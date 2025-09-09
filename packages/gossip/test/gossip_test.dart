import 'dart:async';

import 'package:gossip/gossip.dart';
import 'package:test/test.dart';

/// Mock transport for testing that simulates network communication
class MockTransport implements GossipTransport {
  final String nodeId;
  final Map<String, MockTransport> _network;

  final StreamController<IncomingDigest> _digestController =
      StreamController<IncomingDigest>.broadcast();
  final StreamController<IncomingEvents> _eventsController =
      StreamController<IncomingEvents>.broadcast();

  MockTransport(this.nodeId, this._network);

  @override
  Future<void> initialize() async {
    _network[nodeId] = this;
  }

  @override
  Future<void> shutdown() async {
    _network.remove(nodeId);
    await _digestController.close();
    await _eventsController.close();
  }

  @override
  Stream<IncomingDigest> get incomingDigests => _digestController.stream;

  @override
  Stream<IncomingEvents> get incomingEvents => _eventsController.stream;

  @override
  Future<GossipDigestResponse> sendDigest(
    TransportPeer transportPeer,
    GossipDigest digest, {
    Duration? timeout,
  }) async {
    final targetTransport = _network[transportPeer.address.value];
    if (targetTransport == null) {
      throw TransportException(
        'Transport peer ${transportPeer.address.value} not found',
      );
    }

    final completer = Completer<GossipDigestResponse>();

    final incomingDigest = IncomingDigest(
      fromTransportPeer: TransportPeer(
        address: TransportPeerAddress(nodeId),
        displayName: 'Node $nodeId',
        connectedAt: DateTime.now(),
      ),
      digest: digest,
      respond: (response) async {
        completer.complete(response);
      },
    );

    targetTransport._digestController.add(incomingDigest);

    return completer.future.timeout(timeout ?? const Duration(seconds: 5));
  }

  @override
  Future<void> sendEvents(
    TransportPeer transportPeer,
    GossipEventMessage message, {
    Duration? timeout,
  }) async {
    final targetTransport = _network[transportPeer.address.value];
    if (targetTransport == null) {
      throw TransportException(
        'Transport peer ${transportPeer.address.value} not found',
      );
    }

    final incomingEvents = IncomingEvents(
      fromTransportPeer: TransportPeer(
        address: TransportPeerAddress(nodeId),
        displayName: 'Node $nodeId',
        connectedAt: DateTime.now(),
      ),
      message: message,
    );

    targetTransport._eventsController.add(incomingEvents);
  }

  @override
  Future<List<TransportPeer>> discoverPeers() async {
    return _network.keys
        .where((id) => id != nodeId)
        .map(
          (id) => TransportPeer(
            address: TransportPeerAddress(id),
            displayName: 'Node $id',
            connectedAt: DateTime.now(),
          ),
        )
        .toList();
  }

  @override
  Future<bool> isPeerReachable(TransportPeer transportPeer) async {
    return _network.containsKey(transportPeer.address.value);
  }
}

