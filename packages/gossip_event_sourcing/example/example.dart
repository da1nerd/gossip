/// Example demonstrating the gossip_event_sourcing library
///
/// This example shows how to:
/// - Create custom projections
/// - Set up event processing
/// - Use projection stores for performance
/// - Handle state restoration
/// - Monitor projection states

import 'dart:async';
import 'package:gossip/gossip.dart';
import 'package:gossip_event_sourcing/gossip_event_sourcing.dart';

void main() async {
  print('🚀 Starting Gossip Event Sourcing Example');

  // Create a simple in-memory projection store
  final projectionStore = InMemoryProjectionStore();
  await projectionStore.initialize();

  // Create event processor with projection store
  final eventProcessor = EventProcessor(
    projectionStore: projectionStore,
    storeConfig: const ProjectionStoreConfig(
      autoSaveEnabled: true,
      autoSaveInterval: 5, // Save every 5 events for demo
      saveAfterBatch: true,
      loadOnRebuild: true,
    ),
    logger: (message) => print('[EventProcessor] $message'),
  );

  // Create and register projections
  final counterProjection = CounterProjection();
  final historyProjection = EventHistoryProjection();

  eventProcessor.registerProjection(counterProjection);
  eventProcessor.registerProjection(historyProjection);

  // Listen to projection changes
  counterProjection.addListener(() {
    print('📊 Counter: ${counterProjection.count}');
  });

  historyProjection.addListener(() {
    print('📜 Event history: ${historyProjection.eventCount} events');
  });

  // Simulate processing some events
  print('\n--- Processing initial events ---');
  final events = [
    createSimpleEvent('1', {'type': 'increment', 'value': 1}),
    createSimpleEvent('2', {'type': 'increment', 'value': 3}),
    createSimpleEvent('3', {'type': 'decrement', 'value': 1}),
    createSimpleEvent('4', {'type': 'increment', 'value': 2}),
    createSimpleEvent('5', {'type': 'user_action', 'action': 'clicked_button'}),
    createSimpleEvent('6', {'type': 'increment', 'value': 1}),
    createSimpleEvent('7', {'type': 'user_action', 'action': 'opened_menu'}),
  ];

  // Process events one by one
  for (final event in events) {
    await eventProcessor.processEvent(event);
    await Future.delayed(
      Duration(milliseconds: 100),
    ); // Simulate time between events
  }

  print('\n--- Final state after processing ---');
  print('Counter: ${counterProjection.count}');
  print('Total events processed: ${historyProjection.eventCount}');
  print('User actions: ${historyProjection.userActionCount}');

  // Get projection store stats
  final stats = eventProcessor.getProjectionStoreStats();
  if (stats != null) {
    print('\n--- Projection Store Stats ---');
    print('Total saved states: ${stats.totalStates}');
    print('Last save time: ${stats.lastSaveTime}');
  }

  // Simulate app restart by creating a new event processor
  print('\n--- Simulating app restart ---');
  final newEventProcessor = EventProcessor(
    projectionStore: projectionStore,
    storeConfig: const ProjectionStoreConfig(),
    logger: (message) => print('[NewEventProcessor] $message'),
  );

  // Create new projection instances
  final newCounterProjection = CounterProjection();
  final newHistoryProjection = EventHistoryProjection();

  newEventProcessor.registerProjection(newCounterProjection);
  newEventProcessor.registerProjection(newHistoryProjection);

  // This should load from saved states instead of replaying all events
  await newEventProcessor.rebuildProjections(events);

  print('\n--- State after restart (should match previous) ---');
  print('Counter: ${newCounterProjection.count}');
  print('Total events processed: ${newHistoryProjection.eventCount}');
  print('User actions: ${newHistoryProjection.userActionCount}');

  // Process a few more events to show incremental updates work
  print('\n--- Processing additional events after restart ---');
  final moreEvents = [
    createSimpleEvent('8', {'type': 'increment', 'value': 5}),
    createSimpleEvent('9', {'type': 'user_action', 'action': 'logged_out'}),
  ];

  for (final event in moreEvents) {
    await newEventProcessor.processEvent(event);
  }

  print('\n--- Final state ---');
  print('Counter: ${newCounterProjection.count}');
  print('Total events processed: ${newHistoryProjection.eventCount}');
  print('User actions: ${newHistoryProjection.userActionCount}');

  // Clean up
  eventProcessor.dispose();
  newEventProcessor.dispose();
  await projectionStore.close();

  print('\n✅ Example completed successfully!');
}

/// Helper function to create simple events for the example
Event createSimpleEvent(String id, Map<String, dynamic> payload) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return Event(
    id: id,
    nodeId: 'example-node',
    timestamp: now,
    creationTimestamp: now,
    payload: payload,
  );
}

/// Example counter projection that tracks increment/decrement events
class CounterProjection extends Projection with ProjectionChangeNotifier {
  int _count = 0;

  int get count => _count;

  @override
  String get stateVersion => '1.0.0';

