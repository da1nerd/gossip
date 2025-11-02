library;

import '../../gossip_node_id.dart';
import '../../gossip_transport.dart';
import '../../domain/entities/identified_node.dart';

/// Port for identity-level persistence of gossip nodes.
///
/// This repository manages nodes keyed by their `GossipNodeID` and tracks
/// associated transport addresses that can be used to contact the node.
/// It intentionally does not deal with transport-level liveness/reliability
/// (that belongs to a separate ConnectedPeerRepository).
///
/// Typical lifecycle:
/// 1) A peer is discovered at the transport layer as a ConnectedPeer
/// 2) During a digest/event exchange, we learn the real `GossipNodeID`
/// 3) We create or link an `IdentifiedNode` for that ID and associate
///    one or more transport addresses
abstract class IdentifiedNodeRepository {
  /// Returns a node by its gossip identity, or null if not found.
  Future<IdentifiedNode?> getById(GossipNodeID id);

  /// Returns all identified nodes currently known.
  Future<List<IdentifiedNode>> getAllNodes();

  /// Attempts to find an identified node that is associated with [address].
  ///
  /// Implementations may index addresses to avoid O(n) scans.
  /// Returns null if no identified node currently claims the address.
  Future<IdentifiedNode?> findByAddress(TransportPeerAddress address);

  /// Saves (inserts or updates) an identified node.
  ///
  /// Implementations should emit the appropriate stream event (added/updated).
  Future<void> save(IdentifiedNode node);

  /// Removes a node by its identity.
  ///
  /// Implementations should emit the `onNodeRemoved` stream if the node existed.
  Future<void> remove(GossipNodeID id);

  /// Links a transport address to an identified node.
  ///
  /// - If the node does not exist, implementations may either throw or create a
  ///   new node with the given address (document behavior).
  /// - If the address is already linked to a different node, implementations
  ///   should resolve the conflict (e.g., reject, reassign, or log), and
  ///   document the chosen policy.
  Future<void> linkAddress(GossipNodeID id, TransportPeerAddress address);

  /// Unlinks a transport address from an identified node.
  ///
  /// No-op if the node or the address association does not exist.
  Future<void> unlinkAddress(GossipNodeID id, TransportPeerAddress address);

  /// Merges metadata into the identified node's metadata map.
  ///
  /// Source values take precedence for conflicting keys.
  /// No-op if the node does not exist (implementations may also choose to throw).
  Future<void> mergeMetadata(GossipNodeID id, Map<String, dynamic> metadata);

  /// Stream of nodes that have been added to the repository.
  Stream<IdentifiedNode> get onNodeAdded;

  /// Stream of nodes that have been updated in the repository.
  Stream<IdentifiedNode> get onNodeUpdated;

  /// Stream of nodes that have been removed from the repository.
  Stream<IdentifiedNode> get onNodeRemoved;
}
