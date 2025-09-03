/// Tests for vector clock reset detection and recovery in the gossip protocol.
///
/// This test suite validates that the gossip protocol can correctly handle
/// scenarios where a peer's vector clock is reset (e.g., due to storage loss
/// or system restart) and ensures that new events created after the reset
/// are properly synchronized with other peers.
library;

import 'dart:async';

import 'package:test/test.dart';

import '../../lib/gossip.dart';

/// Mock transport implementation for testing the full gossip protocol.
class MockGossipTransport implements GossipTransport {
  final String nodeId;
  final Map<String, MockGossipTransport> _connections = {};
  final StreamController<IncomingDigest> _digestController =
      StreamController.broadcast();
  final StreamController<IncomingEvents> _eventsController =
      StreamController.broadcast();
  bool _initialized = false;

  MockGossipTransport(this.nodeId);

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  void addConnection(MockGossipTransport other, String peerId) {
    _connections[peerId] = other;
  }

  void removeConnection(String peerId) {
    _connections.remove(peerId);
  }

  @override
  Future<GossipDigestResponse> sendDigest(
    GossipPeer peer,
    GossipDigest digest, {
    Duration? timeout,
  }) async {
    if (!_initialized) throw StateError('Transport not initialized');

    final targetTransport = _connections[peer.id];
    if (targetTransport == null) {
      throw StateError('No connection to peer ${peer.id}');
    }

    // Simulate network delay
    await Future.delayed(Duration(milliseconds: 1));

    // Create incoming digest for the target
    final completer = Completer<GossipDigestResponse>();
    final incoming = IncomingDigest(
      fromPeer: GossipPeer(id: nodeId, address: nodeId),
      digest: digest,
      respond: (response) async {
        completer.complete(response);
      },
    );

    // Deliver the digest to the target transport
    targetTransport._digestController.add(incoming);

    return completer.future.timeout(
      timeout ?? Duration(seconds: 5),
      onTimeout: () => throw TimeoutException('Digest timeout'),
    );
  }

  @override
  Future<void> sendEvents(
    GossipPeer peer,
    GossipEventMessage eventMessage, {
    Duration? timeout,
  }) async {
    if (!_initialized) throw StateError('Transport not initialized');

    final targetTransport = _connections[peer.id];
    if (targetTransport == null) {
      throw StateError('No connection to peer ${peer.id}');
    }

    // Simulate network delay
    await Future.delayed(Duration(milliseconds: 1));

    // Create incoming events for the target
    final incoming = IncomingEvents(
      fromPeer: GossipPeer(id: nodeId, address: nodeId),
      message: eventMessage,
    );

    // Deliver the events to the target transport
    targetTransport._eventsController.add(incoming);
  }

  @override
  Stream<IncomingDigest> get incomingDigests => _digestController.stream;

  @override
  Stream<IncomingEvents> get incomingEvents => _eventsController.stream;

  @override
  Future<List<GossipPeer>> discoverPeers() async {
    return _connections.keys
        .map((id) => GossipPeer(id: id, address: id))
        .toList();
  }

  @override
  Future<bool> isPeerReachable(GossipPeer peer) async {
    return _connections.containsKey(peer.id);
  }

  @override
  Future<void> shutdown() async {
    _initialized = false;
    await _digestController.close();
    await _eventsController.close();
    _connections.clear();
  }

  bool get isInitialized => _initialized;
  List<String> get connectedPeers => _connections.keys.toList();
}

