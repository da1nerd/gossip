import 'dart:async';
import 'package:test/test.dart';
import 'package:gossip/gossip.dart';

/// Mock transport for testing that tracks sent events
class MockTransport implements SimpleGossipTransport {
  final String nodeId;
  final StreamController<Event> _incomingController =
      StreamController.broadcast();
  final List<String> _connectedPeers = [];
  final List<Event> _sentEvents = [];
  final Map<String, List<Event>> _sentEventsByPeer = {};
  bool _initialized = false;

  MockTransport(this.nodeId);

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<void> broadcastEvent(Event event) async {
    if (!_initialized) throw StateError('Not initialized');
    _sentEvents.add(event);
    // Simulate broadcasting to all connected peers
    for (final peerId in _connectedPeers) {
      _sentEventsByPeer.putIfAbsent(peerId, () => []).add(event);
    }
  }

  @override
  Future<void> sendEventToPeer(String peerId, Event event) async {
    if (!_initialized) throw StateError('Not initialized');
    if (!_connectedPeers.contains(peerId)) {
      throw ArgumentError('Peer $peerId not connected');
    }
    _sentEventsByPeer.putIfAbsent(peerId, () => []).add(event);
  }

  @override
  Stream<Event> get incomingEvents => _incomingController.stream;

  @override
  List<String> get connectedPeerIds => List.from(_connectedPeers);

  @override
  Future<void> dispose() async {
    _initialized = false;
    await _incomingController.close();
    _connectedPeers.clear();
    _sentEvents.clear();
    _sentEventsByPeer.clear();
  }

  // Test utilities
  void connectPeer(String peerId) {
    if (!_connectedPeers.contains(peerId)) {
      _connectedPeers.add(peerId);
    }
  }

  void disconnectPeer(String peerId) {
    _connectedPeers.remove(peerId);
  }

  void receiveEvent(Event event) {
    _incomingController.add(event);
  }

  List<Event> getSentEventsToPeer(String peerId) {
    return List.from(_sentEventsByPeer[peerId] ?? []);
  }

  List<Event> get allSentEvents => List.from(_sentEvents);

  void clearSentEvents() {
    _sentEvents.clear();
    _sentEventsByPeer.clear();
  }
}

