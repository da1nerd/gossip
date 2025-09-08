import 'package:flutter_test/flutter_test.dart';
import 'package:gossip/gossip.dart';
import 'package:gossip_event_sourcing/gossip_event_sourcing.dart';
import 'package:gossip_chat_demo/services/event_sourcing/projections/chat_projection.dart';

import 'package:gossip_chat_demo/models/chat_events.dart';

void main() {
  group('Event Sourcing Integration Tests', () {
    late EventProcessor eventProcessor;
    late ChatProjection chatProjection;
    late InMemoryProjectionStore projectionStore;

    setUp(() async {
      // Create in-memory projection store for testing
      projectionStore = InMemoryProjectionStore();
      await projectionStore.initialize();

      // Create event processor with projection store
      eventProcessor = EventProcessor(
        projectionStore: projectionStore,
        storeConfig: const ProjectionStoreConfig(
          autoSaveEnabled: true,
          autoSaveInterval: 3, // Save every 3 events for testing
          saveAfterBatch: true,
          loadOnRebuild: true,
        ),
      );

      // Create and register chat projection
      chatProjection = ChatProjection();
      eventProcessor.registerProjection(chatProjection);

      // Register typed events
      ChatEventRegistry.registerAll();
    });

    tearDown(() async {
      eventProcessor.dispose();
      await projectionStore.close();
    });

    test('processes chat events and builds projection state', () async {
      // Create some test events
      final events = [
        Event(
          id: 'event1',
          nodeId: 'user1',
          timestamp: 1,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'chat_message',
            'senderId': 'user1',
            'senderName': 'Alice',
            'content': 'Hello world!',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        ),
        Event(
          id: 'event2',
          nodeId: 'user2',
          timestamp: 2,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'user_joined',
            'userId': 'user2',
            'userName': 'Bob',
          },
        ),
      ];

      // Process events
      await eventProcessor.processEvents(events);

      // Verify projection state
      expect(chatProjection.messageCount, equals(1));
      expect(chatProjection.userCount, equals(1));
      expect(chatProjection.messages.first.content, equals('Hello world!'));
      expect(chatProjection.messages.first.senderName, equals('Alice'));
    });

    test('saves and restores projection state correctly', () async {
      // Create test events
      final events = [
        Event(
          id: 'event1',
          nodeId: 'user1',
          timestamp: 1,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'chat_message',
            'senderId': 'user1',
            'senderName': 'Alice',
            'content': 'First message',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        ),
        Event(
          id: 'event2',
          nodeId: 'user2',
          timestamp: 2,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'user_joined',
            'userId': 'user2',
            'userName': 'Bob',
          },
        ),
        Event(
          id: 'event3',
          nodeId: 'user1',
          timestamp: 3,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'chat_message',
            'senderId': 'user1',
            'senderName': 'Alice',
            'content': 'Second message',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        ),
        Event(
          id: 'event4',
          nodeId: 'user2',
          timestamp: 4,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'chat_message',
            'senderId': 'user2',
            'senderName': 'Bob',
            'content': 'Third message',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        ),
      ];

      // Process events (should trigger auto-save after 3 events)
      await eventProcessor.processEvents(events);

      // Verify initial state
      expect(chatProjection.messageCount, equals(3));
      expect(chatProjection.userCount, equals(1));

      // Verify projection store has saved states
      final stats = eventProcessor.getProjectionStoreStats();
      expect(stats!.totalStates, greaterThan(0));
      expect(stats.lastSaveTime, isNotNull);

      // Create new event processor and projection to simulate app restart
      final newEventProcessor = EventProcessor(
        projectionStore: projectionStore,
        storeConfig: const ProjectionStoreConfig(),
      );

      final newChatProjection = ChatProjection();
      newEventProcessor.registerProjection(newChatProjection);

      // Rebuild projections (should load from saved state)
      await newEventProcessor.rebuildProjections(events);

      // Verify state was restored correctly
      expect(newChatProjection.messageCount, equals(3));
      expect(newChatProjection.userCount, equals(1));
      expect(newChatProjection.messages.length, equals(3));
      expect(newChatProjection.messages.first.content, equals('First message'));
      expect(newChatProjection.messages.last.content, equals('Third message'));

      // Clean up
      newEventProcessor.dispose();
    });

    test('handles projection store failures gracefully', () async {
      // Create a failing projection store
      final failingStore = FailingProjectionStore();
      await failingStore.initialize();

      final failingEventProcessor = EventProcessor(
        projectionStore: failingStore,
        storeConfig: const ProjectionStoreConfig(),
      );

      final testProjection = ChatProjection();
      failingEventProcessor.registerProjection(testProjection);

      final events = [
        Event(
          id: 'event1',
          nodeId: 'user1',
          timestamp: 1,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'chat_message',
            'senderId': 'user1',
            'senderName': 'Alice',
            'content': 'Test message',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        ),
      ];

      // Should process events normally even if projection store fails
      await failingEventProcessor.processEvents(events);
      expect(testProjection.messageCount, equals(1));

      // Should fall back to event replay when projection store fails
      await failingEventProcessor.rebuildProjections(events);
      expect(testProjection.messageCount, equals(1));

      failingEventProcessor.dispose();
      await failingStore.close();
    });

    test('manages multiple projections correctly', () async {
      // Create a second projection for testing
      final secondProjection = ChatProjection();
      eventProcessor.registerProjection(secondProjection);

      final events = [
        Event(
          id: 'event1',
          nodeId: 'user1',
          timestamp: 1,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'chat_message',
            'senderId': 'user1',
            'senderName': 'Alice',
            'content': 'Test message',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        ),
      ];

      await eventProcessor.processEvents(events);

      // Both projections should have the same state
      expect(chatProjection.messageCount, equals(1));
      expect(secondProjection.messageCount, equals(1));
      expect(chatProjection.messages.first.content, equals('Test message'));
      expect(secondProjection.messages.first.content, equals('Test message'));

      // Unregister second projection
      eventProcessor.unregisterProjection(secondProjection);
      expect(eventProcessor.projections.length, equals(1));
    });
  });
}