  @override
  Future<void> apply(Event event) async {
    final type = event.payload['type'] as String?;

    switch (type) {
      case 'increment':
        final value = event.payload['value'] as int? ?? 1;
        _count += value;
        notifyListeners();
        break;

      case 'decrement':
        final value = event.payload['value'] as int? ?? 1;
        _count -= value;
        notifyListeners();
        break;
    }
  }

  @override
  Future<void> reset() async {
    _count = 0;
    notifyListeners();
  }

  @override
  Map<String, dynamic> getState() {
    return {'count': _count};
  }

  @override
  Future<bool> restoreState(Map<String, dynamic> state) async {
    try {
      _count = state['count'] as int;
      notifyListeners();
      return true;
    } catch (e) {
      await reset();
      return false;
    }
  }
}

/// Example projection that tracks event history and user actions
class EventHistoryProjection extends Projection with ProjectionChangeNotifier {
  int _eventCount = 0;
  int _userActionCount = 0;
  final List<String> _recentEventTypes = [];

  int get eventCount => _eventCount;
  int get userActionCount => _userActionCount;
  List<String> get recentEventTypes => List.unmodifiable(_recentEventTypes);

  @override
  String get stateVersion => '1.0.0';

  @override
  Future<void> apply(Event event) async {
    _eventCount++;

    final type = event.payload['type'] as String?;
    if (type != null) {
      _recentEventTypes.add(type);
      // Keep only last 10 event types
      if (_recentEventTypes.length > 10) {
        _recentEventTypes.removeAt(0);
      }

      if (type == 'user_action') {
        _userActionCount++;
      }
    }

    notifyListeners();
  }

  @override
  Future<void> reset() async {
    _eventCount = 0;
    _userActionCount = 0;
    _recentEventTypes.clear();
    notifyListeners();
  }

  @override
  Map<String, dynamic> getState() {
    return {
      'eventCount': _eventCount,
      'userActionCount': _userActionCount,
      'recentEventTypes': _recentEventTypes.toList(),
    };
  }

  @override
  Future<bool> restoreState(Map<String, dynamic> state) async {
    try {
      _eventCount = state['eventCount'] as int;
      _userActionCount = state['userActionCount'] as int;
      _recentEventTypes.clear();
      _recentEventTypes.addAll(
        (state['recentEventTypes'] as List).cast<String>(),
      );
      notifyListeners();
      return true;
    } catch (e) {
      await reset();
      return false;
    }
  }
}

/// Simple in-memory projection store for the example
class InMemoryProjectionStore implements ProjectionStore {
  final Map<String, ProjectionStateSnapshot> _states = {};
  bool _isInitialized = false;

  @override
  Future<void> initialize() async {
    _isInitialized = true;
  }

  @override
  Future<void> saveProjectionState(
    String projectionType,
    Map<String, dynamic> state,
    String? lastProcessedEventId,
    int eventCount,
  ) async {
    if (!_isInitialized) throw Exception('Store not initialized');

    _states[projectionType] = ProjectionStateSnapshot(
      projectionType: projectionType,
      state: Map<String, dynamic>.from(state),
      lastProcessedEventId: lastProcessedEventId,
      eventCount: eventCount,
      savedAt: DateTime.now(),
      version: '1.0.0',
    );
  }

  @override
  Future<ProjectionStateSnapshot?> loadProjectionState(
    String projectionType,
  ) async {
    if (!_isInitialized) throw Exception('Store not initialized');
    return _states[projectionType];
  }

  @override
  Future<void> clearProjectionState(String projectionType) async {
    if (!_isInitialized) throw Exception('Store not initialized');
    _states.remove(projectionType);
  }

  @override
  Future<void> clearAllProjectionStates() async {
    if (!_isInitialized) throw Exception('Store not initialized');
    _states.clear();
  }

  @override
  Future<List<ProjectionStateMetadata>> getAllProjectionMetadata() async {
    if (!_isInitialized) throw Exception('Store not initialized');

    return _states.values
        .map(
          (snapshot) => ProjectionStateMetadata(
            projectionType: snapshot.projectionType,
            lastProcessedEventId: snapshot.lastProcessedEventId,
            eventCount: snapshot.eventCount,
            savedAt: snapshot.savedAt,
            version: snapshot.version,
          ),
        )
        .toList();
  }

  @override
  Future<bool> hasProjectionState(String projectionType) async {
    if (!_isInitialized) throw Exception('Store not initialized');
    return _states.containsKey(projectionType);
  }

  @override
  Future<void> close() async {
    _states.clear();
    _isInitialized = false;
  }

  @override
  ProjectionStoreStats getStats() {
    return ProjectionStoreStats(
      totalProjections: _states.length,
      totalStates: _states.length,
      lastSaveTime: _states.values.isNotEmpty
          ? _states.values
                .map((s) => s.savedAt)
                .reduce((a, b) => a.isAfter(b) ? a : b)
          : null,
      additionalStats: {
        'storageType': 'in-memory',
        'projectionTypes': _states.keys.toList(),
      },
    );
  }
}
