import 'dart:async';
import 'package:gossip/gossip.dart';

import 'projection.dart';
import 'projection_store.dart';

/// Coordinates processing of events to update projections.
/// This is the core of the Event Sourcing architecture.
///
/// Enhanced with optional projection store support for improved performance
/// when dealing with large numbers of events.
class EventProcessor {
  final List<Projection> _projections = [];
  final Set<String> _processedEvents = {};
  final ProjectionStore? _projectionStore;

  /// Configuration for projection store behavior
  final ProjectionStoreConfig _storeConfig;

  /// Track events processed since last save (for auto-save functionality)
  final Map<String, int> _eventsSinceLastSave = {};

  /// Optional logger function for debugging/monitoring
  final void Function(String message)? _logger;

  EventProcessor({
    ProjectionStore? projectionStore,
    ProjectionStoreConfig? storeConfig,
    void Function(String message)? logger,
  }) : _projectionStore = projectionStore,
       _storeConfig = storeConfig ?? const ProjectionStoreConfig(),
       _logger = logger;

  void _log(String message) {
    _logger?.call(message);
  }

  /// Register a projection to be updated when events are processed
  void registerProjection(Projection projection) {
    _projections.add(projection);
    _log('📋 EventProcessor: Registered projection ${projection.runtimeType}');
  }

  /// Unregister a projection
  void unregisterProjection(Projection projection) {
    _projections.remove(projection);
    _eventsSinceLastSave.remove(projection.runtimeType.toString());
    _log(
      '📋 EventProcessor: Unregistered projection ${projection.runtimeType}',
    );
  }

  /// Process a single event through all projections
  Future<void> processEvent(Event event) async {
    // Skip if already processed (idempotency)
    if (_processedEvents.contains(event.id)) {
      _log('⏭️  EventProcessor: Skipping already processed event ${event.id}');
      return;
    }

    _log(
      '⚙️  EventProcessor: Processing event ${event.id} through ${_projections.length} projections',
    );

    // Process through all projections
    for (final projection in _projections) {
      try {
        await projection.apply(event);

        // Track events processed for auto-save
        if (_projectionStore != null && _storeConfig.autoSaveEnabled) {
          final projectionType = projection.runtimeType.toString();
          _eventsSinceLastSave[projectionType] =
              (_eventsSinceLastSave[projectionType] ?? 0) + 1;
        }
      } catch (e, stackTrace) {
        _log(
          '❌ EventProcessor: Error applying event ${event.id} to ${projection.runtimeType}: $e',
        );
        _log(stackTrace.toString());
        // Continue processing other projections even if one fails
      }
    }

    _processedEvents.add(event.id);

    // Auto-save projection states if configured
    if (_projectionStore != null && _storeConfig.autoSaveEnabled) {
      await _checkAutoSave(event.id);
    }

    _log('✅ EventProcessor: Finished processing event ${event.id}');
  }

  /// Process multiple events in order
  Future<void> processEvents(List<Event> events) async {
    if (events.isEmpty) {
      _log('📝 EventProcessor: No events to process');
      return;
    }

    _log('📝 EventProcessor: Processing ${events.length} events');

    // Sort by creation timestamp to ensure proper ordering
    events.sort((a, b) => a.creationTimestamp.compareTo(b.creationTimestamp));

    for (final event in events) {
      await processEvent(event);
    }

    // Save projection states after processing batch if configured
    if (_projectionStore != null && _storeConfig.saveAfterBatch) {
      await _saveAllProjectionStates(events.isNotEmpty ? events.last.id : null);
    }

    _log('✅ EventProcessor: Finished processing ${events.length} events');
  }

  /// Rebuild projections from events, optionally using saved projection states
  /// This is the enhanced version that can leverage projection stores for performance
  Future<void> rebuildProjections(List<Event> allEvents) async {
    _log(
      '🔄 EventProcessor: Rebuilding projections from ${allEvents.length} events',
    );

    // Clear processed events cache
    _processedEvents.clear();

    // Sort events by timestamp
    allEvents.sort(
      (a, b) => a.creationTimestamp.compareTo(b.creationTimestamp),
    );

    // Try to load saved projection states if projection store is available
    if (_projectionStore != null && _storeConfig.loadOnRebuild) {
      final bool usedSavedStates = await _tryLoadSavedStates(allEvents);
      if (usedSavedStates) {
        return; // Successfully loaded from saved states
      }
    }

    // Fallback to full event replay
    await _rebuildFromEvents(allEvents);
  }