void main() {
  group('SimpleGossipNode Historical Sync', () {
    late MockTransport transport;
    late MemoryEventStore eventStore;
    late SimpleGossipNode node;

    setUp(() async {
      transport = MockTransport('test-node');
      eventStore = MemoryEventStore();
      node = SimpleGossipNode(
        nodeId: 'test-node',
        transport: transport,
        eventStore: eventStore,
      );
      await node.start();
    });

    tearDown(() async {
      await node.dispose();
    });

    test('should sync historical events when new peer connects', () async {
      // Create some historical events
      await node.createEvent({'type': 'message', 'content': 'Hello 1'});
      await node.createEvent({'type': 'message', 'content': 'Hello 2'});
      await node.createEvent({'type': 'message', 'content': 'Hello 3'});

      // Clear any sent events from creation
      transport.clearSentEvents();

      // Simulate a new peer connecting
      transport.connectPeer('peer-1');

      // Wait for the peer monitoring timer to tick and sync to complete
      await Future.delayed(const Duration(milliseconds: 1100));

      // Verify historical events were sent to the new peer
      final sentEvents = transport.getSentEventsToPeer('peer-1');
      expect(sentEvents.length, equals(3));

      // Verify events are in chronological order
      expect(sentEvents[0].payload['content'], equals('Hello 1'));
      expect(sentEvents[1].payload['content'], equals('Hello 2'));
      expect(sentEvents[2].payload['content'], equals('Hello 3'));

      // Verify creation timestamps are in order
      for (int i = 1; i < sentEvents.length; i++) {
        expect(
          sentEvents[i].creationTimestamp,
          greaterThanOrEqualTo(sentEvents[i - 1].creationTimestamp),
        );
      }
    });

    test('should not sync to disconnected peers', () async {
      // Create some historical events
      await node.createEvent({'type': 'message', 'content': 'Hello 1'});

      // Connect and then disconnect a peer
      transport.connectPeer('peer-1');
      transport.disconnectPeer('peer-1');
      transport.clearSentEvents();

      // Try to manually sync - should fail
      expect(
        () => node.syncHistoricalEventsToPeer('peer-1'),
        throwsArgumentError,
      );

      // Verify no events were sent
      final sentEvents = transport.getSentEventsToPeer('peer-1');
      expect(sentEvents.length, equals(0));
    });

    test('should sync to all connected peers when requested', () async {
      // Create some historical events
      await node.createEvent({'type': 'message', 'content': 'Hello 1'});
      await node.createEvent({'type': 'message', 'content': 'Hello 2'});

      // Connect multiple peers
      transport.connectPeer('peer-1');
      transport.connectPeer('peer-2');
      transport.clearSentEvents();

      // Manually sync to all peers
      await node.syncHistoricalEventsToAllPeers();

      // Verify both peers received all events
      final sentToPeer1 = transport.getSentEventsToPeer('peer-1');
      final sentToPeer2 = transport.getSentEventsToPeer('peer-2');

      expect(sentToPeer1.length, equals(2));
      expect(sentToPeer2.length, equals(2));

      expect(sentToPeer1[0].payload['content'], equals('Hello 1'));
      expect(sentToPeer1[1].payload['content'], equals('Hello 2'));
      expect(sentToPeer2[0].payload['content'], equals('Hello 1'));
      expect(sentToPeer2[1].payload['content'], equals('Hello 2'));
    });

    test('should handle empty event store gracefully', () async {
      // Clear event store
      await eventStore.clear();

      // Connect a new peer
      transport.connectPeer('peer-1');
      transport.clearSentEvents();

      // Wait for potential sync
      await Future.delayed(const Duration(milliseconds: 1100));

      // Verify no events were sent (since there are none)
      final sentEvents = transport.getSentEventsToPeer('peer-1');
      expect(sentEvents.length, equals(0));
    });

    test('should handle sync failure gracefully', () async {
      // Create historical events
      await node.createEvent({'type': 'message', 'content': 'Hello 1'});

      // Connect a peer
      transport.connectPeer('peer-1');
      transport.clearSentEvents();

      // Disconnect peer to simulate failure
      transport.disconnectPeer('peer-1');

      // Try to sync - should not throw but should handle gracefully
      // The internal _syncHistoricalEventsToPeer should handle the error
      expect(
        () => node.syncHistoricalEventsToPeer('peer-1'),
        throwsArgumentError,
      );
    });

    test('should maintain event ordering across multiple syncs', () async {
      // Create events with delays to ensure different timestamps
      await node
          .createEvent({'type': 'message', 'content': 'First', 'timestamp': 1});
      await Future.delayed(const Duration(milliseconds: 10));
      await node.createEvent(
          {'type': 'message', 'content': 'Second', 'timestamp': 2});
      await Future.delayed(const Duration(milliseconds: 10));
      await node
          .createEvent({'type': 'message', 'content': 'Third', 'timestamp': 3});

      // Connect first peer and let auto-sync happen
      transport.connectPeer('peer-1');
      await Future.delayed(const Duration(milliseconds: 1100));

      // Clear sent events and connect second peer
      transport.clearSentEvents();
      transport.connectPeer('peer-2');
      await Future.delayed(const Duration(milliseconds: 1100));

      // Both peers should receive events in the same order
      final sentToPeer1 = transport.getSentEventsToPeer('peer-1');
      final sentToPeer2 = transport.getSentEventsToPeer('peer-2');

      // peer-1 got events from auto-sync, peer-2 from second auto-sync
      expect(sentToPeer2.length, equals(3));
      expect(sentToPeer2[0].payload['content'], equals('First'));
      expect(sentToPeer2[1].payload['content'], equals('Second'));
      expect(sentToPeer2[2].payload['content'], equals('Third'));
    });

    test('should not fail when starting without peers', () async {
      // Create a new node without any connected peers
      final isolatedTransport = MockTransport('isolated-node');
      final isolatedEventStore = MemoryEventStore();
      final isolatedNode = SimpleGossipNode(
        nodeId: 'isolated-node',
        transport: isolatedTransport,
        eventStore: isolatedEventStore,
      );

      // Should start successfully
      await isolatedNode.start();

      // Should handle sync to all peers gracefully (no peers)
      await isolatedNode.syncHistoricalEventsToAllPeers();

      await isolatedNode.dispose();
    });

    test('should track peer changes correctly', () async {
      // Initially no peers
      expect(node.connectedPeers.length, equals(0));

      // Connect a peer
      transport.connectPeer('peer-1');
      await Future.delayed(const Duration(milliseconds: 1100));

      // Should detect the new peer
      expect(node.connectedPeers.length, equals(1));
      expect(node.connectedPeers, contains('peer-1'));

      // Connect another peer
      transport.connectPeer('peer-2');
      await Future.delayed(const Duration(milliseconds: 1100));

      expect(node.connectedPeers.length, equals(2));
      expect(node.connectedPeers, containsAll(['peer-1', 'peer-2']));

      // Disconnect first peer
      transport.disconnectPeer('peer-1');
      await Future.delayed(const Duration(milliseconds: 1100));

      expect(node.connectedPeers.length, equals(1));
      expect(node.connectedPeers, contains('peer-2'));
      expect(node.connectedPeers, isNot(contains('peer-1')));
    });
  });
}
