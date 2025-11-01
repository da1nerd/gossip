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

import '../ports/connected_peer_repository.dart';
import '../ports/identified_node_repository.dart';

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
