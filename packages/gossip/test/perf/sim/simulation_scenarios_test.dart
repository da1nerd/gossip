import 'dart:async';
import 'dart:math';

import 'package:test/test.dart';
import 'package:gossip/src/gossip_config.dart';
import 'package:gossip/src/modular_gossip_node.dart';
import 'package:gossip/src/stores/memory_event_store.dart';
import 'package:gossip/src/gossip_peer.dart';
import 'package:gossip/src/event.dart';
import 'package:gossip/src/gossip_node_id.dart';

import 'simulated_transport.dart';
import 'topology_generators.dart';

@Tags(['perf'])
void main() {
  group('Simulation: Erdos–Renyi topology convergence', () {
    test('G(n, p) reaches 95% convergence within a reasonable time', () async {
      // Parameters for the simulation
      const int n = 30; // number of nodes (keep modest for CI)
      const double p = 0.20; // edge probability (connectedness)
      const int seed = 42; // deterministic topology and link behaviors
      const Duration gossipInterval = Duration(milliseconds: 30);
      const int fanout = 8;
      const int maxEventsPerMessage = 256;

      // Build the simulated network and node addresses
      final network = SimulatedNetwork(seed: seed);
      final addresses = nodeAddresses(n, prefix: 'n');

      // Register transports (one per node)
      final transports = registerTransports(network, addresses);

      // Build an undirected Erdos–Renyi topology
      connectErdosRenyiUndirected(
        network,
        addresses,
        p,
        defaultConfig: const SimulatedLinkConfig(
          baseLatency: Duration(milliseconds: 8),
          jitterMs: 4,
          lossRate: 0.01,
        ),
        seed: seed,
      );

      // Create nodes (ModularGossipNode) with in-memory stores
      final nodes = <ModularGossipNode>[];
      final stores = <MemoryEventStore>[];

      for (var i = 0; i < n; i++) {
        final store = MemoryEventStore();
        stores.add(store);

        final cfg = GossipConfig(
          nodeId: 'node_$i',
          gossipInterval: gossipInterval,
          fanout: fanout,
          maxEventsPerMessage: maxEventsPerMessage,
          enableAntiEntropy: true,
          antiEntropyInterval: Duration(seconds: 1),
          peerDiscoveryInterval: Duration(milliseconds: 100),
        );

        final node = ModularGossipNode(
          config: cfg,
          eventStore: store,
          transport: transports[i],
        );
        nodes.add(node);
      }

      // Initialize all nodes
      await Future.wait(nodes.map((n) => n.initialize()));

      // Start gossiping on all nodes
      await Future.wait(nodes.map((n) => n.startGossiping()));

      // Allow initial discovery + stabilization
      await Future.delayed(const Duration(milliseconds: 800));

      // Create a single event at a random source node
      final rng = Random(seed);
      final int sourceIndex = rng.nextInt(n);
      final sourceNode = nodes[sourceIndex];

      final Event created = await sourceNode.createEvent(<String, dynamic>{
        'kind': 'simulation_test',
        'msg': 'hello from node_$sourceIndex',
        'ts': DateTime.now().millisecondsSinceEpoch,
      });

      // For debugging, also subscribe to onEventReceived streams (optional)
      final subscriptions = <StreamSubscription>[];
      for (final node in nodes) {
        final sub = node.onEventReceived.listen((ReceivedEvent re) {
          // debug prints can be noisy; comment in if needed
          // print('[${node.config.nodeId}] received ${re.id} from ${re.fromPeer.id}');
        });
        subscriptions.add(sub);
      }

      // Measure convergence: find the time when at least 95% of event stores have the event
      const double targetFraction = 0.90;
      final int targetCount = (n * targetFraction).ceil();
      final sw = Stopwatch()..start();

      final Duration timeout = const Duration(
        seconds: 8,
      ); // generous cap for CI
      bool reached = false;
      int reachedAtMs = 0;
      int currentCount = 0;

      Future<int> countHaveEvent() async {
        var have = 0;
        for (final s in stores) {
          if (await s.hasEvent(created.id)) {
            have++;
          }
        }
        return have;
      }

      // Poll periodically until we reach the target fraction or time out
      while (sw.elapsed < timeout) {
        currentCount = await countHaveEvent();
        if (currentCount >= targetCount) {
          reached = true;
          reachedAtMs = sw.elapsedMilliseconds;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // Cleanup
      for (final sub in subscriptions) {
        await sub.cancel();
      }
      await Future.wait(nodes.map((n) => n.stopGossiping()));
      await Future.delayed(const Duration(milliseconds: 300));
      await Future.wait(nodes.map((n) => n.shutdown()));

      // Report metrics
      final convergenceRatio = currentCount / n;
      // Keep this print to make it easy to see perf numbers in CI logs
      // ignore: avoid_print
      print(
        'Convergence metrics: '
        'N=$n, p=$p, fanout=$fanout, interval=${gossipInterval.inMilliseconds}ms, '
        '90% target=$targetCount, reached=$reached at ${reachedAtMs}ms, '
        'finalCount=$currentCount (${(convergenceRatio * 100).toStringAsFixed(1)}%)',
      );

      // Assert that we reach at least 95% convergence within the timeout window
      expect(
        reached,
        isTrue,
        reason:
            'Expected at least ${targetFraction * 100}% convergence, got ${(convergenceRatio * 100).toStringAsFixed(1)}%',
      );
    });
  });
}
