library;

import 'dart:async';

import 'package:gossip/src/application/ports/identified_node_repository.dart';
import 'package:gossip/src/domain/entities/identified_node.dart';
import 'package:gossip/src/gossip_node_id.dart';
import 'package:gossip/src/transport.dart';

/// In-memory implementation of [IdentifiedNodeRepository].
///
/// Features:
/// - Stores nodes keyed by GossipNodeID
/// - Maintains a reverse index from TransportPeerAddress -> GossipNodeID
///   for fast lookups and address linking/unlinking
/// - Broadcasts add/update/remove events
///
/// Notes:
/// - Operations are synchronous under the async API for simplicity
/// - Not intended for cross-isolate concurrency
/// - Policy on linkAddress conflicts: reassign the address to the provided node
///   (if it was linked to a different node, it gets unlinked from the old one)
class InMemoryIdentifiedNodeRepository implements IdentifiedNodeRepository {
  final Map<GossipNodeID, IdentifiedNode> _nodes = {};
  final Map<TransportPeerAddress, GossipNodeID> _addressIndex = {};

  final StreamController<IdentifiedNode> _addedCtrl =
      StreamController<IdentifiedNode>.broadcast();
  final StreamController<IdentifiedNode> _updatedCtrl =
      StreamController<IdentifiedNode>.broadcast();
  final StreamController<IdentifiedNode> _removedCtrl =
      StreamController<IdentifiedNode>.broadcast();

  bool _disposed = false;

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('InMemoryIdentifiedNodeRepository has been disposed');
    }
  }

  // --- IdentifiedNodeRepository implementation ---

  @override
  Future<IdentifiedNode?> getById(GossipNodeID id) async {
    _checkNotDisposed();
    return _nodes[id];
  }

  @override
  Future<List<IdentifiedNode>> getAllNodes() async {
    _checkNotDisposed();
    // Return a snapshot copy
    return List<IdentifiedNode>.unmodifiable(_nodes.values.toList());
  }

  @override
  Future<IdentifiedNode?> findByAddress(TransportPeerAddress address) async {
    _checkNotDisposed();
    final id = _addressIndex[address];
    if (id == null) return null;
    return _nodes[id];
  }

  @override
  Future<void> save(IdentifiedNode node) async {
    _checkNotDisposed();

    final existing = _nodes[node.id];
    if (existing == null) {
      // Insert new node
      _nodes[node.id] = node;
      // Index addresses
      for (final a in node.addresses) {
        _indexAddress(a, node.id);
      }
      _emitAdded(node);
      return;
    }

    // Update node:
    // - Determine address delta to maintain reverse index
    final oldAddrs = existing.addresses.toSet();
    final newAddrs = node.addresses.toSet();

    final toRemove = oldAddrs.difference(newAddrs);
    final toAdd = newAddrs.difference(oldAddrs);

    for (final a in toRemove) {
      _unindexAddress(a, expectedId: existing.id);
    }
    for (final a in toAdd) {
      _indexAddress(a, node.id);
    }

    _nodes[node.id] = node;
    _emitUpdated(node);
  }

  @override
  Future<void> remove(GossipNodeID id) async {
    _checkNotDisposed();
    final removed = _nodes.remove(id);
    if (removed == null) return;

    // Clean reverse index entries
    for (final addr in removed.addresses) {
      _unindexAddress(addr, expectedId: id);
    }

    _emitRemoved(removed);
  }

  @override
  Future<void> linkAddress(
    GossipNodeID id,
    TransportPeerAddress address,
  ) async {
    _checkNotDisposed();

    // Reassign policy:
    // If the address is already linked to a different node, unlink it there first.
    final currentOwner = _addressIndex[address];
    if (currentOwner != null && currentOwner != id) {
      final ownerNode = _nodes[currentOwner];
      if (ownerNode != null) {
        final updated = ownerNode.copyWith(
          addresses: ownerNode.addresses.where((a) => a != address).toList(),
        );
        _nodes[currentOwner] = updated;
        _emitUpdated(updated);
      }
      _addressIndex.remove(address);
    }

    // Ensure target node exists (create new node with just this address if missing)
    final node =
        _nodes[id] ??
        IdentifiedNode(
          id: id,
          addresses: <TransportPeerAddress>[],
          metadata: {},
        );

    if (!node.addresses.contains(address)) {
      final updated = node.copyWith(addresses: [...node.addresses, address]);
      _nodes[id] = updated;
      _indexAddress(address, id);

      // Emit appropriate event (added if it was created)
      if (node.addresses.isEmpty &&
          node.metadata.isEmpty &&
          !_nodes.containsKey(id)) {
        _emitAdded(updated);
      } else {
        _emitUpdated(updated);
      }
    } else {
      // Address already present, ensure index exists
      _indexAddress(address, id);
      // No-op update event
    }
  }

  @override
  Future<void> unlinkAddress(
    GossipNodeID id,
    TransportPeerAddress address,
  ) async {
    _checkNotDisposed();
    final node = _nodes[id];
    if (node == null) return;

    if (!node.addresses.contains(address)) return;

    final updated = node.copyWith(
      addresses: node.addresses.where((a) => a != address).toList(),
    );
    _nodes[id] = updated;
    _unindexAddress(address, expectedId: id);
    _emitUpdated(updated);
  }

  @override
  Future<void> mergeMetadata(
    GossipNodeID id,
    Map<String, dynamic> metadata,
  ) async {
    _checkNotDisposed();
    final node = _nodes[id];
    if (node == null) return;
    final merged = node.copyWith(metadata: {...node.metadata, ...metadata});
    _nodes[id] = merged;
    _emitUpdated(merged);
  }

  @override
  Stream<IdentifiedNode> get onNodeAdded => _addedCtrl.stream;

  @override
  Stream<IdentifiedNode> get onNodeUpdated => _updatedCtrl.stream;

  @override
  Stream<IdentifiedNode> get onNodeRemoved => _removedCtrl.stream;

  // --- Helpers ---

  void _indexAddress(TransportPeerAddress address, GossipNodeID id) {
    _addressIndex[address] = id;
  }

  void _unindexAddress(
    TransportPeerAddress address, {
    required GossipNodeID expectedId,
  }) {
    final current = _addressIndex[address];
    if (current == expectedId) {
      _addressIndex.remove(address);
    }
  }

  void _emitAdded(IdentifiedNode node) {
    if (!_addedCtrl.isClosed) _addedCtrl.add(node);
  }

  void _emitUpdated(IdentifiedNode node) {
    if (!_updatedCtrl.isClosed) _updatedCtrl.add(node);
  }

  void _emitRemoved(IdentifiedNode node) {
    if (!_removedCtrl.isClosed) _removedCtrl.add(node);
  }

  /// Disposes this repository and closes its streams.
  ///
  /// After disposal, any method call will throw [StateError].
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _addedCtrl.close();
    await _updatedCtrl.close();
    await _removedCtrl.close();
    _nodes.clear();
    _addressIndex.clear();
  }
}