void main() {
  group('Event', () {
    test('should create event with required fields', () {
      final event = Event(
        id: 'test-1',
        nodeId: GossipPeerID('node-1'),
        timestamp: 1,
        creationTimestamp: 1000,
        payload: {'data': 'test'},
      );

      expect(event.id, equals('test-1'));
      expect(event.nodeId, equals(GossipPeerID('node-1')));
      expect(event.timestamp, equals(1));
      expect(event.creationTimestamp, equals(1000));
      expect(event.payload, equals({'data': 'test'}));
    });

    test('should serialize to and from JSON', () {
      final originalEvent = Event(
        id: 'test-1',
        nodeId: GossipPeerID('node-1'),
        timestamp: 1,
        creationTimestamp: 1000,
        payload: {'data': 'test', 'number': 42},
      );

      final json = originalEvent.toJson();
      final deserializedEvent = Event.fromJson(json);

      expect(deserializedEvent.id, equals(originalEvent.id));
      expect(deserializedEvent.nodeId, equals(originalEvent.nodeId));
      expect(deserializedEvent.timestamp, equals(originalEvent.timestamp));
      expect(
        deserializedEvent.creationTimestamp,
        equals(originalEvent.creationTimestamp),
      );
      expect(deserializedEvent.payload, equals(originalEvent.payload));
    });

    test('should support equality comparison', () {
      final event1 = Event(
        id: 'test-1',
        nodeId: GossipPeerID('node-1'),
        timestamp: 1,
        creationTimestamp: 1000,
        payload: {'data': 'test'},
      );

      final event2 = Event(
        id: 'test-1',
        nodeId: GossipPeerID('node-1'),
        timestamp: 1,
        creationTimestamp: 1000,
        payload: {'data': 'test'},
      );

      final event3 = Event(
        id: 'test-2',
        nodeId: GossipPeerID('node-1'),
        timestamp: 1,
        creationTimestamp: 1000,
        payload: {'data': 'test'},
      );

      expect(event1, equals(event2));
      expect(event1, isNot(equals(event3)));
    });
  });

  group('VectorClock', () {
    test('should initialize empty', () {
      final clock = VectorClock();
      expect(clock.isEmpty, isTrue);
      expect(clock.nodeCount, equals(0));
    });

    test('should increment timestamps', () {
      final clock = VectorClock();

      expect(clock.getTimestampFor('node1'), equals(0));
      clock.increment('node1');
      expect(clock.getTimestampFor('node1'), equals(1));
      clock.increment('node1');
      expect(clock.getTimestampFor('node1'), equals(2));
    });

    test('should merge vector clocks correctly', () {
      final clock1 = VectorClock();
      clock1.increment('node1');
      clock1.increment('node2');

      final clock2 = VectorClock();
      clock2.increment('node2');
      clock2.increment('node3');

      clock1.merge(clock2);

      expect(clock1.getTimestampFor('node1'), equals(1));
      expect(clock1.getTimestampFor('node2'), equals(1));
      expect(clock1.getTimestampFor('node3'), equals(1));
    });

    test('should compare vector clocks', () {
      final clock1 = VectorClock();
      clock1.setTimestampFor('node1', 1);
      clock1.setTimestampFor('node2', 2);

      final clock2 = VectorClock();
      clock2.setTimestampFor('node1', 1);
      clock2.setTimestampFor('node2', 3);

      expect(clock1.compareTo(clock2), equals(ClockComparison.before));
      expect(clock2.compareTo(clock1), equals(ClockComparison.after));
      expect(clock1.compareTo(clock1.copy()), equals(ClockComparison.equal));
    });

    test('should detect concurrent clocks', () {
      final clock1 = VectorClock();
      clock1.setTimestampFor('node1', 2);
      clock1.setTimestampFor('node2', 1);

      final clock2 = VectorClock();
      clock2.setTimestampFor('node1', 1);
      clock2.setTimestampFor('node2', 2);

      expect(clock1.compareTo(clock2), equals(ClockComparison.concurrent));
      expect(clock2.compareTo(clock1), equals(ClockComparison.concurrent));
    });
  });

  group('MemoryEventStore', () {
    late MemoryEventStore store;

    setUp(() {
      store = MemoryEventStore();
    });

    tearDown(() async {
      await store.close();
    });

    test('should save and retrieve events', () async {
      final event = Event(
        id: 'test-1',
        nodeId: GossipPeerID('node-1'),
        timestamp: 1,
        creationTimestamp: 1000,
        payload: {'data': 'test'},
      );

      await store.saveEvent(event);

      final retrieved = await store.getEvent('test-1');
      expect(retrieved, equals(event));

      final hasEvent = await store.hasEvent('test-1');
      expect(hasEvent, isTrue);
    });

    test('should handle duplicate events gracefully', () async {
      final event = Event(
        id: 'test-1',
        nodeId: GossipPeerID('node-1'),
        timestamp: 1,
        creationTimestamp: 1000,
        payload: {'data': 'test'},
      );

      await store.saveEvent(event);
      await store.saveEvent(event); // Save duplicate

      final count = await store.getEventCount();
      expect(count, equals(1)); // Should still be 1
    });

    test('should retrieve events since timestamp', () async {
      final events = [
        Event(
          id: 'test-1',
          nodeId: GossipPeerID('node-1'),
          timestamp: 1,
          creationTimestamp: 1000,
          payload: {'data': 'test1'},
        ),
        Event(
          id: 'test-2',
          nodeId: GossipPeerID('node-1'),
          timestamp: 2,
          creationTimestamp: 2000,
          payload: {'data': 'test2'},
        ),
        Event(
          id: 'test-3',
          nodeId: GossipPeerID('node-1'),
          timestamp: 3,
          creationTimestamp: 3000,
          payload: {'data': 'test3'},
        ),
      ];

      for (final event in events) {
        await store.saveEvent(event);
      }

      final eventsSince1 = await store.getEventsSince('node-1', 1);
      expect(eventsSince1.length, equals(2));
      expect(eventsSince1.map((e) => e.id), containsAll(['test-2', 'test-3']));
    });

    test('should get latest timestamp for node', () async {
      final events = [
        Event(
          id: 'test-1',
          nodeId: GossipPeerID('node-1'),
          timestamp: 5,
          creationTimestamp: 1000,
          payload: {'data': 'test1'},
        ),
        Event(
          id: 'test-2',
          nodeId: GossipPeerID('node-1'),
          timestamp: 3,
          creationTimestamp: 2000,
          payload: {'data': 'test2'},
        ),
      ];

      for (final event in events) {
        await store.saveEvent(event);
      }

      final latestTimestamp = await store.getLatestTimestampForNode('node-1');
      expect(latestTimestamp, equals(5));
    });

    test('should provide statistics', () async {
      final events = [
        Event(
          id: 'test-1',
          nodeId: GossipPeerID('node-1'),
          timestamp: 1,
          creationTimestamp: 1000,
          payload: {'data': 'test1'},
        ),
        Event(
          id: 'test-2',
          nodeId: GossipPeerID('node-2'),
          timestamp: 1,
          creationTimestamp: 2000,
          payload: {'data': 'test2'},
        ),
      ];

      for (final event in events) {
        await store.saveEvent(event);
      }

      final stats = await store.getStats();
      expect(stats.totalEvents, equals(2));
      expect(stats.uniqueNodes, equals(2));
    });
  });

  group('GossipConfig', () {
    test('should create valid configuration', () {
      final config = GossipConfig(nodeId: 'test-node');

      expect(config.nodeId, equals('test-node'));
      expect(config.gossipInterval, equals(Duration(seconds: 1)));
      expect(config.fanout, equals(3));
    });

    test('should validate configuration parameters', () {
      expect(
        () => GossipConfig(nodeId: ''),
        throwsA(isA<InvalidConfigurationException>()),
      );

      expect(
        () => GossipConfig(nodeId: 'test', fanout: -1),
        throwsA(isA<InvalidConfigurationException>()),
      );
    });

    test('should create preset configurations', () {
      final highThroughput = GossipConfig.highThroughput(nodeId: 'test');
      expect(
        highThroughput.gossipInterval,
        equals(Duration(milliseconds: 500)),
      );
      expect(highThroughput.fanout, equals(5));

      final lowResource = GossipConfig.lowResource(nodeId: 'test');
      expect(lowResource.gossipInterval, equals(Duration(seconds: 5)));
      expect(lowResource.fanout, equals(2));
    });
  });

  group('GossipNode Integration', () {
    late Map<String, MockTransport> network;

    setUp(() {
      network = <String, MockTransport>{};
    });

    tearDown(() async {
      // Clean up any remaining transports
      // Create a copy to avoid concurrent modification
      final transports = List<MockTransport>.from(network.values);
      for (final transport in transports) {
        await transport.shutdown();
      }
    });

    test('should start and stop successfully', () async {
      final config = GossipConfig(nodeId: 'test-node');
      final store = MemoryEventStore();
      final transport = MockTransport('test-node', network);
      final node = GossipNode(
        config: config,
        eventStore: store,
        transport: transport,
      );

      await node.start();
      expect(() => node.start(), returnsNormally); // Should be idempotent

      await node.stop();
    });

    test('should create events with incrementing timestamps', () async {
      final config = GossipConfig(nodeId: 'test-node');
      final store = MemoryEventStore();
      final transport = MockTransport('test-node', network);
      final node = GossipNode(
        config: config,
        eventStore: store,
        transport: transport,
      );

      await node.start();

      final event1 = await node.createEvent({'data': 'first'});
      final event2 = await node.createEvent({'data': 'second'});

      expect(event1.timestamp, equals(1));
      expect(event2.timestamp, equals(2));
      expect(event1.nodeId, equals(GossipPeerID('test-node')));
      expect(event2.nodeId, equals(GossipPeerID('test-node')));

      await node.stop();
    });

    test('should add and remove peers', () async {
      final config = GossipConfig(nodeId: 'test-node');
      final store = MemoryEventStore();
      final transport = MockTransport('test-node', network);
      final node = GossipNode(
        config: config,
        eventStore: store,
        transport: transport,
      );

      await node.start();

      final peer = GossipPeer(
        id: GossipPeerID('peer-1'),
        address: TransportPeerAddress('mock://peer-1'),
      );
      node.addPeer(peer);

      expect(node.peers, hasLength(1));
      expect(node.peers.first.id, equals(GossipPeerID('peer-1')));

      final removed = node.removePeer(GossipPeerID('peer-1'));
      expect(removed, isTrue);
      expect(node.peers, isEmpty);

      final removedAgain = node.removePeer(GossipPeerID('peer-1'));
      expect(removedAgain, isFalse);

      await node.stop();
    });

    test('should perform gossip exchange between two nodes', () async {
      // Create two nodes
      final nodeA = GossipNode(
        config: GossipConfig(nodeId: 'nodeA'),
        eventStore: MemoryEventStore(),
        transport: MockTransport('nodeA', network),
      );

      final nodeB = GossipNode(
        config: GossipConfig(nodeId: 'nodeB'),
        eventStore: MemoryEventStore(),
        transport: MockTransport('nodeB', network),
      );

      await nodeA.start();
      await nodeB.start();

      // Create events on each node first
      await nodeA.createEvent({'from': 'A', 'message': 'Hello from A'});
      await nodeB.createEvent({'from': 'B', 'message': 'Hello from B'});

      // Add peers manually since we need to establish relationships
      // In the new architecture, peers are discovered via transport but relationships
      // are established through gossip digest exchange
      nodeA.addPeer(
        GossipPeer(
          id: GossipPeerID('nodeB'),
          address: TransportPeerAddress('nodeB'),
        ),
      );
      nodeB.addPeer(
        GossipPeer(
          id: GossipPeerID('nodeA'),
          address: TransportPeerAddress('nodeA'),
        ),
      );

      // Wait a bit for any immediate processing
      await Future.delayed(Duration(milliseconds: 10));

      // Manually trigger gossip to establish peer relationships and sync events
      await nodeA.gossip();
      await nodeB.gossip();

      // Wait for gossip to complete
      await Future.delayed(Duration(milliseconds: 100));

      // Check that events were synchronized
      final nodeAEvents = await nodeA.eventStore.getAllEvents();
      final nodeBEvents = await nodeB.eventStore.getAllEvents();

      expect(nodeAEvents.length, equals(2));
      expect(nodeBEvents.length, equals(2));

      await nodeA.stop();
      await nodeB.stop();
    });

    test('should emit event streams', () async {
      final config = GossipConfig(nodeId: 'test-node');
      final store = MemoryEventStore();
      final transport = MockTransport('test-node', network);
      final node = GossipNode(
        config: config,
        eventStore: store,
        transport: transport,
      );

      await node.start();

      final createdEvents = <Event>[];
      final subscription = node.onEventCreated.listen(createdEvents.add);

      await node.createEvent({'test': 'data'});
      await Future.delayed(Duration(milliseconds: 10));

      expect(createdEvents, hasLength(1));
      expect(createdEvents.first.payload['test'], equals('data'));

      await subscription.cancel();
      await node.stop();
    });
  });
}
