/// Simple example demonstrating the gossip protocol library.
///
/// This example shows how to create gossip nodes, configure them,
/// and simulate a basic gossip network with event synchronization.

import 'dart:async';
import 'dart:math';

import 'package:gossip/gossip.dart';

/// Simple in-memory transport for testing and examples.
///
/// This transport simulates network communication between nodes
/// running in the same process. In a real application, you would
/// implement a transport using HTTP, TCP, WebSocket, or other
/// network protocols.
class InMemoryTransport implements GossipTransport {
  final String nodeId;
  final Map<String, InMemoryTransport> _nodeRegistry;

  final StreamController<IncomingDigest> _digestController =
      StreamController<IncomingDigest>.broadcast();
  final StreamController<IncomingEvents> _eventsController =
      StreamController<IncomingEvents>.broadcast();
  final StreamController<GossipPeer> _peerDisconnectionsController =
      StreamController<GossipPeer>.broadcast();

  bool _isInitialized = false;

  InMemoryTransport(this.nodeId, this._nodeRegistry);

  @override
  Future<void> initialize() async {
    _nodeRegistry[nodeId] = this;
    _isInitialized = true;
  }

  @override
  Future<void> shutdown() async {
    _nodeRegistry.remove(nodeId);
    await _digestController.close();
    await _eventsController.close();
    await _peerDisconnectionsController.close();
    _isInitialized = false;
  }

  @override
  Future<GossipDigestResponse> sendDigest(
    GossipPeer peer,
    GossipDigest digest, {
    Duration? timeout,
  }) async {
    final targetTransport = _nodeRegistry[peer.id];
    if (targetTransport == null) {
      throw TransportException('Peer ${peer.id} not found');
    }

    final completer = Completer<GossipDigestResponse>();

    final incomingDigest = IncomingDigest(
      fromPeer: GossipPeer(id: nodeId, address: 'memory://$nodeId'),
      digest: digest,
      respond: (response) async {
        completer.complete(response);
      },
    );

    targetTransport._digestController.add(incomingDigest);

    return completer.future;
  }

  @override
  Future<void> sendEvents(
    GossipPeer peer,
    GossipEventMessage message, {
    Duration? timeout,
  }) async {
    final targetTransport = _nodeRegistry[peer.id];
    if (targetTransport == null) {
      throw TransportException('Peer ${peer.id} not found');
    }

    final incomingEvents = IncomingEvents(
      fromPeer: GossipPeer(id: nodeId, address: 'memory://$nodeId'),
      message: message,
    );

    targetTransport._eventsController.add(incomingEvents);
  }

  @override
  Stream<IncomingDigest> get incomingDigests => _digestController.stream;

  @override
  Stream<IncomingEvents> get incomingEvents => _eventsController.stream;

  @override
  Stream<GossipPeer> get peerDisconnections =>
      _peerDisconnectionsController.stream;

  @override
  Future<List<GossipPeer>> discoverPeers() async {
    return _nodeRegistry.keys
        .where((id) => id != nodeId)
        .map((id) => GossipPeer(id: id, address: 'memory://$id'))
        .toList();
  }

  @override
  Future<bool> isPeerReachable(GossipPeer peer) async {
    return _nodeRegistry.containsKey(peer.id);
  }
}

