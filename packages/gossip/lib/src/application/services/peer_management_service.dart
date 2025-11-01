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

import '../../gossip_node_id.dart';
import '../../transport.dart';
import '../ports/peer_repository.dart';
import '../ports/connected_peer_repository.dart';
import '../../domain/entities/internal_gossip_peer.dart';

/// Service for managing peer lifecycle and discovery.
class PeerManagementService {
  final PeerRepository peerRepository;
  final GossipTransport transport;
  final ConnectedPeerRepository connectedPeerRepository;

  PeerManagementService({
    required this.peerRepository,
    required this.transport,
    required this.connectedPeerRepository,
  });

  /// Add a new peer to the gossip network.
  ///
  /// Creates an [InternalGossipPeer] and stores it in the repository.
  Future<void> addPeer(
    GossipNodeID nodeId,
    TransportPeerAddress address,
  ) async {
    final peer = InternalGossipPeer(nodeId: nodeId, address: address);
    await peerRepository.savePeer(peer);
  }

  /// Remove a peer from the gossip network.
  Future<void> removePeer(GossipNodeID nodeId) async {
    await peerRepository.removePeer(nodeId);
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

  /// Update an existing peer with information from the transport layer.
  Future<void> _updatePeerFromTransport(
    InternalGossipPeer existingPeer,
    TransportPeer transportPeer,
  ) async {
    // Create updated peer with new transport information
    final updatedPeer = InternalGossipPeer(
      nodeId: existingPeer.nodeId,
      address: transportPeer.address,
      metadata: {
        ...existingPeer.metadata,
        'displayName': transportPeer.displayName,
        'transportId': transportPeer.address.value,
        ...transportPeer.metadata,
      },
      lastContactTime: existingPeer.lastContactTime,
      isActive: transportPeer.isActive,
    );

    await peerRepository.savePeer(updatedPeer);
  }

  /// Update peer status based on transport peer information.
  ///
  /// This is used when the transport layer provides updates about
  /// peer connectivity status.
  Future<void> updatePeerFromTransport(TransportPeer transportPeer) async {
    // Find existing peer by address since TransportPeer doesn't have nodeId
    final allPeers = await peerRepository.getAllPeers();
    final existing = allPeers
        .where((p) => p.address == transportPeer.address)
        .firstOrNull;

    if (existing != null) {
      await _updatePeerFromTransport(existing, transportPeer);
    }
  }

  /// Promote a connected peer (by address) to an identified node (by id).
  /// Placeholder for identity promotion plumbing; links will be implemented where appropriate.
  Future<void> promote(
    TransportPeerAddress address,
    GossipNodeID nodeId,
  ) async {
    // TODO: Implement linking to IdentifiedNodeRepository and merging metadata/addresses.
    // For now, ensure the connected peer exists.
    await connectedPeerRepository.getByAddress(address);
  }
}
