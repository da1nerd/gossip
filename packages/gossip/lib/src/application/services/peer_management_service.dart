/// Service for managing peer lifecycle and discovery.
///
/// This service handles adding, removing, and discovering peers in the
/// gossip network. In the new design, transport-discovered peers are
/// tracked as "ConnectedPeers" (address-keyed, reliability/liveness),
/// while identity is tracked separately as "IdentifiedNodes"
/// (GossipNodeID-keyed).
///
/// This layer will evolve to:
/// - upsert ConnectedPeers on discovery (no temporary IDs)
/// - select/gossip using ConnectedPeers
/// - promote/link ConnectedPeers to IdentifiedNodes when a real node ID
///   is learned from digests/events
library;

import 'dart:async';

import '../../gossip_node_id.dart';
import '../../gossip_peer.dart';
import '../../gossip_transport.dart';

import '../ports/connected_peer_repository.dart';
import '../ports/identified_node_repository.dart';

import '../../domain/entities/connected_peer.dart';
import '../../domain/entities/identified_node.dart';

/// Service for managing peer lifecycle and discovery.
class PeerManagementService {
  final GossipTransport transport;
  final ConnectedPeerRepository connectedPeerRepository;
  final IdentifiedNodeRepository identifiedNodeRepository;

  PeerManagementService({
    required this.transport,
    required this.connectedPeerRepository,
    required this.identifiedNodeRepository,
  });

  // Peer lifecycle streams (identity + best transport address)
  final StreamController<GossipPeer> _peerAddedCtrl =
      StreamController<GossipPeer>.broadcast();
  final StreamController<GossipPeer> _peerRemovedCtrl =
      StreamController<GossipPeer>.broadcast();

  Stream<GossipPeer> get peerAdded => _peerAddedCtrl.stream;
  Stream<GossipPeer> get peerRemoved => _peerRemovedCtrl.stream;

  // Track active transport-address count per identified node
  final Map<GossipNodeID, int> _activeAddressCount = {};

  // Subscriptions to repository streams
  final List<StreamSubscription> _subs = [];

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    // Seed active-state for currently known identified nodes and emit if active
    final nodes = await identifiedNodeRepository.getAllNodes();
    for (final n in nodes) {
      final count = await _computeActiveCount(n.id);
      _activeAddressCount[n.id] = count;
      if (count > 0) {
        await _emitAdded(n);
      }
    }

    // Subscribe to identity-level changes
    _subs.add(identifiedNodeRepository.onNodeAdded.listen(_onNodeAdded));
    _subs.add(identifiedNodeRepository.onNodeUpdated.listen(_onNodeUpdated));
    _subs.add(identifiedNodeRepository.onNodeRemoved.listen(_onNodeRemoved));

    // Subscribe to transport-level connected peer changes
    _subs.add(
      connectedPeerRepository.onPeerAdded.listen(_onConnectedPeerChanged),
    );
    _subs.add(
      connectedPeerRepository.onPeerUpdated.listen(_onConnectedPeerChanged),
    );
    _subs.add(
      connectedPeerRepository.onPeerRemoved.listen(_onConnectedPeerRemoved),
    );

