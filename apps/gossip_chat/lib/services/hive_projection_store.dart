import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gossip_event_sourcing/gossip_event_sourcing.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// Hive-based implementation of ProjectionStore for Flutter applications
///
/// This implementation uses Hive to persist projection states to disk,
/// enabling fast startup times by avoiding full event replay when possible.
///
/// The store uses two Hive boxes:
/// - projectionStatesBox: Stores the actual projection states
/// - projectionMetadataBox: Stores metadata about each projection state
///
/// Each projection state is versioned to handle schema changes gracefully.
class HiveProjectionStore implements ProjectionStore {
  static const String _projectionStatesBoxName = 'projection_states';
  static const String _projectionMetadataBoxName = 'projection_metadata';
  static const String _currentVersion = '1.0.0';

  Box<Map<dynamic, dynamic>>? _projectionStatesBox;
  Box<Map<dynamic, dynamic>>? _projectionMetadataBox;
  bool _isInitialized = false;
  bool _isClosed = false;

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize Hive if not already done
      if (!Hive.isAdapterRegistered(0)) {
        await Hive.initFlutter();
      }

      // Get app documents directory for Hive storage
      if (!kIsWeb) {
        final appDocDir = await getApplicationDocumentsDirectory();
        final hivePath = '${appDocDir.path}/hive_projections';

        // Create directory if it doesn't exist
        final dir = Directory(hivePath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }

        Hive.init(hivePath);
      }

      // Open boxes
      _projectionStatesBox = await Hive.openBox<Map<dynamic, dynamic>>(
        _projectionStatesBoxName,
      );
      _projectionMetadataBox = await Hive.openBox<Map<dynamic, dynamic>>(
        _projectionMetadataBoxName,
      );

      _isInitialized = true;
      debugPrint('✅ HiveProjectionStore initialized successfully');
    } catch (e) {
      throw ProjectionStoreException(
        'Failed to initialize Hive projection store',
        e,
      );
    }
  }

  void _ensureInitialized() {
    if (!_isInitialized || _isClosed) {
      throw const ProjectionStoreException(
        'ProjectionStore is not initialized or has been closed',
      );
    }
  }

  @override
  Future<void> saveProjectionState(
    String projectionType,
    Map<String, dynamic> state,
    String? lastProcessedEventId,
    int eventCount,
  ) async {
    _ensureInitialized();

    try {
      final now = DateTime.now();
      final snapshot = ProjectionStateSnapshot(
        projectionType: projectionType,
        state: state,
        lastProcessedEventId: lastProcessedEventId,
        eventCount: eventCount,
        savedAt: now,
        version: _currentVersion,
      );

      // Save the full state
      await _projectionStatesBox!.put(projectionType, snapshot.toJson());

      // Save metadata separately for efficient queries
      final metadata = {
        'projectionType': projectionType,
        'lastProcessedEventId': lastProcessedEventId,
        'eventCount': eventCount,
        'savedAt': now.toIso8601String(),
        'version': _currentVersion,
      };
      await _projectionMetadataBox!.put(projectionType, metadata);

      debugPrint(
        '💾 Saved projection state for $projectionType '
        '($eventCount events, last: ${lastProcessedEventId?.substring(0, 8)}...)',
      );
    } catch (e) {
      throw ProjectionStoreException(
        'Failed to save projection state for $projectionType',
        e,
      );
    }
  }

  @override
  Future<ProjectionStateSnapshot?> loadProjectionState(
    String projectionType,
  ) async {
    _ensureInitialized();

    try {
      final stateData = _projectionStatesBox!.get(projectionType);
      if (stateData == null) {
        debugPrint('📂 No saved state found for projection $projectionType');
        return null;
      }

      final snapshot = ProjectionStateSnapshot.fromJson(
        Map<String, dynamic>.from(stateData),
      );

      debugPrint(
        '📂 Loaded projection state for $projectionType '
        '(${snapshot.eventCount} events, saved: ${snapshot.savedAt})',
      );

      return snapshot;
    } catch (e) {
      debugPrint('⚠️ Failed to load projection state for $projectionType: $e');
      // Don't throw - return null to fall back to event replay
      return null;
    }
  }

  @override
  Future<void> clearProjectionState(String projectionType) async {
    _ensureInitialized();

    try {
      await _projectionStatesBox!.delete(projectionType);
      await _projectionMetadataBox!.delete(projectionType);
      debugPrint('🗑️ Cleared projection state for $projectionType');
    } catch (e) {
      throw ProjectionStoreException(
        'Failed to clear projection state for $projectionType',
        e,
      );
    }
  }

  @override
  Future<void> clearAllProjectionStates() async {
    _ensureInitialized();

    try {
      await _projectionStatesBox!.clear();
      await _projectionMetadataBox!.clear();
      debugPrint('🗑️ Cleared all projection states');
    } catch (e) {
      throw ProjectionStoreException(
        'Failed to clear all projection states',
        e,
      );
    }
  }

  @override
  Future<List<ProjectionStateMetadata>> getAllProjectionMetadata() async {
    _ensureInitialized();

    try {
      final List<ProjectionStateMetadata> metadata = [];

      for (final key in _projectionMetadataBox!.keys) {
        final data = _projectionMetadataBox!.get(key);
        if (data != null) {
          metadata.add(
            ProjectionStateMetadata(
              projectionType: data['projectionType'] as String,
              lastProcessedEventId: data['lastProcessedEventId'] as String?,
              eventCount: data['eventCount'] as int,
              savedAt: DateTime.parse(data['savedAt'] as String),
              version: data['version'] as String? ?? '1.0.0',
            ),
          );
        }
      }

      return metadata;
    } catch (e) {
      throw ProjectionStoreException('Failed to get projection metadata', e);
    }
  }

  @override
  Future<bool> hasProjectionState(String projectionType) async {
    _ensureInitialized();
    return _projectionStatesBox!.containsKey(projectionType);
  }

  @override
  Future<void> close() async {
    if (!_isInitialized || _isClosed) return;

    try {
      await _projectionStatesBox?.close();
      await _projectionMetadataBox?.close();
      _isClosed = true;
      _isInitialized = false;
      debugPrint('🔒 HiveProjectionStore closed successfully');
    } catch (e) {
      throw ProjectionStoreException('Failed to close HiveProjectionStore', e);
    }
  }

  @override
  ProjectionStoreStats getStats() {
    if (!_isInitialized || _isClosed) {
      return const ProjectionStoreStats(
        totalProjections: 0,
        totalStates: 0,
        additionalStats: {'status': 'closed'},
      );
    }

    final totalStates = _projectionStatesBox?.length ?? 0;
    DateTime? lastSaveTime;

    // Find the most recent save time
    if (_projectionMetadataBox != null && _projectionMetadataBox!.isNotEmpty) {
      DateTime? latest;
      for (final key in _projectionMetadataBox!.keys) {
        final data = _projectionMetadataBox!.get(key);
        if (data != null && data['savedAt'] != null) {
          final savedAt = DateTime.parse(data['savedAt'] as String);
          if (latest == null || savedAt.isAfter(latest)) {
            latest = savedAt;
          }
        }
      }
      lastSaveTime = latest;
    }

    return ProjectionStoreStats(
      totalProjections: totalStates,
      totalStates: totalStates,
      lastSaveTime: lastSaveTime,
      additionalStats: {
        'storageBackend': 'Hive',
        'statesBoxName': _projectionStatesBoxName,
        'metadataBoxName': _projectionMetadataBoxName,
        'statesBoxPath': _projectionStatesBox?.path,
        'metadataBoxPath': _projectionMetadataBox?.path,
      },
    );
  }
}
