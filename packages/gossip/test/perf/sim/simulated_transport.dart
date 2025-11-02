import 'dart:async';
import 'dart:math';

import 'package:gossip/src/gossip_digest.dart';
import 'package:gossip/src/gossip_digest_response.dart';
import 'package:gossip/src/gossip_event_message.dart';
import 'package:gossip/src/gossip_transport.dart';
import 'package:gossip/src/exceptions.dart';

/// In-process, configurable transport for large-scale performance simulations.
///
/// This transport avoids real network I/O and allows you to:
/// - Define connectivity/topology (adjacency) across peers
/// - Configure per-link latency, jitter, packet loss, and duplication
/// - Run many nodes in the same process deterministically
///
/// Usage:
/// - Build a [SimulatedNetwork]
/// - Register nodes (transports) with addresses on the network
/// - Wire each node to a ModularGossipNode or use-cases for testing
/// - Drive gossip cycles in tests and collect metrics
class SimulatedTransport extends GossipTransport {
  final SimulatedNetwork network;
  final TransportPeer self;

  final _incomingDigestsController =
      StreamController<IncomingDigest>.broadcast();
  final _incomingEventsController =
      StreamController<IncomingEvents>.broadcast();

  bool _initialized = false;
  bool _started = false;
  bool _closed = false;

  // Track pending digest requests to cancel/complete on shutdown.
  final Set<Completer<GossipDigestResponse>> _pendingDigestCompleters = {};
  final Set<
    StreamSubscription<MapEntry<TransportPeerAddress, GossipDigestResponse>>
  >
  _pendingDigestSubscriptions = {};

  SimulatedTransport({
    required this.network,
    required TransportPeerAddress address,
    String? displayName,
    DateTime? connectedAt,
    bool isActive = true,
    Map<String, dynamic> metadata = const {},
  }) : self = TransportPeer(
         address: address,
         displayName: displayName ?? address.value,
         connectedAt: connectedAt ?? DateTime.now(),
         isActive: isActive,
         metadata: metadata,
       ) {
    network.register(this);
  }

  @override
  Future<void> initialize() async {
    _ensureNotClosed();
    _initialized = true;
  }

  @override
  Future<void> shutdown() async {
    if (_closed) return;
    await stop();

    // Complete any pending digest requests with an error and cancel subscriptions.
    for (final sub in _pendingDigestSubscriptions.toList()) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
    _pendingDigestSubscriptions.clear();
    for (final c in _pendingDigestCompleters.toList()) {
      if (!c.isCompleted) {
        c.completeError(
          TransportException('SimulatedTransport is shutting down'),
        );
      }
    }
    _pendingDigestCompleters.clear();

    _incomingDigestsController.close();
    _incomingEventsController.close();
    network.unregister(self.address);
    _closed = true;
  }

  @override
  Future<void> start() async {
    _ensureInitialized();
    _started = true;
  }