    _initialized = true;
  }

  Future<void> shutdown() async {
    if (!_initialized) return;

    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();

    await _peerAddedCtrl.close();
    await _peerRemovedCtrl.close();

    _activeAddressCount.clear();
    _initialized = false;
  }

  // Handlers for identified node repository

  Future<void> _onNodeAdded(IdentifiedNode node) async {
    final wasActive = _isActive(node.id);
    final after = await _computeActiveCount(node.id);
    _activeAddressCount[node.id] = after;
    if (!wasActive && after > 0) {
      await _emitAdded(node);
    }
  }

  Future<void> _onNodeUpdated(IdentifiedNode node) async {
    final wasActive = _isActive(node.id);
    final after = await _computeActiveCount(node.id);
    _activeAddressCount[node.id] = after;

    if (!wasActive && after > 0) {
      await _emitAdded(node);
    } else if (wasActive && after == 0) {
      await _emitRemoved(node);
    }
  }

  Future<void> _onNodeRemoved(IdentifiedNode node) async {
    if (_isActive(node.id)) {
      await _emitRemoved(node);
    }
    _activeAddressCount.remove(node.id);
  }

  // Handlers for connected peer repository

  Future<void> _onConnectedPeerChanged(ConnectedPeer cp) async {
    final node = await identifiedNodeRepository.findByAddress(cp.address);
    if (node == null) return;

    final wasActive = _isActive(node.id);
    final after = await _computeActiveCount(node.id);
    _activeAddressCount[node.id] = after;

    if (!wasActive && after > 0) {
      await _emitAdded(node);
    } else if (wasActive && after == 0) {
      await _emitRemoved(node);
    }
  }

  Future<void> _onConnectedPeerRemoved(ConnectedPeer cp) async {
    final node = await identifiedNodeRepository.findByAddress(cp.address);
    if (node == null) return;

    final wasActive = _isActive(node.id);
    final after = await _computeActiveCount(node.id);
    _activeAddressCount[node.id] = after;

    if (wasActive && after == 0) {
      await _emitRemoved(node);
    }
  }

  // Helpers

  bool _isActive(GossipNodeID id) => (_activeAddressCount[id] ?? 0) > 0;

  Future<int> _computeActiveCount(GossipNodeID id) async {
    final node = await identifiedNodeRepository.getById(id);
    if (node == null) return 0;

    var count = 0;
    for (final addr in node.addresses) {
      final cp = await connectedPeerRepository.getByAddress(addr);
      if (cp?.isActive == true) count++;
    }
    return count;
  }

  Future<GossipPeer> _buildGossipPeer(IdentifiedNode node) async {
    TransportPeerAddress? selected = node.addresses.isNotEmpty
        ? node.addresses.first
        : null;
    DateTime? bestLastContact;
    bool isActive = false;

    for (final addr in node.addresses) {
      final cp = await connectedPeerRepository.getByAddress(addr);
      final last = cp?.lastContactTime;
      if (cp?.isActive == true) isActive = true;

      if (last != null &&
          (bestLastContact == null || last.isAfter(bestLastContact))) {
        selected = addr;
        bestLastContact = last;
      }
    }

    return GossipPeer(
      id: node.id,
      address: selected ?? TransportPeerAddress('unknown'),
      metadata: node.metadata,
      lastContactTime: bestLastContact,
      isActive: isActive,
    );
  }

  Future<void> _emitAdded(IdentifiedNode node) async {
    if (_peerAddedCtrl.isClosed) return;
    final peer = await _buildGossipPeer(node);
    _peerAddedCtrl.add(peer);
  }

  Future<void> _emitRemoved(IdentifiedNode node) async {
    if (_peerRemovedCtrl.isClosed) return;
    final peer = await _buildGossipPeer(node);
    _peerRemovedCtrl.add(peer);
  }

  Future<List<GossipPeer>> listPeers() async {
    final nodes = await identifiedNodeRepository.getAllNodes();
    final peers = <GossipPeer>[];
    for (final n in nodes) {
      if (n.addresses.isEmpty) continue;
      peers.add(await _buildGossipPeer(n));
    }
    return peers;
  }

  /// Discover new peers using the transport layer.
  ///
  /// This method queries the transport for available peers and (in the
  /// ConnectedPeer/IdentifiedNode design) should upsert them into a
  /// ConnectedPeerRepository keyed by address, without creating any
  /// temporary GossipNodeIDs. Identity will be linked later once learned.
  Future<void> discoverPeers() async {
    try {
      final discoveredPeers = await transport.discoverPeers();

      for (final transportPeer in discoveredPeers) {
        // Upsert connected peers by address (no temporary GossipNodeIDs).
        await connectedPeerRepository.upsertFromTransport(transportPeer);
      }
    } catch (e) {
      // Peer discovery failures should not crash the node
      // Log the error but continue operating
    }
  }

  /// Update or insert a connected peer from the latest transport snapshot.
  ///
  /// This keeps transport-derived liveness/metadata fresh without relying on
  /// any legacy ID-based repositories.
  Future<void> updatePeerFromTransport(TransportPeer transportPeer) async {
    await connectedPeerRepository.upsertFromTransport(transportPeer);
  }

  /// Promote a connected peer (by address) to an identified node (by id).
  ///
  /// Links the transport address to the provided GossipNodeID via the
  /// IdentifiedNodeRepository. Repository policy determines whether a new
  /// node is created or an existing one is updated.
  Future<void> promote(
    TransportPeerAddress address,
    GossipNodeID nodeId,
  ) async {
    await identifiedNodeRepository.linkAddress(nodeId, address);
  }
}
