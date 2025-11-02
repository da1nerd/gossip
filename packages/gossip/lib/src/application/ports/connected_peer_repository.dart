library;

import '../../transport.dart';
import '../../domain/entities/connected_peer.dart';

/// Port for managing transport-level peers that may not yet have a known
/// gossip node identity (`GossipNodeID`).
///
/// This repository allows the application to:
/// - Persist peers discovered by the transport (by address)
/// - Track and update liveness/reliability state for selection
/// - Promote or link to identified nodes later without using temporary IDs
///
/// Typical lifecycle:
/// 1) Transport discovers a peer -> upsert as `ConnectedPeer` (by address)
/// 2) Gossip selection chooses among connected peers
/// 3) On digest/events with a real node ID -> separate promotion/association step
abstract class ConnectedPeerRepository {
  /// Returns all connected peers currently known, regardless of active state.
  Future<List<ConnectedPeer>> getAllConnectedPeers();

  /// Returns only connected peers considered active.
  ///
  /// Implementations may define "active" based on transport signals or
  /// recent liveness checks.
  Future<List<ConnectedPeer>> getActiveConnectedPeers();

  /// Finds a connected peer by its transport address.
  Future<ConnectedPeer?> getByAddress(TransportPeerAddress address);

  /// Creates or updates a connected peer entry from a transport peer snapshot.
  ///
  /// - If a peer with [transportPeer.address] exists, merges transport fields
  ///   (e.g., isActive, displayName, metadata) and returns the updated entity.
  /// - Otherwise, creates a new `ConnectedPeer` with default reliability state.
  Future<ConnectedPeer> upsertFromTransport(TransportPeer transportPeer);

  /// Saves a connected peer with any modified fields (e.g., reliability/liveness).
  ///
  /// Call this after `recordSuccessfulContact()` or `recordFailedContact()`
  /// to persist the updated reliability state.
  Future<void> save(ConnectedPeer peer);

  /// Removes a connected peer by its address.
  ///
  /// Useful for churn and cleanup scenarios when a peer is no longer relevant.
  Future<void> removeByAddress(TransportPeerAddress address);

  /// Stream of connected peers added to the repository.
  Stream<ConnectedPeer> get onPeerAdded;

  /// Stream of connected peers updated in the repository.
  Stream<ConnectedPeer> get onPeerUpdated;

  /// Stream of connected peers removed from the repository.
  Stream<ConnectedPeer> get onPeerRemoved;

  /// Disposes any resources held by the repository.
  Future<void> dispose();
}
