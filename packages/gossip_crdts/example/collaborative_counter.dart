/// Collaborative Counter Example
///
/// This example demonstrates how to use the gossip_crdts library to create
/// a distributed counter that can be incremented by multiple nodes and
/// automatically synchronizes across the network.

import 'dart:async';
import 'dart:math';

import 'package:gossip/gossip.dart';
import 'package:gossip_crdts/gossip_crdts.dart';

/// Simple in-memory transport for the example
class ExampleTransport implements GossipTransport {
  final String nodeId;
  final Map<String, ExampleTransport> _network;

  final StreamController<IncomingDigest> _digestController =
      StreamController<IncomingDigest>.broadcast();
  final StreamController<IncomingEvents> _eventsController =
      StreamController<IncomingEvents>.broadcast();

  ExampleTransport(this.nodeId, this._network);

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
  Future<GossipDigestResponse> sendDigest(
    GossipPeer peer,
    GossipDigest digest, {
    Duration? timeout,
  }) async {
    final targetTransport = _network[peer.id];
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
    final targetTransport = _network[peer.id];
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
  Future<List<GossipPeer>> discoverPeers() async {
    return _network.keys
        .where((id) => id != nodeId)
        .map((id) => GossipPeer(id: id, address: 'memory://$id'))
        .toList();
  }

  @override
  Future<bool> isPeerReachable(GossipPeer peer) async {
    return _network.containsKey(peer.id);
  }
}

void main() async {
  print('🚀 Starting Collaborative Counter Example\n');

  // Shared transport registry for in-memory communication
  final transportRegistry = <String, ExampleTransport>{};

  // Create three nodes with CRDT support
  final nodes = <CRDTEnabledGossipNode>[];

  for (int i = 1; i <= 3; i++) {
    final nodeId = 'node-$i';

    // Create regular gossip node
    final gossipNode = GossipNode(
      config: GossipConfig(
        nodeId: nodeId,
        gossipInterval: Duration(milliseconds: 500),
        fanout: 2,
      ),
      eventStore: MemoryEventStore(),
      transport: ExampleTransport(nodeId, transportRegistry),
    );

    // Enable CRDT support
    final crdtNode = await gossipNode.withCRDTSupport();
    nodes.add(crdtNode);

    print('✅ Created $nodeId with CRDT support');
  }

  // Start all nodes
  print('\n🌐 Starting gossip network...');
  for (final node in nodes) {
    await node.start();
  }

  // Discover peers
  await Future.delayed(Duration(milliseconds: 100));
  for (final node in nodes) {
    await node.gossipNode.discoverPeers();
  }
  print('✅ Peer discovery completed\n');

  // Register shared counters on all nodes
  print('📊 Setting up shared counters...');

  final counterNames = ['page-views', 'user-likes', 'downloads'];

  for (final node in nodes) {
    for (final counterName in counterNames) {
      // Create both increment-only and increment/decrement counters
      final gCounter = GCounter('$counterName-grow');
      final pnCounter = PNCounter('$counterName-votes');

      await node.registerCRDT(gCounter);
      await node.registerCRDT(pnCounter);
    }
  }
  print('✅ Counters registered on all nodes\n');

  // Set up event listeners
  for (int i = 0; i < nodes.length; i++) {
    final node = nodes[i];
    final nodeId = node.config.nodeId;

    node.onCRDTOperation.listen((operationEvent) {
      final op = operationEvent.operation;
      final source =
          operationEvent.source == CRDTOperationSource.local ? '📤' : '📥';
      print('$source $nodeId: ${op.operation}(${op.data}) on ${op.crdtId}');
    });
  }

  // Simulate collaborative counter usage
  print('🎯 Starting collaborative counter simulation...\n');

  final random = Random();

  // Simulate 20 operations across all nodes
  for (int round = 1; round <= 20; round++) {
    print('--- Round $round ---');

    // Pick random node and counter
    final node = nodes[random.nextInt(nodes.length)];
    final counterName = counterNames[random.nextInt(counterNames.length)];
    final useGCounter = random.nextBool();

    final crdtId = useGCounter ? '$counterName-grow' : '$counterName-votes';

    if (useGCounter) {
      // G-Counter: only increment
      final amount = random.nextInt(5) + 1;
      await node.performCRDTOperation(crdtId, 'increment', {'amount': amount});
    } else {
      // PN-Counter: increment or decrement
      final isIncrement = random.nextBool();
      final operation = isIncrement ? 'increment' : 'decrement';
      final amount = random.nextInt(3) + 1;
      await node.performCRDTOperation(crdtId, operation, {'amount': amount});
    }

    // Allow some time for gossip synchronization
    await Future.delayed(Duration(milliseconds: 100));

    // Occasionally trigger manual sync
    if (round % 5 == 0) {
      print('🔄 Triggering manual synchronization...');
      await node.forceCRDTSync();
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  print('\n⏳ Waiting for final synchronization...');
  await Future.delayed(Duration(seconds: 2));

  // Display final counter values from all nodes
  print('\n📈 Final Counter Values:');
  print('========================');

  for (final counterName in counterNames) {
    print('\n🏷️  $counterName:');

    // Show G-Counter values
    final gCounterId = '$counterName-grow';
    print('   Grow-only counter ($gCounterId):');
    for (final node in nodes) {
      final gCounter = node.getCRDT<GCounter>(gCounterId);
      print('     ${node.config.nodeId}: ${gCounter?.value ?? 0}');
    }

    // Show PN-Counter values
    final pnCounterId = '$counterName-votes';
    print('   Vote counter ($pnCounterId):');
    for (final node in nodes) {
      final pnCounter = node.getCRDT<PNCounter>(pnCounterId);
      if (pnCounter != null) {
        print(
          '     ${node.config.nodeId}: ${pnCounter.value} '
          '(+${pnCounter.totalPositive}, -${pnCounter.totalNegative})',
        );
      }
    }
  }

  // Verify convergence
  print('\n🔍 Verifying Convergence:');
  print('=========================');

  bool allConverged = true;

  for (final counterName in counterNames) {
    // Check G-Counter convergence
    final gCounterId = '$counterName-grow';
    final gValues =
        nodes.map((n) => n.getCRDT<GCounter>(gCounterId)?.value ?? 0).toSet();
    final gConverged = gValues.length == 1;
    print(
      '✓ $gCounterId: ${gConverged ? 'CONVERGED' : 'NOT CONVERGED'} (values: $gValues)',
    );
    if (!gConverged) allConverged = false;

    // Check PN-Counter convergence
    final pnCounterId = '$counterName-votes';
    final pnValues =
        nodes.map((n) => n.getCRDT<PNCounter>(pnCounterId)?.value ?? 0).toSet();
    final pnConverged = pnValues.length == 1;
    print(
      '✓ $pnCounterId: ${pnConverged ? 'CONVERGED' : 'NOT CONVERGED'} (values: $pnValues)',
    );
    if (!pnConverged) allConverged = false;
  }

  if (allConverged) {
    print('\n🎉 All counters have converged successfully!');
  } else {
    print('\n⚠️  Some counters have not fully converged yet.');
  }

  // Show CRDT statistics
  print('\n📊 CRDT Manager Statistics:');
  print('============================');

  for (final node in nodes) {
    final stats = node.getCRDTStats();
    print(
      '${node.config.nodeId}: ${stats.totalCRDTs} CRDTs, '
      'types: ${stats.crdtTypes}',
    );
  }

  // Clean shutdown
  print('\n🛑 Shutting down nodes...');
  for (final node in nodes) {
    await node.close();
  }

  print('✅ Collaborative Counter Example completed successfully!');
}
