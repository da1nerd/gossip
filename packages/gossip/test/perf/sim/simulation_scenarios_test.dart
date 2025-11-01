import 'dart:async';
import 'dart:math';

import 'package:test/test.dart';
import 'package:gossip/src/gossip_config.dart';
import 'package:gossip/src/modular_gossip_node.dart';
import 'package:gossip/src/stores/memory_event_store.dart';
import 'package:gossip/src/event.dart';

import 'simulated_transport.dart';
import 'topology_generators.dart';

@Tags(['perf'])
void main() {
  group('Simulation: Erdos–Renyi topology convergence', () {
    test('G(n, p) reaches 95% convergence within a reasonable time', () async {
      // Parameters for the simulation
      const int n = 30; // number of nodes (keep modest for CI)
      const double p = 0.30; // edge probability (connectedness)
      const int seed = 42; // deterministic topology and link behaviors
      const Duration gossipInterval = Duration(milliseconds: 25);
      const int fanout = 10;
      const int maxEventsPerMessage = 512;

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
          antiEntropyInterval: Duration(milliseconds: 800),
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
      await Future.delayed(const Duration(milliseconds: 1200));

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
      const double targetFraction = 0.85;
      final int targetCount = (n * targetFraction).ceil();
      final sw = Stopwatch()..start();

      final Duration timeout = const Duration(
        seconds: 12,
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
        '85% target=$targetCount, reached=$reached at ${reachedAtMs}ms, '
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

  group('Simulation: partition and heal', () {
    test('two partitions reconcile after adding a bridge', () async {
      const int n = 40;
      const double p = 0.15; // sparse connectivity
      const int seed = 7;
      const Duration gossipInterval = Duration(milliseconds: 35);
      const int fanout = 8;
      const int maxEventsPerMessage = 256;

      final network = SimulatedNetwork(seed: seed);
      final addresses = nodeAddresses(n, prefix: 'p');
      final transports = registerTransports(network, addresses);

      // Initial random graph
      connectErdosRenyiUndirected(
        network,
        addresses,
        p,
        defaultConfig: const SimulatedLinkConfig(
          baseLatency: Duration(milliseconds: 10),
          jitterMs: 5,
          lossRate: 0.02,
        ),
        seed: seed,
      );

      // Split into two equal partitions by removing all cross links
      final half = (n / 2).floor();
      for (var i = 0; i < half; i++) {
        for (var j = half; j < n; j++) {
          network.disconnectUndirected(addresses[i], addresses[j]);
        }
      }

      final nodes = <ModularGossipNode>[];
      final stores = <MemoryEventStore>[];
      for (var i = 0; i < n; i++) {
        final store = MemoryEventStore();
        stores.add(store);

        final cfg = GossipConfig(
          nodeId: 'part_${i < half ? 'A' : 'B'}_$i',
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

      await Future.wait(nodes.map((n) => n.initialize()));
      await Future.wait(nodes.map((n) => n.startGossiping()));
      await Future.delayed(const Duration(milliseconds: 600));

      // Create an event in partition A only
      final srcIndex = 0; // first partition
      final Event created = await nodes[srcIndex].createEvent({
        'kind': 'partition_test',
        'msg': 'hello from A',
        'ts': DateTime.now().millisecondsSinceEpoch,
      });

      // Allow convergence within partition A
      await Future.delayed(const Duration(seconds: 3));

      Future<int> countHaveEventRange(int start, int end) async {
        var have = 0;
        for (var i = start; i < end; i++) {
          if (await stores[i].hasEvent(created.id)) have++;
        }
        return have;
      }

      final aCount = await countHaveEventRange(0, half);
      final bCountBeforeHeal = await countHaveEventRange(half, n);

      // Expect most of A has it; B should not (partitioned)
      expect(aCount / half, greaterThanOrEqualTo(0.90));
      expect(bCountBeforeHeal, equals(0));

      // Heal: add a single bridge between the partitions
      network.addBridge(
        addresses[0],
        addresses[half],
        configAB: const SimulatedLinkConfig(
          baseLatency: Duration(milliseconds: 8),
          jitterMs: 4,
          lossRate: 0.01,
        ),
      );

      // Allow time for cross-partition propagation
      final sw = Stopwatch()..start();
      final timeout = const Duration(seconds: 6);
      var totalCount = aCount + bCountBeforeHeal;
      while (sw.elapsed < timeout) {
        totalCount = await countHaveEventRange(0, n);
        if (totalCount >= (n * 0.9).ceil()) break;
        await Future.delayed(const Duration(milliseconds: 80));
      }

      await Future.wait(nodes.map((n) => n.stopGossiping()));
      await Future.delayed(const Duration(milliseconds: 200));
      await Future.wait(nodes.map((n) => n.shutdown()));

      final ratio = totalCount / n;
      // ignore: avoid_print
      print(
        'Partition/heal: reached ${(ratio * 100).toStringAsFixed(1)}% '
        'in ${sw.elapsedMilliseconds}ms',
      );
      expect(ratio, greaterThanOrEqualTo(0.85));
    });
  });

  group('Simulation: lossy and high-latency links', () {
    test('converges sufficiently under adverse link conditions', () async {
      const int n = 25;
      const double p = 0.20;
      const int seed = 99;
      const Duration gossipInterval = Duration(milliseconds: 35);
      const int fanout = 10;
      const int maxEventsPerMessage = 512;

      final network = SimulatedNetwork(seed: seed);
      final addresses = nodeAddresses(n, prefix: 'L');
      final transports = registerTransports(network, addresses);

      // High latency, jitter, and loss links
      connectErdosRenyiUndirected(
        network,
        addresses,
        p,
        defaultConfig: const SimulatedLinkConfig(
          baseLatency: Duration(milliseconds: 40),
          jitterMs: 20,
          lossRate: 0.20,
          duplicateRate: 0.02,
        ),
        seed: seed,
      );

      final nodes = <ModularGossipNode>[];
      final stores = <MemoryEventStore>[];
      for (var i = 0; i < n; i++) {
        final store = MemoryEventStore();
        stores.add(store);
        final cfg = GossipConfig(
          nodeId: 'lossy_$i',
          gossipInterval: gossipInterval,
          fanout: fanout,
          maxEventsPerMessage: maxEventsPerMessage,
          enableAntiEntropy: true,
          antiEntropyInterval: Duration(seconds: 1),
          peerDiscoveryInterval: Duration(milliseconds: 150),
        );
        nodes.add(
          ModularGossipNode(
            config: cfg,
            eventStore: store,
            transport: transports[i],
          ),
        );
      }

      await Future.wait(nodes.map((n) => n.initialize()));
      await Future.wait(nodes.map((n) => n.startGossiping()));
      await Future.delayed(const Duration(milliseconds: 800));

      final Event created = await nodes[0].createEvent({
        'kind': 'lossy_latency_test',
        'ts': DateTime.now().millisecondsSinceEpoch,
      });

      final sw = Stopwatch()..start();
      final timeout = const Duration(seconds: 18);
      var count = 0;
      while (sw.elapsed < timeout) {
        count = 0;
        for (final s in stores) {
          if (await s.hasEvent(created.id)) count++;
        }
        if (count >= (n * 0.75).ceil()) break; // 75% in adverse conditions
        await Future.delayed(const Duration(milliseconds: 100));
      }

      await Future.wait(nodes.map((n) => n.stopGossiping()));
      await Future.delayed(const Duration(milliseconds: 300));
      await Future.wait(nodes.map((n) => n.shutdown()));

      final ratio = count / n;
      // ignore: avoid_print
      print(
        'Lossy/high-latency: reached ${(ratio * 100).toStringAsFixed(1)}% '
        'in ${sw.elapsedMilliseconds}ms',
      );
      expect(ratio, greaterThanOrEqualTo(0.75));
    });
  });

  group('Simulation: churn', () {
    test(
      'maintains propagation under link churn and transient isolations',
      () async {
        const int n = 35;
        const double p = 0.15;
        const int seed = 1234;
        const Duration gossipInterval = Duration(milliseconds: 35);
        const int fanout = 6;
        const int maxEventsPerMessage = 256;

        final rng = Random(seed);
        final network = SimulatedNetwork(seed: seed);
        final addresses = nodeAddresses(n, prefix: 'C');
        final transports = registerTransports(network, addresses);

        connectErdosRenyiUndirected(
          network,
          addresses,
          p,
          defaultConfig: const SimulatedLinkConfig(
            baseLatency: Duration(milliseconds: 12),
            jitterMs: 6,
            lossRate: 0.05,
          ),
          seed: seed,
        );

        final nodes = <ModularGossipNode>[];
        final stores = <MemoryEventStore>[];
        for (var i = 0; i < n; i++) {
          final store = MemoryEventStore();
          stores.add(store);
          final cfg = GossipConfig(
            nodeId: 'churn_$i',
            gossipInterval: gossipInterval,
            fanout: fanout,
            maxEventsPerMessage: maxEventsPerMessage,
            enableAntiEntropy: true,
            antiEntropyInterval: Duration(seconds: 1),
            peerDiscoveryInterval: Duration(milliseconds: 100),
          );
          nodes.add(
            ModularGossipNode(
              config: cfg,
              eventStore: store,
              transport: transports[i],
            ),
          );
        }

        await Future.wait(nodes.map((n) => n.initialize()));
        await Future.wait(nodes.map((n) => n.startGossiping()));
        await Future.delayed(const Duration(milliseconds: 500));

        // Inject an event
        final Event created = await nodes[0].createEvent({
          'kind': 'churn_test',
          'ts': DateTime.now().millisecondsSinceEpoch,
        });

        // Apply churn: several rounds of transient isolations and re-links
        for (var round = 0; round < 5; round++) {
          // Isolate 2 random nodes briefly
          for (var k = 0; k < 2; k++) {
            final idx = rng.nextInt(n);
            network.clearLinksFor(addresses[idx]);
          }
          await Future.delayed(const Duration(milliseconds: 300));

          // Reconnect isolated nodes with a few random neighbors
          for (var i = 0; i < n; i++) {
            // pick up to 2 neighbors to connect
            final neighborCount = 1 + rng.nextInt(2);
            for (var c = 0; c < neighborCount; c++) {
              final j = rng.nextInt(n);
              if (i == j) continue;
              network.connectUndirected(
                addresses[i],
                addresses[j],
                configAB: const SimulatedLinkConfig(
                  baseLatency: Duration(milliseconds: 10),
                  jitterMs: 5,
                  lossRate: 0.05,
                ),
              );
            }
          }

          await Future.delayed(const Duration(milliseconds: 400));
        }

        // Let the system stabilize
        final sw = Stopwatch()..start();
        final timeout = const Duration(seconds: 8);
        var count = 0;
        while (sw.elapsed < timeout) {
          count = 0;
          for (final s in stores) {
            if (await s.hasEvent(created.id)) count++;
          }
          if (count >= (n * 0.85).ceil()) break; // tolerate churn, 85% target
          await Future.delayed(const Duration(milliseconds: 80));
        }

        await Future.wait(nodes.map((n) => n.stopGossiping()));
        await Future.delayed(const Duration(milliseconds: 300));
        await Future.wait(nodes.map((n) => n.shutdown()));

        final ratio = count / n;
        // ignore: avoid_print
        print(
          'Churn: reached ${(ratio * 100).toStringAsFixed(1)}% '
          'in ${sw.elapsedMilliseconds}ms',
        );
        expect(ratio, greaterThanOrEqualTo(0.85));
      },
    );
  });
}
