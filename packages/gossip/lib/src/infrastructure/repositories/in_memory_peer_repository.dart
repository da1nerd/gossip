/// In-memory implementation of PeerRepository.
///
/// This provides a simple in-memory storage implementation for peers.
/// This can be easily replaced with persistent storage implementations
/// like file-based or database-backed storage.
library;

import 'dart:async';

import '../../gossip_node_id.dart';
import '../../domain/entities/internal_gossip_peer.dart';
import '../../application/ports/peer_repository.dart';

/// In-memory implementation of PeerRepository.
///
/// This can be easily replaced with persistent storage implementations.
class InMemoryPeerRepository implements PeerRepository {
  final Map<GossipNodeID, InternalGossipPeer> _peers = {};

  final StreamController<InternalGossipPeer> _peerAddedController =
      StreamController<InternalGossipPeer>.broadcast();
  final StreamController<InternalGossipPeer> _peerRemovedController =
      StreamController<InternalGossipPeer>.broadcast();
  final StreamController<InternalGossipPeer> _peerUpdatedController =
      StreamController<InternalGossipPeer>.broadcast();

  @override
  Future<List<InternalGossipPeer>> getAllPeers() async {
    return _peers.values.toList();
  }

  @override
  Future<InternalGossipPeer?> getPeerById(GossipNodeID id) async {
    return _peers[id];
  }

  @override
  Future<void> savePeer(InternalGossipPeer peer) async {
    final wasNew = !_peers.containsKey(peer.nodeId);
    _peers[peer.nodeId] = peer;

    if (wasNew) {
      if (!_peerAddedController.isClosed) {
        _peerAddedController.add(peer);
      }
    } else {
      if (!_peerUpdatedController.isClosed) {
        _peerUpdatedController.add(peer);
      }
    }
  }

  @override
  Future<void> removePeer(GossipNodeID id) async {
    final peer = _peers.remove(id);
    if (peer != null) {
      if (!_peerRemovedController.isClosed) {
        _peerRemovedController.add(peer);
      }
    }
  }

  @override
  Future<void> saveAllPeers(List<InternalGossipPeer> peers) async {
    for (final peer in peers) {
      await savePeer(peer);
    }
  }

  @override
  Stream<InternalGossipPeer> get peerAdded => _peerAddedController.stream;

  @override
  Stream<InternalGossipPeer> get peerRemoved => _peerRemovedController.stream;

  @override
  Stream<InternalGossipPeer> get peerUpdated => _peerUpdatedController.stream;

  /// Dispose of resources and close streams.
  ///
  /// This should be called when the repository is no longer needed.
  Future<void> dispose() async {
    await _peerAddedController.close();
    await _peerRemovedController.close();
    await _peerUpdatedController.close();
  }

  /// Get the number of peers currently stored.
  int get peerCount => _peers.length;

  /// Clear all peers from storage.
  ///
  /// This is useful for testing or resetting the repository.
  Future<void> clear() async {
    final peersToRemove = _peers.keys.toList();
    for (final nodeId in peersToRemove) {
      await removePeer(nodeId);
    }
  }
}