/// Simple in-memory projection store for testing
class InMemoryProjectionStore implements ProjectionStore {
  final Map<String, ProjectionStateSnapshot> _states = {};

  @override
  Future<void> initialize() async {
    // Initialization complete
  }

  @override
  Future<void> saveProjectionState(
    String projectionType,
    Map<String, dynamic> state,
    String? lastProcessedEventId,
    int eventCount,
  ) async {
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
    return _states[projectionType];
  }

  @override
  Future<void> clearProjectionState(String projectionType) async {
    _states.remove(projectionType);
  }

  @override
  Future<void> clearAllProjectionStates() async {
    _states.clear();
  }

  @override
  Future<List<ProjectionStateMetadata>> getAllProjectionMetadata() async {
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
    return _states.containsKey(projectionType);
  }

  @override
  Future<void> close() async {
    _states.clear();
    // Store closed
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
        'storageType': 'in-memory-test',
        'projectionTypes': _states.keys.toList(),
      },
    );
  }
}

/// Projection store that always fails (for testing error handling)
class FailingProjectionStore implements ProjectionStore {
  @override
  Future<void> initialize() async {
    // Initialize successfully
  }

  @override
  Future<void> saveProjectionState(
    String projectionType,
    Map<String, dynamic> state,
    String? lastProcessedEventId,
    int eventCount,
  ) async {
    throw const ProjectionStoreException('Save failed');
  }

  @override
  Future<ProjectionStateSnapshot?> loadProjectionState(
    String projectionType,
  ) async {
    throw const ProjectionStoreException('Load failed');
  }

  @override
  Future<void> clearProjectionState(String projectionType) async {
    throw const ProjectionStoreException('Clear failed');
  }

  @override
  Future<void> clearAllProjectionStates() async {
    throw const ProjectionStoreException('Clear all failed');
  }

  @override
  Future<List<ProjectionStateMetadata>> getAllProjectionMetadata() async {
    throw const ProjectionStoreException('Get metadata failed');
  }

  @override
  Future<bool> hasProjectionState(String projectionType) async {
    throw const ProjectionStoreException('Has projection failed');
  }

  @override
  Future<void> close() async {
    // Close successfully
  }

  @override
  ProjectionStoreStats getStats() {
    return const ProjectionStoreStats(
      totalProjections: 0,
      totalStates: 0,
      additionalStats: {'status': 'failing'},
    );
  }
}