  /// Try to load projections from saved states
  Future<bool> _tryLoadSavedStates(List<Event> allEvents) async {
    _log('🔍 EventProcessor: Attempting to load projections from saved states');

    bool allProjectionsLoaded = true;
    String? latestEventId;

    for (final projection in _projections) {
      final projectionType = projection.runtimeType.toString();

      try {
        final snapshot = await _projectionStore!.loadProjectionState(
          projectionType,
        );

        if (snapshot == null) {
          _log('📂 No saved state for $projectionType');
          allProjectionsLoaded = false;
          continue;
        }

        // Check version compatibility
        if (!projection.isStateCompatible(snapshot.version)) {
          _log(
            '⚠️ Saved state version ${snapshot.version} incompatible with projection version ${projection.stateVersion} for $projectionType',
          );
          allProjectionsLoaded = false;
          continue;
        }

        // Attempt to restore the state
        final restored = await projection.restoreState(snapshot.state);
        if (!restored) {
          _log('❌ Failed to restore state for $projectionType');
          allProjectionsLoaded = false;
          continue;
        }

        // Track the latest processed event ID
        if (snapshot.lastProcessedEventId != null) {
          if (latestEventId == null) {
            latestEventId = snapshot.lastProcessedEventId;
          } else {
            // Find the latest event by comparing timestamps
            Event? currentEvent;
            Event? snapshotEvent;

            for (final event in allEvents) {
              if (event.id == latestEventId) {
                currentEvent = event;
              }
              if (event.id == snapshot.lastProcessedEventId) {
                snapshotEvent = event;
              }
            }

            if (snapshotEvent != null &&
                currentEvent != null &&
                snapshotEvent.creationTimestamp >
                    currentEvent.creationTimestamp) {
              latestEventId = snapshot.lastProcessedEventId;
            }
          }
        }

        _log(
          '✅ Loaded projection $projectionType from saved state (${snapshot.eventCount} events processed)',
        );
      } catch (e) {
        _log('❌ Error loading saved state for $projectionType: $e');
        allProjectionsLoaded = false;
      }
    }

    if (!allProjectionsLoaded) {
      _log(
        '⚠️ Not all projections could be loaded from saved states, falling back to event replay',
      );
      // Reset all projections since we need consistent state
      for (final projection in _projections) {
        await projection.reset();
      }
      return false;
    }

    // Process any events that occurred after the last saved state
    if (latestEventId != null) {
      final lastEventIndex = allEvents.indexWhere((e) => e.id == latestEventId);
      if (lastEventIndex != -1 && lastEventIndex < allEvents.length - 1) {
        final eventsToProcess = allEvents.skip(lastEventIndex + 1).toList();
        _log(
          '📝 Processing ${eventsToProcess.length} events that occurred after last saved state',
        );
        await processEvents(eventsToProcess);
      }
    }

    _log('✅ Successfully loaded all projections from saved states');
    return true;
  }

  /// Rebuild projections from events (traditional approach)
  Future<void> _rebuildFromEvents(List<Event> allEvents) async {
    _log('🔄 Rebuilding projections from events (full replay)');

    // Reset all projections to initial state
    for (final projection in _projections) {
      try {
        await projection.reset();
        _log('🔄 EventProcessor: Reset projection ${projection.runtimeType}');
      } catch (e, stackTrace) {
        _log('❌ EventProcessor: Error resetting ${projection.runtimeType}: $e');
        _log(stackTrace.toString());
      }
    }

    // Process all events in chronological order
    await processEvents(allEvents);

    _log('✅ EventProcessor: Finished rebuilding all projections');
  }

  /// Save all projection states to the store
  Future<void> saveAllProjectionStates([String? lastProcessedEventId]) async {
    if (_projectionStore == null) {
      _log('⚠️ No projection store configured, cannot save states');
      return;
    }

    await _saveAllProjectionStates(lastProcessedEventId);
  }