  @override
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
  }

  @override
  Stream<IncomingDigest> get incomingDigests =>
      _incomingDigestsController.stream;

  @override
  Stream<IncomingEvents> get incomingEvents => _incomingEventsController.stream;

  /// Sends a digest to [transportPeer] and waits for the response.
  ///
  /// Under the simulated network, this call uses the configured link behavior
  /// (latency, loss, duplication) between this node and the destination. The
  /// response path experiences the link behavior from destination back to this node.
  @override
  Future<GossipDigestResponse> sendDigest(
    TransportPeer transportPeer,
    GossipDigest digest, {
    Duration? timeout,
  }) async {
    _ensureStarted();

    final completer = Completer<GossipDigestResponse>();
    _pendingDigestCompleters.add(completer);

    // Construct the incoming message for the destination peer with a respond callback.
    final incoming = IncomingDigest(
      fromTransportPeer: self,
      digest: digest,
      respond: (GossipDigestResponse response) async {
        // Deliver the response back to this node via the network
        await network.deliverDigestResponse(
          from: transportPeer.address,
          to: self.address,
          response: response,
        );
      },
    );

    // Register a one-shot listener for the response
    final sub = network._onDigestResponseFor(self.address).listen((entry) {
      if (entry.key == transportPeer.address && !completer.isCompleted) {
        completer.complete(entry.value);
      }
    });
    _pendingDigestSubscriptions.add(sub);

    // Send the digest to the destination
    await network.deliverDigest(
      from: self.address,
      to: transportPeer.address,
      message: incoming,
    );

    // Respect timeout if provided
    if (timeout != null) {
      final future = completer.future.timeout(
        timeout,
        onTimeout: () {
          // Cancel listener and signal timeout via TransportException.
          // Also complete the underlying completer with error for cleanup.
          sub.cancel();
          _pendingDigestSubscriptions.remove(sub);
          final err = TransportException(
            'SimulatedTransport timeout waiting for GossipDigestResponse '
            'from ${transportPeer.address} after ${timeout.inMilliseconds}ms',
          );
          if (!completer.isCompleted) {
            completer.completeError(err);
          }
          throw err;
        },
      );
      try {
        final result = await future;
        return result;
      } finally {
        _pendingDigestCompleters.remove(completer);
        _pendingDigestSubscriptions.remove(sub);
        await sub.cancel();
      }
    }

    try {
      final result = await completer.future;
      return result;
    } finally {
      _pendingDigestCompleters.remove(completer);
      _pendingDigestSubscriptions.remove(sub);
      await sub.cancel();
    }
  }

  /// Sends a final gossip event message to [transportPeer].
  @override
  Future<void> sendEvents(
    TransportPeer transportPeer,
    GossipEventMessage message, {
    Duration? timeout,
  }) async {
    _ensureStarted();
    await network.deliverEvents(
      from: self.address,
      to: transportPeer.address,
      message: IncomingEvents(fromTransportPeer: self, message: message),
    );
  }

  /// Discovers peers reachable from this node as defined by the network.
  @override
  Future<List<TransportPeer>> discoverPeers() async {
    _ensureInitialized();
    final neighbors = network.neighborsOf(self.address);
    final peers = <TransportPeer>[];
    for (final addr in neighbors) {
      final peer = network.peerFor(addr);
      if (peer != null) {
        peers.add(peer);
      }
    }
    return peers;
  }

  // Internal: deliver incoming digest to this node (called by network)
  void _emitIncomingDigest(IncomingDigest digest) {
    if (_incomingDigestsController.isClosed) return;
    _incomingDigestsController.add(digest);
  }

  // Internal: deliver incoming events to this node (called by network)
  void _emitIncomingEvents(IncomingEvents events) {
    if (_incomingEventsController.isClosed) return;
    _incomingEventsController.add(events);
  }

  void _ensureInitialized() {
    if (_closed) {
      throw TransportException('SimulatedTransport is closed');
    }
    if (!_initialized) {
      throw TransportException('SimulatedTransport must be initialized first');
    }
  }

  void _ensureStarted() {
    _ensureInitialized();
    if (!_started) {
      throw TransportException('SimulatedTransport must be started first');
    }
  }

  void _ensureNotClosed() {
    if (_closed) {
      throw TransportException('SimulatedTransport is closed');
    }
  }
}

/// Link behavior configuration between two peers.
class SimulatedLinkConfig {
  /// Base one-way latency.
  final Duration baseLatency;

  /// Additional jitter in milliseconds (uniform +- jitterMs).
  final double jitterMs;

  /// Probability [0.0, 1.0] that a packet is dropped.
  final double lossRate;

  /// Probability [0.0, 1.0] to duplicate a packet (delivered twice).
  final double duplicateRate;

  const SimulatedLinkConfig({
    this.baseLatency = const Duration(milliseconds: 10),
    this.jitterMs = 0.0,
    this.lossRate = 0.0,
    this.duplicateRate = 0.0,
  });

  Duration sampleLatency(Random rng) {
    if (jitterMs == 0) return baseLatency;
    final jitter = (rng.nextDouble() * 2 - 1) * jitterMs;
    final totalMs = max(0, baseLatency.inMilliseconds + jitter.round());
    return Duration(milliseconds: totalMs);
  }

  bool shouldDrop(Random rng) => rng.nextDouble() < lossRate;

