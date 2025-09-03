/// Comprehensive test suite for vector clock reset detection in the gossip protocol.
///
/// ## Problem Statement
///
/// In distributed gossip protocols, vector clocks track the logical time of events
/// across nodes. However, when a node goes offline and loses its vector clock state
/// (due to storage loss, restart, etc.), it creates a synchronization problem:
///
/// 1. **Before Reset**: Node A has created events with timestamps 1, 2, 3, ..., 100
/// 2. **Node Goes Offline**: Node A loses its vector clock state
/// 3. **Vector Clock Reset**: Node A restarts with a fresh vector clock (timestamp 0)
/// 4. **New Events**: Node A creates new events with timestamps 1, 2, 3
/// 5. **Sync Problem**: Other nodes think Node A is at timestamp 100, so they won't
///    request the new events with lower timestamps 1, 2, 3
///
/// ## Solution
///
/// This implementation detects vector clock resets by:
/// - **Timestamp Regression Detection**: If a peer reports a timestamp lower than
///   what we think they should have, assume they've reset
/// - **Full Synchronization**: Request ALL events from timestamp 0 when reset detected
/// - **Selective Vector Clock Merge**: Don't downgrade our vector clock on resets
/// - **Bidirectional Protection**: Send recent events if we might have reset
///
/// ## Test Coverage
///
/// This test suite validates:
/// - Basic reset detection when peer timestamp goes backward
/// - Normal advancement scenarios (no false positives)
/// - Multiple peer scenarios with mixed reset states
/// - Edge cases (zero timestamps, equal timestamps, unknown peers)
/// - Vector clock merge behavior during resets
/// - Event store integration for latest event retrieval
///
/// These tests use a simplified mock transport to focus on the core logic
/// without complex networking or timing dependencies.
library;

import 'dart:async';

import 'package:test/test.dart';

import '../../lib/gossip.dart';

/// Simple mock transport for controlled testing
class TestTransport implements GossipTransport {
  final String nodeId;
  final StreamController<IncomingDigest> _digestController =
      StreamController.broadcast();
  final StreamController<IncomingEvents> _eventsController =
      StreamController.broadcast();

  TestTransport(this.nodeId);

  @override
  Future<void> initialize() async {}

