/// Service for managing peer lifecycle and discovery.
///
/// This service handles adding, removing, and discovering peers in the
/// gossip network. It coordinates between the transport layer and the
/// peer repository.
library;

import '../../gossip_node_id.dart';
import '../../transport.dart';
import '../ports/peer_repository.dart';
import '../../domain/entities/internal_gossip_peer.dart';

/// Service for managing peer lifecycle and discovery.
class PeerManagementService {
  final PeerRepository peerRepository;
  final GossipTransport transport;

  PeerManagementService({
    required this.peerRepository,
    required this.transport,
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
  /// This method queries the transport for available peers and adds
  /// any new ones to the repository.
  Future<void> discoverPeers() async {
    try {
      final discoveredPeers = await transport.discoverPeers();

      for (final transportPeer in discoveredPeers) {
        // For now, we'll use the transport address as a temporary nodeId
        // This is a limitation - in a real implementation, we'd need a way
        // to discover the actual gossip node ID from the transport peer
        final tempNodeId = GossipNodeID(
          'transport_${transportPeer.address.value}',
        );

        // Check if we already know about this peer by address
        final allPeers = await peerRepository.getAllPeers();
        final existingPeer = allPeers
            .where((p) => p.address == transportPeer.address)
            .firstOrNull;

        if (existingPeer == null) {
          // Add new peer with temporary node ID
          await addPeer(tempNodeId, transportPeer.address);
        } else {
          // Update existing peer information if needed
          await _updatePeerFromTransport(existingPeer, transportPeer);
        }
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
}
