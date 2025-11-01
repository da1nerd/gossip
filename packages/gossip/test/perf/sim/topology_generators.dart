import 'dart:math';

import 'package:gossip/src/transport.dart';

import 'simulated_transport.dart';

/// Topology generators for simulation test harnesses.
///
/// Provides utilities to generate graph structures (adjacency via links) on a
/// [SimulatedNetwork] without real network I/O. These are useful for driving
/// large-scale simulations with varying connectedness.
///
/// This file currently provides Erdos–Renyi G(n, p) generators for:
/// - Undirected graphs: each undirected edge is included independently with probability p
/// - Directed graphs: each ordered edge is included independently with probability p
///
/// Notes:
/// - You must create and register SimulatedTransport instances (one per node)
///   with the network before invoking these generators. The generators only
///   add links between existing addresses.
/// - Use the optional [linkFactory] to vary link characteristics per edge
///   (e.g., different base latencies, loss rates).
/// - If [linkFactory] is not provided, [defaultConfig] is applied uniformly.
class TopologyGenerators {
  TopologyGenerators._(); // static-only
}

/// Creates a list of [TransportPeerAddress] for N nodes with a given [prefix].
///
/// Example:
///   final nodes = nodeAddresses(5, prefix: 'node'); // node0..node4
List<TransportPeerAddress> nodeAddresses(int n, {String prefix = 'n'}) {
  assert(n >= 0, 'n must be non-negative');
  return List<TransportPeerAddress>.generate(
    n,
    (i) => TransportPeerAddress('$prefix$i'),
    growable: false,
  );
}

/// Generates an Erdos–Renyi undirected graph G(n, p) over [nodes] on [network].
///
/// For each unordered pair (i, j), an undirected edge is added with probability [p].
/// When an edge is added, the link is created in both directions using
/// [SimulatedNetwork.connectUndirected]. Link behavior is either the provided
/// [defaultConfig], or, if [linkFactory] is provided, derived per edge using
/// that function.
///
/// Parameters:
/// - [network]: The simulated network to configure
/// - [nodes]: The node addresses already registered with the network
/// - [p]: Probability in [0, 1] of including an undirected edge
/// - [defaultConfig]: Link configuration to apply when [linkFactory] is null
/// - [seed]: RNG seed for deterministic topology generation
/// - [linkFactory]: Optional factory to generate per-edge link configuration
///
/// Example:
///   final net = SimulatedNetwork(seed: 42);
///   final nodes = nodeAddresses(100, prefix: 'n');
///   // Register transports for each node (not shown)
///   connectErdosRenyiUndirected(
///     net,
///     nodes,
///     0.05,
///     defaultConfig: SimulatedLinkConfig(
///       baseLatency: Duration(milliseconds: 8),
///       jitterMs: 4,
///       lossRate: 0.01,
///     ),
///   );
void connectErdosRenyiUndirected(
  SimulatedNetwork network,
  List<TransportPeerAddress> nodes,
  double p, {
  SimulatedLinkConfig defaultConfig = const SimulatedLinkConfig(),
  int? seed,
  SimulatedLinkConfig Function(
    TransportPeerAddress a,
    TransportPeerAddress b,
    Random rng,
  )?
  linkFactory,
}) {
  assert(p >= 0.0 && p <= 1.0, 'p must be in [0, 1]');
  if (nodes.length < 2) return;

  final rng = Random(seed);
  for (var i = 0; i < nodes.length; i++) {
    final a = nodes[i];
    for (var j = i + 1; j < nodes.length; j++) {
      final b = nodes[j];
      if (rng.nextDouble() <= p) {
        final cfg = linkFactory != null
            ? linkFactory(a, b, rng)
            : defaultConfig;
        network.connectUndirected(a, b, configAB: cfg);
      }
    }
  }
}

/// Generates an Erdos–Renyi directed graph over [nodes] on [network].
///
/// For each ordered pair (i -> j), i != j, a directed edge is included with probability [p].
/// Each directed edge uses [SimulatedNetwork.connectDirected].
/// Link behavior is either the provided [defaultConfig], or, if [linkFactory] is
/// provided, derived per directed edge using that function.
///
/// Parameters:
/// - [network]: The simulated network to configure
/// - [nodes]: The node addresses already registered with the network
/// - [p]: Probability in [0, 1] of including a directed edge i -> j
/// - [defaultConfig]: Link configuration to apply when [linkFactory] is null
/// - [seed]: RNG seed for deterministic topology generation
/// - [linkFactory]: Optional factory to generate per-directed-edge link configuration
///
/// Example:
///   connectErdosRenyiDirected(
///     net,
///     nodes,
///     0.02,
///     defaultConfig: SimulatedLinkConfig(
///       baseLatency: Duration(milliseconds: 12),
///       jitterMs: 6,
///     ),
///   );
void connectErdosRenyiDirected(
  SimulatedNetwork network,
  List<TransportPeerAddress> nodes,
  double p, {
  SimulatedLinkConfig defaultConfig = const SimulatedLinkConfig(),
  int? seed,
  SimulatedLinkConfig Function(
    TransportPeerAddress from,
    TransportPeerAddress to,
    Random rng,
  )?
  linkFactory,
}) {
  assert(p >= 0.0 && p <= 1.0, 'p must be in [0, 1]');
  if (nodes.length < 2) return;

  final rng = Random(seed);
  for (var i = 0; i < nodes.length; i++) {
    final from = nodes[i];
    for (var j = 0; j < nodes.length; j++) {
      if (i == j) continue;
      final to = nodes[j];
      if (rng.nextDouble() <= p) {
        final cfg = linkFactory != null
            ? linkFactory(from, to, rng)
            : defaultConfig;
        network.connectDirected(from, to, config: cfg);
      }
    }
  }
}

/// Convenience helper to create and register a set of [SimulatedTransport]s for
/// the provided [nodes] on [network].
///
/// This is useful to keep simulations concise: addresses must be registered with
/// the network for peer discovery and delivery, so this utility will instantiate
/// transports bound to the given addresses and return them.
///
/// Example:
///   final net = SimulatedNetwork(seed: 42);
///   final nodes = nodeAddresses(50, prefix: 'n');
///   final transports = registerTransports(net, nodes);
///   // Now build ModularGossipNode instances with these transports...
List<SimulatedTransport> registerTransports(
  SimulatedNetwork network,
  List<TransportPeerAddress> nodes, {
  String? displayNamePrefix,
}) {
  final out = <SimulatedTransport>[];
  for (var i = 0; i < nodes.length; i++) {
    final addrValue = nodes[i].value;
    out.add(
      SimulatedTransport(
        network: network,
        address: TransportPeerAddress(addrValue),
        displayName: displayNamePrefix != null
            ? '$displayNamePrefix$i'
            : addrValue,
      ),
    );
  }
  return out;
}