  bool shouldDuplicate(Random rng) => rng.nextDouble() < duplicateRate;
}

/// Simulated network coordinates deliveries between in-process transports.
class SimulatedNetwork {
  final Map<TransportPeerAddress, SimulatedTransport> _registry = {};
  final Map<TransportPeerAddress, Set<TransportPeerAddress>> _adjacency = {};
  final Map<
    TransportPeerAddress,
    Map<TransportPeerAddress, SimulatedLinkConfig>
  >
  _links = {};
  final Random rng;

  // One-off response streams keyed by destination address for digest responses
  final Map<
    TransportPeerAddress,
    StreamController<MapEntry<TransportPeerAddress, GossipDigestResponse>>
  >
  _digestResponseStreams = {};

  SimulatedNetwork({int? seed}) : rng = Random(seed);

  /// Registers a transport in the network.
  void register(SimulatedTransport transport) {
    _registry[transport.self.address] = transport;
    _adjacency.putIfAbsent(
      transport.self.address,
      () => <TransportPeerAddress>{},
    );
  }

  /// Unregisters a transport from the network.
  void unregister(TransportPeerAddress address) {
    _registry.remove(address);
    _adjacency.remove(address);
    _links.remove(address);
    final ctrl = _digestResponseStreams.remove(address);
    ctrl?.close();
  }

  /// Link creation helpers (directed or undirected).
  void connectDirected(
    TransportPeerAddress from,
    TransportPeerAddress to, {
    SimulatedLinkConfig config = const SimulatedLinkConfig(),
  }) {
    _adjacency.putIfAbsent(from, () => <TransportPeerAddress>{}).add(to);
    _links.putIfAbsent(
      from,
      () => <TransportPeerAddress, SimulatedLinkConfig>{},
    )[to] = config;
  }

  void connectUndirected(
    TransportPeerAddress a,
    TransportPeerAddress b, {
    SimulatedLinkConfig configAB = const SimulatedLinkConfig(),
    SimulatedLinkConfig? configBA,
  }) {
    connectDirected(a, b, config: configAB);
    connectDirected(b, a, config: configBA ?? configAB);
  }

  /// Returns neighbors (directed). Empty if none or unknown.
  Set<TransportPeerAddress> neighborsOf(TransportPeerAddress address) {
    return _adjacency[address] ?? <TransportPeerAddress>{};
  }

  /// Returns the registered TransportPeer for the given address if exists.
  TransportPeer? peerFor(TransportPeerAddress address) {
    final t = _registry[address];
    return t?.self;
  }

  /// Internal stream for digest responses addressed to [to].
  Stream<MapEntry<TransportPeerAddress, GossipDigestResponse>>
  _onDigestResponseFor(TransportPeerAddress to) {
    final ctrl = _digestResponseStreams.putIfAbsent(
      to,
      () =>
          StreamController<
            MapEntry<TransportPeerAddress, GossipDigestResponse>
          >.broadcast(),
    );
    return ctrl.stream;
  }

  /// Deliver a digest to a destination peer (one-way).
  Future<void> deliverDigest({
    required TransportPeerAddress from,
    required TransportPeerAddress to,
    required IncomingDigest message,
  }) async {
    final link = _link(from, to);
    if (link == null) return;

    // Possible drop
    if (link.shouldDrop(rng)) return;

    final latency = link.sampleLatency(rng);
    await Future.delayed(latency);

    final dest = _registry[to];
    if (dest != null) {
      dest._emitIncomingDigest(message);
      // Possible duplication
      if (link.shouldDuplicate(rng)) {
        final dupLatency = link.sampleLatency(rng);
        await Future.delayed(dupLatency);
        dest._emitIncomingDigest(message);
      }
    }
  }