  Future<void> _saveAllProjectionStates([String? lastProcessedEventId]) async {
    _log('💾 Saving all projection states');

    for (final projection in _projections) {
      try {
        final projectionType = projection.runtimeType.toString();
        final state = projection.getState();
        final eventCount = _processedEvents.length;

        await _projectionStore!.saveProjectionState(
          projectionType,
          state,
          lastProcessedEventId,
          eventCount,
        );

        // Reset the counter for this projection
        _eventsSinceLastSave[projectionType] = 0;
      } catch (e) {
        _log('❌ Error saving state for ${projection.runtimeType}: $e');
      }
    }
  }

  /// Check if projections should be auto-saved
  Future<void> _checkAutoSave(String eventId) async {
    for (final entry in _eventsSinceLastSave.entries) {
      if (entry.value >= _storeConfig.autoSaveInterval) {
        await _saveAllProjectionStates(eventId);
        break; // Only save once per batch of events
      }
    }
  }

  /// Clear all saved projection states
  Future<void> clearSavedProjectionStates() async {
    if (_projectionStore == null) {
      _log('⚠️ No projection store configured');
      return;
    }

    try {
      await _projectionStore!.clearAllProjectionStates();
      _log('🗑️ Cleared all saved projection states');
    } catch (e) {
      _log('❌ Error clearing saved projection states: $e');
    }
  }

  /// Get a projection by type
  T? getProjection<T extends Projection>() {
    try {
      return _projections.whereType<T>().first;
    } catch (e) {
      return null;
    }
  }

  /// Get all registered projections
  List<Projection> get projections => List.unmodifiable(_projections);

  /// Get count of processed events (for debugging/monitoring)
  int get processedEventCount => _processedEvents.length;

  /// Check if projection store is available
  bool get hasProjectionStore => _projectionStore != null;

  /// Get projection store statistics
  ProjectionStoreStats? getProjectionStoreStats() {
    return _projectionStore?.getStats();
  }

  /// Clear processed events cache (useful for testing)
  void clearProcessedEventsCache() {
    _processedEvents.clear();
    _eventsSinceLastSave.clear();
    _log('🧹 EventProcessor: Cleared processed events cache');
  }

  /// Dispose of the event processor
  void dispose() {
    for (final projection in _projections) {
      projection.dispose();
    }
    _projections.clear();
    _processedEvents.clear();
    _eventsSinceLastSave.clear();
    _log('🔒 EventProcessor: Disposed');
  }

  /// Get current state of all projections (for debugging)
  Map<String, Map<String, dynamic>> getAllProjectionStates() {
    final Map<String, Map<String, dynamic>> states = {};
    for (final projection in _projections) {
      try {
        states[projection.runtimeType.toString()] = projection.getState();
      } catch (e) {
        states[projection.runtimeType.toString()] = {'error': e.toString()};
      }
    }
    return states;
  }
}

/// Configuration for projection store behavior
class ProjectionStoreConfig {
  /// Whether to automatically save projection states periodically
  final bool autoSaveEnabled;

  /// Number of events to process before auto-saving
  final int autoSaveInterval;

  /// Whether to save projection states after processing a batch of events
  final bool saveAfterBatch;

  /// Whether to attempt loading projection states when rebuilding
  final bool loadOnRebuild;

  const ProjectionStoreConfig({
    this.autoSaveEnabled = true,
    this.autoSaveInterval = 100, // Save every 100 events by default
    this.saveAfterBatch = true,
    this.loadOnRebuild = true,
  });

  /// Configuration for high-performance scenarios (less frequent saves)
  const ProjectionStoreConfig.highPerformance()
    : autoSaveEnabled = true,
      autoSaveInterval = 500,
      saveAfterBatch = false,
      loadOnRebuild = true;

  /// Configuration for maximum durability (frequent saves)
  const ProjectionStoreConfig.maxDurability()
    : autoSaveEnabled = true,
      autoSaveInterval = 50,
      saveAfterBatch = true,
      loadOnRebuild = true;

  /// Configuration that disables projection store features
  const ProjectionStoreConfig.disabled()
    : autoSaveEnabled = false,
      autoSaveInterval = 0,
      saveAfterBatch = false,
      loadOnRebuild = false;
}
