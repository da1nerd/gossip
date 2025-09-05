/// Extension to add CRDT capabilities to existing GossipNode instances.
///
/// This module provides a convenient extension method that allows any existing
/// GossipNode to be enhanced with CRDT functionality without modifying the
/// original gossip protocol library.
library;

import 'package:gossip/gossip.dart';

import '../crdt_manager.dart';
import '../crdt_store.dart';
import '../crdts/crdt.dart';

/// Extension to add CRDT capabilities to existing GossipNode instances.
///
/// This extension provides a seamless way to add CRDT support to any GossipNode
/// without requiring changes to the core gossip protocol library. The extension
/// creates and manages a CRDTManager that coordinates CRDT operations with the
/// gossip protocol.
///
/// ## Usage
///
/// ```dart
/// import 'package:gossip/gossip.dart';
/// import 'package:gossip_crdts/gossip_crdts.dart';
///
/// final node = GossipNode(
///   config: GossipConfig(nodeId: 'node1'),
///   eventStore: MemoryEventStore(),
///   transport: MyTransport(),
/// );
///
/// await node.start();
///
/// // Enable CRDT support
/// final crdtManager = await node.enableCRDTSupport();
///
/// // Register and use CRDTs
/// final counter = GCounter('shared-counter');
/// await crdtManager.register(counter);
/// await crdtManager.performOperation('shared-counter', 'increment', {'amount': 5});
/// ```
extension GossipNodeCRDTExtension on GossipNode {
  /// Enable CRDT support for this gossip node.
  ///
  /// This method sets up CRDT functionality by creating a CRDTManager that
  /// coordinates with the gossip protocol for operation broadcasting and
  /// state synchronization.
  ///
  /// Parameters:
  /// - [crdtStore]: Optional custom storage backend. If not provided,
  ///   uses an in-memory store (suitable for testing/development)
  ///
  /// Returns a [CRDTManager] that can be used to register and manage CRDTs.
  ///
  /// Throws [CRDTException] if CRDT support cannot be enabled.
  ///
  /// ## Example
  ///
  /// ```dart
  /// // Basic usage with default memory storage
  /// final crdtManager = await node.enableCRDTSupport();
  ///
  /// // With custom storage
  /// final customStore = MyCRDTStore();
  /// final crdtManager = await node.enableCRDTSupport(crdtStore: customStore);
  /// ```
  Future<CRDTManager> enableCRDTSupport({CRDTStore? crdtStore}) async {
    final store = crdtStore ?? MemoryCRDTStore();
    final manager = CRDTManager(this, store);

    await manager.initialize();

    return manager;
  }

  /// Create a CRDT-enabled version of this gossip node.
  ///
  /// This is an alternative to [enableCRDTSupport] that returns a wrapper
  /// object that combines the original gossip node with CRDT management
  /// capabilities.
  ///
  /// Parameters:
  /// - [crdtStore]: Optional custom storage backend
  ///
  /// Returns a [CRDTEnabledGossipNode] that provides both gossip and CRDT
  /// functionality in a single interface.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final crdtNode = await node.withCRDTSupport();
  ///
  /// // Use gossip functionality
  /// await crdtNode.createEvent({'type': 'message', 'content': 'hello'});
  ///
  /// // Use CRDT functionality
  /// final counter = GCounter('my-counter');
  /// await crdtNode.registerCRDT(counter);
  /// await crdtNode.performCRDTOperation('my-counter', 'increment', {'amount': 1});
  /// ```
  Future<CRDTEnabledGossipNode> withCRDTSupport({CRDTStore? crdtStore}) async {
    final manager = await enableCRDTSupport(crdtStore: crdtStore);
    return CRDTEnabledGossipNode._(this, manager);
  }
}

/// A wrapper that combines GossipNode and CRDTManager functionality.
///
/// This class provides a unified interface for both gossip protocol operations
/// and CRDT management, making it easier to work with both systems together.
class CRDTEnabledGossipNode {
  final GossipNode _gossipNode;
  final CRDTManager _crdtManager;

  CRDTEnabledGossipNode._(this._gossipNode, this._crdtManager);

  /// Access to the underlying gossip node.
  GossipNode get gossipNode => _gossipNode;

  /// Access to the CRDT manager.
  CRDTManager get crdtManager => _crdtManager;

  // Delegate common gossip operations

  /// Create an event and broadcast it through the gossip protocol.
  Future<Event> createEvent(Map<String, dynamic> payload) =>
      _gossipNode.createEvent(payload);

  /// Start the gossip node.
  Future<void> start() => _gossipNode.start();

  /// Stop the gossip node.
  Future<void> stop() => _gossipNode.stop();

  /// Get the gossip node's configuration.
  GossipConfig get config => _gossipNode.config;

  /// Get the gossip node's current vector clock.
  VectorClock get vectorClock => _gossipNode.vectorClock;

  /// Stream of events created by this node.
  Stream<Event> get onEventCreated => _gossipNode.onEventCreated;

  /// Stream of events received from other nodes.
  Stream<ReceivedEvent> get onEventReceived => _gossipNode.onEventReceived;

  /// Stream of peers added to this node.
  Stream<GossipPeer> get onPeerAdded => _gossipNode.onPeerAdded;

  /// Stream of peers removed from this node.
  Stream<GossipPeer> get onPeerRemoved => _gossipNode.onPeerRemoved;

  /// Stream of gossip exchange results.
  Stream<GossipExchangeResult> get onGossipExchange =>
      _gossipNode.onGossipExchange;

  // Delegate CRDT operations with convenience methods

  /// Register a CRDT with the manager.
  Future<void> registerCRDT<T extends CRDT>(T crdt) =>
      _crdtManager.register(crdt);

  /// Unregister a CRDT from the manager.
  Future<bool> unregisterCRDT(String crdtId) => _crdtManager.unregister(crdtId);

  /// Get a CRDT by its ID.
  T? getCRDT<T extends CRDT>(String crdtId) => _crdtManager.getCRDT<T>(crdtId);

  /// Get all registered CRDT IDs.
  List<String> getCRDTIds() => _crdtManager.getCRDTIds();

  /// Get all registered CRDTs.
  List<CRDT> getAllCRDTs() => _crdtManager.getAllCRDTs();

  /// Perform a CRDT operation.
  Future<void> performCRDTOperation(
    String crdtId,
    String operation,
    Map<String, dynamic> data,
  ) => _crdtManager.performOperation(crdtId, operation, data);

  /// Synchronize CRDT state with a specific peer.
  Future<void> syncCRDTsWith(String peerId) => _crdtManager.syncWith(peerId);

  /// Force synchronization of all CRDTs.
  Future<void> forceCRDTSync() => _crdtManager.forceSync();

  /// Stream of CRDT update events.
  Stream<CRDTUpdateEvent> get onCRDTUpdate => _crdtManager.onUpdate;

  /// Stream of CRDT operation events.
  Stream<CRDTOperationEvent> get onCRDTOperation => _crdtManager.onOperation;

  /// Stream of CRDT synchronization events.
  Stream<CRDTSyncEvent> get onCRDTSync => _crdtManager.onSync;

  /// Get statistics about the CRDT manager.
  CRDTManagerStats getCRDTStats() => _crdtManager.getStats();

  /// Close both the gossip node and CRDT manager.
  Future<void> close() async {
    await _crdtManager.close();
    await _gossipNode.stop();
  }

  @override
  String toString() =>
      'CRDTEnabledGossipNode(nodeId: ${config.nodeId}, '
      'crdtCount: ${getCRDTIds().length})';
}
