library;

import 'dart:async';

import 'package:gossip/src/application/ports/connected_peer_repository.dart';
import 'package:gossip/src/domain/entities/connected_peer.dart';
import 'package:gossip/src/transport.dart';

/// In-memory implementation of [ConnectedPeerRepository].
///
/// This repository stores [ConnectedPeer]s keyed by their [TransportPeerAddress]
/// and exposes simple CRUD operations plus broadcast streams for add/update/remove
/// events. It is suitable for tests, development, and small deployments.
///
/// Notes:
/// - This class is not intended to be used concurrently across isolates.
/// - All operations are synchronous aside from the interface's Future contract.
/// - Stream controllers are broadcast and guarded against add-after-close.
class InMemoryConnectedPeerRepository implements ConnectedPeerRepository {
  final Map<TransportPeerAddress, ConnectedPeer> _peers = {};

  final StreamController<ConnectedPeer> _addedCtrl =
      StreamController<ConnectedPeer>.broadcast();
  final StreamController<ConnectedPeer> _updatedCtrl =
      StreamController<ConnectedPeer>.broadcast();
  final StreamController<ConnectedPeer> _removedCtrl =
      StreamController<ConnectedPeer>.broadcast();

  bool _disposed = false;

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('InMemoryConnectedPeerRepository has been disposed');
    }
  }

  @override
  Future<List<ConnectedPeer>> getAllConnectedPeers() async {
    _checkNotDisposed();
    return _peers.values.toList(growable: false);
  }

  @override
  Future<List<ConnectedPeer>> getActiveConnectedPeers() async {
    _checkNotDisposed();
    return _peers.values.where((p) => p.isActive).toList(growable: false);
  }

  @override
  Future<ConnectedPeer?> getByAddress(TransportPeerAddress address) async {
    _checkNotDisposed();
    return _peers[address];
  }

  @override
  Future<ConnectedPeer> upsertFromTransport(TransportPeer transportPeer) async {
    _checkNotDisposed();

    final existing = _peers[transportPeer.address];
    if (existing != null) {
      // Merge transport attributes into the existing peer
      existing.updateFromTransport(transportPeer);
      // Persist and notify
      _peers[transportPeer.address] = existing;
      if (!_updatedCtrl.isClosed) _updatedCtrl.add(existing);
      return existing;
    }

    // Create a new ConnectedPeer seeded from the transport peer
    final created = ConnectedPeer(
      address: transportPeer.address,
      metadata: Map<String, dynamic>.from(transportPeer.metadata),
      lastContactTime: transportPeer.connectedAt,
      isActive: transportPeer.isActive,
    )..updateFromTransport(transportPeer);

    _peers[transportPeer.address] = created;
    if (!_addedCtrl.isClosed) _addedCtrl.add(created);
    return created;
  }

  @override
  Future<void> save(ConnectedPeer peer) async {
    _checkNotDisposed();
    final existed = _peers.containsKey(peer.address);
    _peers[peer.address] = peer;

    if (existed) {
      if (!_updatedCtrl.isClosed) _updatedCtrl.add(peer);
    } else {
      if (!_addedCtrl.isClosed) _addedCtrl.add(peer);
    }
  }

  @override
  Future<void> removeByAddress(TransportPeerAddress address) async {
    _checkNotDisposed();
    final removed = _peers.remove(address);
    if (removed != null && !_removedCtrl.isClosed) {
      _removedCtrl.add(removed);
    }
  }

  @override
  Stream<ConnectedPeer> get onPeerAdded => _addedCtrl.stream;

  @override
  Stream<ConnectedPeer> get onPeerUpdated => _updatedCtrl.stream;

  @override
  Stream<ConnectedPeer> get onPeerRemoved => _removedCtrl.stream;

  /// Disposes this repository and closes its streams.
  ///
  /// After disposal, any method call will throw [StateError].
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await _addedCtrl.close();
    await _updatedCtrl.close();
    await _removedCtrl.close();

    _peers.clear();
  }

  /// For test/debug: current count of peers.
  int get count => _peers.length;

  /// For test/debug: clears all peers and emits removal events.
  Future<void> clear() async {
    _checkNotDisposed();
    final addresses = _peers.keys.toList(growable: false);
    for (final addr in addresses) {
      await removeByAddress(addr);
    }
  }
}