  /// Deliver digest response back to requester.
  Future<void> deliverDigestResponse({
    required TransportPeerAddress from,
    required TransportPeerAddress to,
    required GossipDigestResponse response,
  }) async {
    final link = _link(from, to);
    if (link == null) return;

    if (link.shouldDrop(rng)) return;

    final latency = link.sampleLatency(rng);
    await Future.delayed(latency);

    final ctrl = _digestResponseStreams[to];
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(MapEntry(from, response));
      if (link.shouldDuplicate(rng)) {
        final dupLatency = link.sampleLatency(rng);
        await Future.delayed(dupLatency);
        if (!ctrl.isClosed) {
          ctrl.add(MapEntry(from, response));
        }
      }
    }
  }

  /// Deliver final event messages to the destination peer.
  Future<void> deliverEvents({
    required TransportPeerAddress from,
    required TransportPeerAddress to,
    required IncomingEvents message,
  }) async {
    final link = _link(from, to);
    if (link == null) return;

    if (link.shouldDrop(rng)) return;

    final latency = link.sampleLatency(rng);
    await Future.delayed(latency);

    final dest = _registry[to];
    if (dest != null) {
      dest._emitIncomingEvents(message);
      if (link.shouldDuplicate(rng)) {
        final dupLatency = link.sampleLatency(rng);
        await Future.delayed(dupLatency);
        dest._emitIncomingEvents(message);
      }
    }
  }

  SimulatedLinkConfig? _link(
    TransportPeerAddress from,
    TransportPeerAddress to,
  ) {
    return _links[from]?[to];
  }

  /// Returns true if a directed link exists from [from] to [to].
  bool isLinked(TransportPeerAddress from, TransportPeerAddress to) {
    return _links[from]?.containsKey(to) ?? false;
  }

  /// Disconnects a directed link from [from] to [to], if present.
  void disconnectDirected(TransportPeerAddress from, TransportPeerAddress to) {
    final neigh = _adjacency[from];
    neigh?.remove(to);
    final linkMap = _links[from];
    linkMap?.remove(to);

    if (linkMap != null && linkMap.isEmpty) {
      _links.remove(from);
    }
    if (neigh != null && neigh.isEmpty) {
      _adjacency.remove(from);
    }
  }

  /// Disconnects an undirected link between [a] and [b] (both directions).
  void disconnectUndirected(TransportPeerAddress a, TransportPeerAddress b) {
    disconnectDirected(a, b);
    disconnectDirected(b, a);
  }

  /// Removes all links (both outgoing and incoming) associated with [address].
  ///
  /// Useful for simulating node isolation or partitions.
  void clearLinksFor(TransportPeerAddress address) {
    // Remove outgoing adjacency and link maps
    _adjacency.remove(address);
    _links.remove(address);

    // Remove incoming references from other nodes
    for (final neighbors in _adjacency.values) {
      neighbors.remove(address);
    }
    for (final linkMap in _links.values) {
      linkMap.remove(address);
    }
  }

  /// Adds an undirected "bridge" between two nodes (both directions).
  ///
  /// This is a convenience wrapper around [connectUndirected] for scenarios
  /// like partition healing where a single link reconnects two components.
  void addBridge(
    TransportPeerAddress a,
    TransportPeerAddress b, {
    SimulatedLinkConfig configAB = const SimulatedLinkConfig(),
    SimulatedLinkConfig? configBA,
  }) {
    connectUndirected(a, b, configAB: configAB, configBA: configBA);
  }

  /// Removes an undirected "bridge" between two nodes (both directions).
  void removeBridge(TransportPeerAddress a, TransportPeerAddress b) {
    disconnectUndirected(a, b);
  }
}

/// Utility to create a TransportPeerAddress from a string.
TransportPeerAddress addr(String value) => TransportPeerAddress(value);

/// Helper to instantiate a [SimulatedTransport] for a node and register it.
///
/// Example:
///   final net = SimulatedNetwork(seed: 42);
///   final tA = simulatedTransport(net, 'nodeA');
///   final tB = simulatedTransport(net, 'nodeB');
///   net.connectUndirected(tA.self.address, tB.self.address);
SimulatedTransport simulatedTransport(
  SimulatedNetwork network,
  String addressValue, {
  String? displayName,
  Map<String, dynamic> metadata = const {},
}) {
  return SimulatedTransport(
    network: network,
    address: TransportPeerAddress(addressValue),
    displayName: displayName ?? addressValue,
    metadata: metadata,
  );
}