  @override
  Future<GossipDigestResponse> sendDigest(
    GossipPeer peer,
    GossipDigest digest, {
    Duration? timeout,
  }) async {
    // Return empty response for simplicity
    return GossipDigestResponse(
      senderId: nodeId,
      events: [],
      eventRequests: {},
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> sendEvents(
    GossipPeer peer,
    GossipEventMessage eventMessage, {
    Duration? timeout,
  }) async {
    // No-op for this test
  }

  @override
  Stream<IncomingDigest> get incomingDigests => _digestController.stream;

  @override
  Stream<IncomingEvents> get incomingEvents => _eventsController.stream;

  @override
  Future<List<GossipPeer>> discoverPeers() async => [];

  @override
  Future<bool> isPeerReachable(GossipPeer peer) async => true;

  @override
  Future<void> shutdown() async {
    await _digestController.close();
    await _eventsController.close();
  }

  // Test helper to simulate incoming digest
  Future<GossipDigestResponse> simulateIncomingDigest(
      GossipDigest digest) async {
    final completer = Completer<GossipDigestResponse>();

    final incoming = IncomingDigest(
      fromPeer: GossipPeer(id: 'test-peer', address: 'test'),
      digest: digest,
      respond: (response) async {
        completer.complete(response);
      },
    );

    _digestController.add(incoming);
    return completer.future;
  }
}

void main() {
  group('Vector Clock Reset Detection Logic', () {
    late GossipNode node;
    late MemoryEventStore eventStore;
    late TestTransport transport;

    setUp(() async {
      eventStore = MemoryEventStore();
      transport = TestTransport('test-node');

      node = GossipNode(
        config: GossipConfig(
          nodeId: 'test-node',
          gossipInterval:
              Duration(seconds: 10), // Long interval to prevent auto-gossip
          gossipTimeout:
              Duration(seconds: 30), // Must be greater than gossip interval
        ),
        eventStore: eventStore,
        transport: transport,
      );

      await node.start();
    });

    tearDown(() async {
      await node.stop();
      await transport.shutdown();
      await eventStore.close();
    });

    test('detects vector clock reset when peer timestamp goes backward',
        () async {
      // Set up scenario: we think peer-A is at timestamp 10
      node.setVectorClockTimestamp('peer-A', 10);

      // Verify our setup
      expect(node.vectorClock.getTimestampFor('peer-A'), equals(10));

      // Simulate receiving a digest where peer-A claims to be at timestamp 3
      final digest = GossipDigest(
        senderId: 'peer-A',
        vectorClock: {'peer-A': 3}, // Lower than what we think (10)
        createdAt: DateTime.now(),
      );

      final response = await transport.simulateIncomingDigest(digest);

      // Verify reset was detected

      // The response should request all events from timestamp 0 (reset detected)
      expect(response.eventRequests.containsKey('peer-A'), isTrue);
      expect(response.eventRequests['peer-A'], equals(0));
    });

    test('normal case when peer timestamp advances', () async {
      // We think peer-B is at timestamp 5
      node.setVectorClockTimestamp('peer-B', 5);

      // Peer reports being at timestamp 8 (normal advancement)
      final digest = GossipDigest(
        senderId: 'peer-B',
        vectorClock: {'peer-B': 8},
        createdAt: DateTime.now(),
      );

      final response = await transport.simulateIncomingDigest(digest);

      // Verify normal advancement was handled correctly

      // Should request events after our last known timestamp
      expect(response.eventRequests.containsKey('peer-B'), isTrue);
      expect(response.eventRequests['peer-B'], equals(5));
    });

    test('handles unknown peer normally', () async {
      // Peer-C is unknown to us
      final digest = GossipDigest(
        senderId: 'peer-C',
        vectorClock: {'peer-C': 5},
        createdAt: DateTime.now(),
      );

      final response = await transport.simulateIncomingDigest(digest);

      // Should request events after 0 (we know nothing about this peer)
      expect(response.eventRequests.containsKey('peer-C'), isTrue);
      expect(response.eventRequests['peer-C'], equals(0));
    });

    test('sends recent events when we might have reset', () async {
      // Create some events on our node
      await node.createEvent({'type': 'test', 'data': 'event1'});
      await node.createEvent({'type': 'test', 'data': 'event2'});

      // Simulate a peer that thinks we're at a higher timestamp
      final digest = GossipDigest(
        senderId: 'peer-D',
        vectorClock: {
          'test-node': 10
        }, // They think we're at 10, but we're only at 2
        createdAt: DateTime.now(),
      );

      final response = await transport.simulateIncomingDigest(digest);

      // We should send them our recent events
      expect(response.events.length, greaterThan(0));

      // Events should include our recent creations
      final eventTypes = response.events.map((e) => e.payload['type']).toSet();
      expect(eventTypes.contains('test'), isTrue);
    });

    test('vector clock merge updates correctly after reset detection',
        () async {
      // Initial state: we think peer-E is at 15
      node.setVectorClockTimestamp('peer-E', 15);

      // Verify initial state
      expect(node.vectorClock.getTimestampFor('peer-E'), equals(15));

      // Peer reports being at 3 (reset detected)
      final digest = GossipDigest(
        senderId: 'peer-E',
        vectorClock: {'peer-E': 3},
        createdAt: DateTime.now(),
      );

      await transport.simulateIncomingDigest(digest);

      // Verify vector clock wasn't downgraded

      // Our vector clock should NOT be updated to the lower value
      // It should remain at the higher value until we get confirmation
      // that the peer actually has events at the higher timestamps
      expect(node.vectorClock.getTimestampFor('peer-E'), equals(15));
    });

    test('handles multiple peers with mixed reset scenarios', () async {
      // Set up complex scenario
      node.setVectorClockTimestamp('peer-F', 20); // Normal peer
      node.setVectorClockTimestamp('peer-G', 8); // Reset peer

      final digest = GossipDigest(
        senderId: 'multi-peer',
        vectorClock: {
          'peer-F': 25, // Advanced normally
          'peer-G': 2, // Reset detected
          'peer-H': 5, // New peer
        },
        createdAt: DateTime.now(),
      );

      final response = await transport.simulateIncomingDigest(digest);

      // Verify each peer was handled appropriately

      // Should handle each peer appropriately
      expect(response.eventRequests['peer-F'], equals(20)); // Normal request
      expect(response.eventRequests['peer-G'], equals(0)); // Reset detected
      expect(response.eventRequests['peer-H'], equals(0)); // New peer
    });

    test('does not falsely detect reset for equal timestamps', () async {
      // We think peer-I is at timestamp 7
      node.setVectorClockTimestamp('peer-I', 7);

      // Peer also reports being at timestamp 7 (no change)
      final digest = GossipDigest(
        senderId: 'peer-I',
        vectorClock: {'peer-I': 7},
        createdAt: DateTime.now(),
      );

      final response = await transport.simulateIncomingDigest(digest);

      // Verify no false positive reset detection

      // Should not request any events (no change)
      expect(response.eventRequests.containsKey('peer-I'), isFalse);
    });

    test('reset detection works with zero timestamps', () async {
      // We think peer-J is at timestamp 5
      node.setVectorClockTimestamp('peer-J', 5);

      // Peer reports being at timestamp 0 (complete reset)
      final digest = GossipDigest(
        senderId: 'peer-J',
        vectorClock: {'peer-J': 0},
        createdAt: DateTime.now(),
      );

      final response = await transport.simulateIncomingDigest(digest);

      // Verify zero timestamp reset detection

      // Should detect reset and request from 0
      expect(response.eventRequests.containsKey('peer-J'), isTrue);
      expect(response.eventRequests['peer-J'], equals(0));
    });
  });

  group('Vector Clock Reset Edge Cases', () {
    test('vector clock comparison edge cases', () {
      final clock1 = VectorClock();
      final clock2 = VectorClock();

      // Test empty clocks
      expect(clock1.compareTo(clock2), equals(ClockComparison.equal));

      // Test one empty, one with data
      clock1.setTimestampFor('node-A', 5);
      expect(clock1.compareTo(clock2), equals(ClockComparison.after));
      expect(clock2.compareTo(clock1), equals(ClockComparison.before));

      // Test reset scenario comparison
      clock2.setTimestampFor('node-A', 2); // Lower timestamp
      expect(clock1.compareTo(clock2), equals(ClockComparison.after));
      expect(clock2.compareTo(clock1), equals(ClockComparison.before));

      // Test concurrent scenario
      clock1.setTimestampFor('node-B', 3);
      clock2.setTimestampFor('node-C', 4);
      expect(clock1.compareTo(clock2), equals(ClockComparison.concurrent));
    });

    test('event store latest event retrieval', () async {
      final store = MemoryEventStore();

      // Test with no events
      final noEvent = await store.getLatestEvent('non-existent');
      expect(noEvent, isNull);

      // Add some events
      final event1 = Event(
        id: 'e1',
        nodeId: 'node-X',
        timestamp: 1,
        creationTimestamp: DateTime.now().millisecondsSinceEpoch,
        payload: {'data': 'first'},
      );

      final event2 = Event(
        id: 'e2',
        nodeId: 'node-X',
        timestamp: 2,
        creationTimestamp: DateTime.now().millisecondsSinceEpoch + 1,
        payload: {'data': 'second'},
      );

      await store.saveEvent(event1);
      await store.saveEvent(event2);

      // Should get the latest event
      final latestEvent = await store.getLatestEvent('node-X');
      expect(latestEvent, isNotNull);
      expect(latestEvent!.timestamp, equals(2));
      expect(latestEvent.payload['data'], equals('second'));

      await store.close();
    });
  });
}
