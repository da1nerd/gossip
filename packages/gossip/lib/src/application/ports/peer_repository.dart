/// Repository interface for peer persistence.
///
/// This abstracts the storage concerns away from the domain logic.
/// Different implementations can provide in-memory, file-based, or
/// database-backed storage.
library;

import 'dart:async';

import '../../gossip_node_id.dart';
import '../../domain/entities/internal_gossip_peer.dart';

/// Repository interface for peer persistence.
///
/// This abstracts the storage concerns away from the domain logic.
abstract class PeerRepository {
  /// Get all peers from storage.
  Future<List<InternalGossipPeer>> getAllPeers();

  /// Get a specific peer by its node ID.
  Future<InternalGossipPeer?> getPeerById(GossipNodeID id);

  /// Save a peer to storage.
  ///
  /// If the peer already exists, it will be updated.
  /// If it doesn't exist, it will be added.
  Future<void> savePeer(InternalGossipPeer peer);

  /// Remove a peer from storage.
  Future<void> removePeer(GossipNodeID id);

  /// Save multiple peers at once.
  Future<void> saveAllPeers(List<InternalGossipPeer> peers);

  /// Stream of peers that have been added.
  Stream<InternalGossipPeer> get peerAdded;

  /// Stream of peers that have been removed.
  Stream<InternalGossipPeer> get peerRemoved;

  /// Stream of peers that have been updated.
  Stream<InternalGossipPeer> get peerUpdated;
}