void main() {
  group('Vector Clock Reset Detection', () {
    late GossipNode nodeA;
    late GossipNode nodeB;
    late GossipNode nodeC;
    late MockGossipTransport transportA;
    late MockGossipTransport transportB;
    late MockGossipTransport transportC;
    late MemoryEventStore storeA;
    late MemoryEventStore storeB;
    late MemoryEventStore storeC;

    setUp(() async {
      // Create nodes with mock transport
      storeA = MemoryEventStore();
      storeB = MemoryEventStore();
      storeC = MemoryEventStore();

      transportA = MockGossipTransport('nodeA');
      transportB = MockGossipTransport('nodeB');
      transportC = MockGossipTransport('nodeC');

      nodeA = GossipNode(
        config: GossipConfig(
          nodeId: 'nodeA',
          gossipInterval: Duration(milliseconds: 100),
          fanout: 2,
        ),
        eventStore: storeA,
        transport: transportA,
      );

      nodeB = GossipNode(
        config: GossipConfig(
          nodeId: 'nodeB',
          gossipInterval: Duration(milliseconds: 100),
          fanout: 2,
        ),
        eventStore: storeB,
        transport: transportB,
      );

      nodeC = GossipNode(
        config: GossipConfig(
          nodeId: 'nodeC',
          gossipInterval: Duration(milliseconds: 100),
          fanout: 2,
        ),
        eventStore: storeC,
        transport: transportC,
      );

      // Set up transport connections
      transportA.addConnection(transportB, 'nodeB');
      transportA.addConnection(transportC, 'nodeC');
      transportB.addConnection(transportA, 'nodeA');
      transportB.addConnection(transportC, 'nodeC');
      transportC.addConnection(transportA, 'nodeA');
      transportC.addConnection(transportB, 'nodeB');

      // Start nodes
      await nodeA.start();
      await nodeB.start();
      await nodeC.start();

      // Add peers
      nodeA.addPeer(GossipPeer(id: 'nodeB', address: 'nodeB'));
      nodeA.addPeer(GossipPeer(id: 'nodeC', address: 'nodeC'));
      nodeB.addPeer(GossipPeer(id: 'nodeA', address: 'nodeA'));
      nodeB.addPeer(GossipPeer(id: 'nodeC', address: 'nodeC'));
      nodeC.addPeer(GossipPeer(id: 'nodeA', address: 'nodeA'));
      nodeC.addPeer(GossipPeer(id: 'nodeB', address: 'nodeB'));
    });

    tearDown(() async {
      // Stop nodes first to prevent them from using resources
      await nodeA.stop();
      await nodeB.stop();
      await nodeC.stop();

      // Wait a bit for any pending operations to complete
      await Future.delayed(Duration(milliseconds: 50));

      // Then shutdown transports and close stores
      await transportA.shutdown();
      await transportB.shutdown();
      await transportC.shutdown();
      await storeA.close();
      await storeB.close();
      await storeC.close();
    });

    test('detects and recovers from vector clock reset', () async {
      // Phase 1: Normal operation - create events and sync
      await nodeA.createEvent({'phase': 1, 'message': 'event1'});
      await nodeA.createEvent({'phase': 1, 'message': 'event2'});
      await nodeB.createEvent({'phase': 1, 'message': 'event3'});

      // Allow time for gossip synchronization
      await Future.delayed(Duration(milliseconds: 300));

      // Verify initial synchronization
      final initialEventsA = await storeA.getAllEvents();
      final initialEventsB = await storeB.getAllEvents();
      final initialEventsC = await storeC.getAllEvents();

      expect(initialEventsA.length, equals(3));
      expect(initialEventsB.length, equals(3));
      expect(initialEventsC.length, equals(3));

      // Check vector clock states before reset
      final nodeATimestampBefore = nodeA.vectorClock.getTimestampFor('nodeA');
      final nodeBTimestampBefore = nodeB.vectorClock.getTimestampFor('nodeB');

      expect(nodeATimestampBefore, equals(2)); // Created 2 events
      expect(nodeBTimestampBefore, equals(1)); // Created 1 event

      // Phase 2: Simulate vector clock reset for nodeA
      // This simulates what happens when a node loses its state and restarts
      await nodeA.stop();

      // Create new store instead of clearing the closed one
      storeA = MemoryEventStore();

      // Create a new node with the same ID but fresh vector clock
      nodeA = GossipNode(
        config: GossipConfig(
          nodeId: 'nodeA', // Same node ID
          gossipInterval: Duration(milliseconds: 100),
          fanout: 2,
        ),
        eventStore: storeA,
        transport: transportA,
      );

      await nodeA.start();

      // Re-add peers
      nodeA.addPeer(GossipPeer(id: 'nodeB', address: 'nodeB'));
      nodeA.addPeer(GossipPeer(id: 'nodeC', address: 'nodeC'));

      // Phase 3: Create new events after reset
      // These events will have timestamps 1, 2, 3 despite the fact that
      // other nodes think nodeA should be at timestamp 2 already
      await nodeA.createEvent({'phase': 2, 'message': 'event_after_reset_1'});
      await nodeA.createEvent({'phase': 2, 'message': 'event_after_reset_2'});
      await nodeA.createEvent({'phase': 2, 'message': 'event_after_reset_3'});

      // Phase 4: Trigger gossip and verify recovery
      // Allow time for gossip synchronization with reset detection
      await Future.delayed(Duration(milliseconds: 500));

      // Force gossip exchanges to ensure synchronization
      await nodeA.gossip();
      await nodeB.gossip();
      await nodeC.gossip();

      await Future.delayed(Duration(milliseconds: 200));

      // Verify that all new events from the reset node are synchronized
      final finalEventsA = await storeA.getAllEvents();
      final finalEventsB = await storeB.getAllEvents();
      final finalEventsC = await storeC.getAllEvents();

      // NodeA should have its new events plus events from other nodes
      expect(finalEventsA.length, greaterThanOrEqualTo(3));

      // NodeB and NodeC should have the new events from nodeA after reset
      final nodeAEventsInB =
          finalEventsB.where((e) => e.nodeId == 'nodeA').toList();
      final nodeAEventsInC =
          finalEventsC.where((e) => e.nodeId == 'nodeA').toList();

      expect(nodeAEventsInB.length, equals(3));
      expect(nodeAEventsInC.length, equals(3));

      // Verify the content of the reset events
      final resetEvents =
          nodeAEventsInB.where((e) => e.payload['phase'] == 2).toList();

      expect(resetEvents.length, equals(3));
      expect(
          resetEvents.any((e) => e.payload['message'] == 'event_after_reset_1'),
          isTrue);
      expect(
          resetEvents.any((e) => e.payload['message'] == 'event_after_reset_2'),
          isTrue);
      expect(
          resetEvents.any((e) => e.payload['message'] == 'event_after_reset_3'),
          isTrue);

      // Verify that timestamps are correct for the reset events
      resetEvents.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      expect(resetEvents[0].timestamp, equals(1));
      expect(resetEvents[1].timestamp, equals(2));
      expect(resetEvents[2].timestamp, equals(3));
    });

    test('handles partial vector clock reset with mixed event history',
        () async {
      // Create initial events
      await nodeA.createEvent({'type': 'initial', 'data': 'A1'});
      await nodeB.createEvent({'type': 'initial', 'data': 'B1'});
      await nodeC.createEvent({'type': 'initial', 'data': 'C1'});

      await Future.delayed(Duration(milliseconds: 300));

      // Simulate nodeB going offline and losing some events
      await nodeB.stop();

      // Remove only some events from nodeB to simulate partial data loss
      final allEventsB = await storeB.getAllEvents();

      // Create new store and restore only events from other nodes
      storeB = MemoryEventStore();

      // Restore only events from other nodes, simulating that nodeB lost its own events
      for (final event in allEventsB) {
        if (event.nodeId != 'nodeB') {
          await storeB.saveEvent(event);
        }
      }

      // Restart nodeB with compromised state
      nodeB = GossipNode(
        config: GossipConfig(
          nodeId: 'nodeB',
          gossipInterval: Duration(milliseconds: 100),
          fanout: 2,
        ),
        eventStore: storeB,
        transport: transportB,
      );

      await nodeB.start();
      nodeB.addPeer(GossipPeer(id: 'nodeA', address: 'nodeA'));
      nodeB.addPeer(GossipPeer(id: 'nodeC', address: 'nodeC'));

      // Create new events after partial reset
      await nodeB.createEvent({'type': 'post_reset', 'data': 'B2'});
      await nodeB.createEvent({'type': 'post_reset', 'data': 'B3'});

      // Allow synchronization
      await Future.delayed(Duration(milliseconds: 500));

      // Verify that the new events are synchronized
      final finalEventsA = await storeA.getAllEvents();
      final finalEventsC = await storeC.getAllEvents();

      final nodeBEventsInA =
          finalEventsA.where((e) => e.nodeId == 'nodeB').toList();
      final nodeBEventsInC =
          finalEventsC.where((e) => e.nodeId == 'nodeB').toList();

      // Should have both the original event and the new post-reset events
      expect(nodeBEventsInA.length, greaterThanOrEqualTo(2));
      expect(nodeBEventsInC.length, greaterThanOrEqualTo(2));

      final postResetEvents = nodeBEventsInA
          .where((e) => e.payload['type'] == 'post_reset')
          .toList();

      expect(postResetEvents.length, equals(2));
    });

    test('prevents duplicate event processing during reset recovery', () async {
      final receivedEvents = <Event>[];

      // Listen for events on nodeB
      nodeB.onEventReceived.listen((receivedEvent) {
        receivedEvents.add(receivedEvent.event);
      });

      // Create events and sync
      await nodeA.createEvent({'id': 'unique_event_1', 'data': 'test'});
      await Future.delayed(Duration(milliseconds: 200));

      // Reset nodeA and recreate the same event (shouldn't happen in practice, but test resilience)
      await nodeA.stop();

      // Create new store instead of clearing
      storeA = MemoryEventStore();

      nodeA = GossipNode(
        config: GossipConfig(
          nodeId: 'nodeA',
          gossipInterval: Duration(milliseconds: 100),
          fanout: 2,
        ),
        eventStore: storeA,
        transport: transportA,
      );

      await nodeA.start();
      nodeA.addPeer(GossipPeer(id: 'nodeB', address: 'nodeB'));

      // Create event with same payload but different ID (normal case after reset)
      await nodeA
          .createEvent({'id': 'unique_event_2', 'data': 'test_after_reset'});

      await Future.delayed(Duration(milliseconds: 300));

      // Verify no duplicate processing occurred
      final eventsByNodeA =
          receivedEvents.where((e) => e.nodeId == 'nodeA').toList();
      final uniqueEventIds = eventsByNodeA.map((e) => e.id).toSet();

      expect(
          eventsByNodeA.length, equals(uniqueEventIds.length)); // No duplicates
    });

    test('handles cascading vector clock resets', () async {
      // Create initial state with all nodes having events
      await nodeA.createEvent({'wave': 1, 'from': 'A'});
      await nodeB.createEvent({'wave': 1, 'from': 'B'});
      await nodeC.createEvent({'wave': 1, 'from': 'C'});

      await Future.delayed(Duration(milliseconds: 300));

      // Reset multiple nodes in sequence
      await nodeA.stop();
      await nodeB.stop();

      // Create new stores instead of clearing
      storeA = MemoryEventStore();
      storeB = MemoryEventStore();

      // Restart with fresh state
      nodeA = GossipNode(
        config: GossipConfig(
            nodeId: 'nodeA',
            gossipInterval: Duration(milliseconds: 100),
            fanout: 2),
        eventStore: storeA,
        transport: transportA,
      );

      nodeB = GossipNode(
        config: GossipConfig(
            nodeId: 'nodeB',
            gossipInterval: Duration(milliseconds: 100),
            fanout: 2),
        eventStore: storeB,
        transport: transportB,
      );

      await nodeA.start();
      await nodeB.start();

      nodeA.addPeer(GossipPeer(id: 'nodeB', address: 'nodeB'));
      nodeA.addPeer(GossipPeer(id: 'nodeC', address: 'nodeC'));
      nodeB.addPeer(GossipPeer(id: 'nodeA', address: 'nodeA'));
      nodeB.addPeer(GossipPeer(id: 'nodeC', address: 'nodeC'));

      // Create new events after both nodes reset
      await nodeA.createEvent({'wave': 2, 'from': 'A'});
      await nodeB.createEvent({'wave': 2, 'from': 'B'});

      // Allow extensive synchronization time
      await Future.delayed(Duration(milliseconds: 800));

      // Verify that nodeC (the non-reset node) receives all new events
      final finalEventsC = await storeC.getAllEvents();
      final wave2Events =
          finalEventsC.where((e) => e.payload['wave'] == 2).toList();

      expect(wave2Events.length, equals(2));

      final fromA = wave2Events.where((e) => e.payload['from'] == 'A').toList();
      final fromB = wave2Events.where((e) => e.payload['from'] == 'B').toList();

      expect(fromA.length, equals(1));
      expect(fromB.length, equals(1));
    });

    test('vector clock reset detection with timestamp rollback', () async {
      // Create events to establish high vector clock timestamps
      for (int i = 0; i < 5; i++) {
        await nodeA.createEvent({'sequence': i, 'type': 'setup'});
      }

      await Future.delayed(Duration(milliseconds: 200));

      // Verify nodeA has high timestamp
      expect(nodeA.vectorClock.getTimestampFor('nodeA'), equals(5));

      // Other nodes should also know about nodeA's high timestamp
      await Future.delayed(Duration(milliseconds: 200));
      final nodeATimestampInB = nodeB.vectorClock.getTimestampFor('nodeA');
      final nodeATimestampInC = nodeC.vectorClock.getTimestampFor('nodeA');

      expect(nodeATimestampInB, equals(5));
      expect(nodeATimestampInC, equals(5));

      // Reset nodeA
      await nodeA.stop();
      // Create new store instead of clearing
      storeA = MemoryEventStore();

      nodeA = GossipNode(
        config: GossipConfig(
          nodeId: 'nodeA',
          gossipInterval: Duration(milliseconds: 100),
          fanout: 2,
        ),
        eventStore: storeA,
        transport: transportA,
      );

      await nodeA.start();
      nodeA.addPeer(GossipPeer(id: 'nodeB', address: 'nodeB'));
      nodeA.addPeer(GossipPeer(id: 'nodeC', address: 'nodeC'));

      // Create new event with low timestamp (1) despite others expecting higher
      await nodeA.createEvent({'type': 'after_reset', 'message': 'new_start'});

      // Force gossip exchanges
      await Future.delayed(Duration(milliseconds: 100));
      await nodeA.gossip();
      await nodeB.gossip();
      await nodeC.gossip();
      await Future.delayed(Duration(milliseconds: 200));

      // Verify the reset event reached other nodes
      final eventsInB = await storeB.getAllEvents();
      final eventsInC = await storeC.getAllEvents();

      final resetEventInB =
          eventsInB.where((e) => e.payload['type'] == 'after_reset').toList();
      final resetEventInC =
          eventsInC.where((e) => e.payload['type'] == 'after_reset').toList();

      expect(resetEventInB.length, equals(1));
      expect(resetEventInC.length, equals(1));
      expect(resetEventInB.first.timestamp, equals(1));
      expect(resetEventInC.first.timestamp, equals(1));
    });
  });
}