void main() async {
  print('🔄 Starting Gossip Protocol Example\n');

  // Shared transport registry for in-memory communication
  final transportRegistry = <String, InMemoryTransport>{};

  // Create configurations for three nodes
  final nodeAConfig = GossipConfig(
    nodeId: 'NodeA',
    gossipInterval: Duration(milliseconds: 500),
    fanout: 2,
  );

  final nodeBConfig = GossipConfig(
    nodeId: 'NodeB',
    gossipInterval: Duration(milliseconds: 600),
    fanout: 2,
  );

  final nodeCConfig = GossipConfig(
    nodeId: 'NodeC',
    gossipInterval: Duration(milliseconds: 700),
    fanout: 2,
  );

  // Create nodes with in-memory stores and transports
  final nodeA = GossipNode(
    config: nodeAConfig,
    eventStore: MemoryEventStore(),
    transport: InMemoryTransport('NodeA', transportRegistry),
  );

  final nodeB = GossipNode(
    config: nodeBConfig,
    eventStore: MemoryEventStore(),
    transport: InMemoryTransport('NodeB', transportRegistry),
  );

  final nodeC = GossipNode(
    config: nodeCConfig,
    eventStore: MemoryEventStore(),
    transport: InMemoryTransport('NodeC', transportRegistry),
  );

  // Set up event listeners
  nodeA.onEventCreated.listen((event) {
    print('🟢 NodeA created: ${event.payload}');
  });

  nodeB.onEventCreated.listen((event) {
    print('🔵 NodeB created: ${event.payload}');
  });

  nodeC.onEventCreated.listen((event) {
    print('🟡 NodeC created: ${event.payload}');
  });

  nodeA.onEventReceived.listen((event) {
    print('🟢 NodeA received: ${event.payload} from ${event.nodeId}');
  });

  nodeB.onEventReceived.listen((event) {
    print('🔵 NodeB received: ${event.payload} from ${event.nodeId}');
  });

  nodeC.onEventReceived.listen((event) {
    print('🟡 NodeC received: ${event.payload} from ${event.nodeId}');
  });

  // Start all nodes
  print('🚀 Starting nodes...\n');
  await Future.wait([nodeA.start(), nodeB.start(), nodeC.start()]);

  // Discover and add peers
  await Future.delayed(Duration(milliseconds: 100));
  await nodeA.discoverPeers();
  await nodeB.discoverPeers();
  await nodeC.discoverPeers();

  print('📡 Peers discovered and connected\n');

  // Create some initial events
  print('📝 Creating initial events...\n');

  await nodeA.createEvent({
    'type': 'user_action',
    'action': 'login',
    'user': 'alice',
  });
  await Future.delayed(Duration(milliseconds: 50));

  await nodeB.createEvent({'type': 'system', 'message': 'backup_started'});
  await Future.delayed(Duration(milliseconds: 50));

  await nodeC.createEvent({
    'type': 'user_action',
    'action': 'create_post',
    'user': 'bob',
  });

  print('\n⏳ Waiting for initial gossip synchronization...\n');
  await Future.delayed(Duration(seconds: 2));

  // Create more events after some syncing
  print('📝 Creating more events...\n');

  await nodeA.createEvent({
    'type': 'system',
    'message': 'maintenance_mode_enabled',
  });
  await nodeB.createEvent({
    'type': 'user_action',
    'action': 'logout',
    'user': 'charlie',
  });
  await nodeC.createEvent({
    'type': 'alert',
    'severity': 'high',
    'message': 'disk_space_low',
  });

  print('\n⏳ Waiting for final gossip synchronization...\n');
  await Future.delayed(Duration(seconds: 3));

  // Print final state
  print('\n📊 Final State Summary:');
  print('======================');

  final nodeAEvents = await nodeA.eventStore.getAllEvents();
  final nodeBEvents = await nodeB.eventStore.getAllEvents();
  final nodeCEvents = await nodeC.eventStore.getAllEvents();

  print('NodeA has ${nodeAEvents.length} events');
  print('NodeB has ${nodeBEvents.length} events');
  print('NodeC has ${nodeCEvents.length} events');

  // Print vector clock states
  print('\n🕐 Vector Clock States:');
  print('NodeA: ${nodeA.vectorClock}');
  print('NodeB: ${nodeB.vectorClock}');
  print('NodeC: ${nodeC.vectorClock}');

  // Verify synchronization
  if (nodeAEvents.length == nodeBEvents.length &&
      nodeBEvents.length == nodeCEvents.length) {
    print('\n✅ All nodes successfully synchronized!');
  } else {
    print('\n❌ Synchronization incomplete - some events may be missing');
  }

  // Print all events in chronological order
  print('\n📋 All Events (chronological order):');
  print('====================================');

  final allEvents = <Event>[];
  allEvents.addAll(nodeAEvents);

  // Sort by creation timestamp for display
  allEvents.sort((a, b) => a.creationTimestamp.compareTo(b.creationTimestamp));

  for (final event in allEvents) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      event.creationTimestamp,
    );
    print('${timestamp.toIso8601String()}: [${event.nodeId}] ${event.payload}');
  }

  // Show event store statistics
  print('\n📈 Event Store Statistics:');
  print('==========================');

  final statsA = await nodeA.eventStore.getStats();
  final statsB = await nodeB.eventStore.getStats();
  final statsC = await nodeC.eventStore.getStats();

  print(
    'NodeA: ${statsA.totalEvents} events, ${statsA.uniqueNodes} unique nodes',
  );
  print(
    'NodeB: ${statsB.totalEvents} events, ${statsB.uniqueNodes} unique nodes',
  );
  print(
    'NodeC: ${statsC.totalEvents} events, ${statsC.uniqueNodes} unique nodes',
  );

  // Clean shutdown
  print('\n🛑 Shutting down nodes...');
  await Future.wait([nodeA.stop(), nodeB.stop(), nodeC.stop()]);

  print('✅ Example completed successfully!');
}
