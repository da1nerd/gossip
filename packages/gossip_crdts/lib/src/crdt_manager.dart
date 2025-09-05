/// CRDT manager for coordinating CRDT operations with the gossip protocol.
///
/// This module provides the CRDTManager class that coordinates CRDT operations
/// with gossip nodes, handling synchronization, persistence, and operation
/// broadcasting across the distributed system.
library;

import 'dart:async';

import 'package:gossip/gossip.dart';

import 'crdt_store.dart';
import 'crdts/crdt.dart';

/// Manages CRDTs for a gossip node.
///
/// The CRDTManager coordinates between the gossip protocol and CRDT instances,
/// handling operation broadcasting, state synchronization, and persistence.
/// It ensures that CRDT operations are properly distributed across the network
/// and that all replicas eventually converge to the same state.
class CRDTManager {
  final GossipNode _gossipNode;
  final CRDTStore _store;
  final Map<String, CRDT> _crdts = {};
  final Map<String, StreamSubscription> _operationSubscriptions = {};

  // Stream controllers for CRDT events
  final StreamController<CRDTUpdateEvent> _updateController =
      StreamController<CRDTUpdateEvent>.broadcast();
  final StreamController<CRDTOperationEvent> _operationController =
      StreamController<CRDTOperationEvent>.broadcast();
  final StreamController<CRDTSyncEvent> _syncController =
      StreamController<CRDTSyncEvent>.broadcast();

  bool _isInitialized = false;
  bool _isClosed = false;

  /// Creates a new CRDT manager.
  ///
  /// Parameters:
  /// - [gossipNode]: The gossip node to coordinate with
  /// - [store]: The storage backend for CRDT persistence
  CRDTManager(this._gossipNode, this._store);

  /// Initialize the CRDT manager.
  ///
  /// This sets up event listeners and loads any previously saved CRDTs
  /// from storage. Must be called before using the manager.
  Future<void> initialize() async {
    if (_isInitialized) return;

    _checkNotClosed();

    // Set up gossip event listener for CRDT operations
    _operationSubscriptions['gossip'] = _gossipNode.onEventReceived.listen(
      (receivedEvent) => _handleGossipEvent(receivedEvent),
    );

    // Load existing CRDTs from storage
    await _loadCRDTsFromStorage();

    _isInitialized = true;
  }

  /// Register a CRDT with this manager.
  ///
  /// The CRDT will be managed by this instance, including persistence
  /// and synchronization with other nodes.
  ///
  /// Parameters:
  /// - [crdt]: The CRDT instance to register
  ///
  /// Throws [CRDTException] if a CRDT with the same ID is already registered.
  Future<void> register<T extends CRDT>(T crdt) async {
    _checkInitialized();

    if (_crdts.containsKey(crdt.id)) {
      throw CRDTException(
        'CRDT with ID ${crdt.id} is already registered',
        crdtId: crdt.id,
      );
    }

    _crdts[crdt.id] = crdt;
    await _store.saveCRDT(crdt);

    _updateController.add(
      CRDTUpdateEvent(
        crdtId: crdt.id,
        type: CRDTUpdateType.registered,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Unregister a CRDT from this manager.
  ///
  /// The CRDT will no longer be managed, but its state will remain in storage
  /// unless explicitly removed.
  ///
  /// Parameters:
  /// - [crdtId]: The ID of the CRDT to unregister
  ///
  /// Returns true if the CRDT was found and unregistered, false otherwise.
  Future<bool> unregister(String crdtId) async {
    _checkInitialized();

    final crdt = _crdts.remove(crdtId);
    if (crdt != null) {
      _updateController.add(
        CRDTUpdateEvent(
          crdtId: crdtId,
          type: CRDTUpdateType.unregistered,
          timestamp: DateTime.now(),
        ),
      );
      return true;
    }
    return false;
  }

  /// Get a CRDT by its ID.
  ///
  /// Parameters:
  /// - [crdtId]: The unique identifier of the CRDT
  ///
  /// Returns the CRDT instance, or null if not found.
  T? getCRDT<T extends CRDT>(String crdtId) {
    _checkInitialized();
    return _crdts[crdtId] as T?;
  }

  /// Get all registered CRDT IDs.
  List<String> getCRDTIds() {
    _checkInitialized();
    return List.unmodifiable(_crdts.keys);
  }

  /// Get all registered CRDTs.
  List<CRDT> getAllCRDTs() {
    _checkInitialized();
    return List.unmodifiable(_crdts.values);
  }

  /// Perform a CRDT operation.
  ///
  /// The operation will be applied locally and then broadcast to other nodes
  /// through the gossip protocol.
  ///
  /// Parameters:
  /// - [crdtId]: The ID of the CRDT to operate on
  /// - [operation]: The operation type (e.g., 'increment', 'add', 'remove')
  /// - [data]: Operation-specific data
  ///
  /// Throws [CRDTException] if the CRDT is not found or the operation fails.
  Future<void> performOperation(
    String crdtId,
    String operation,
    Map<String, dynamic> data,
  ) async {
    _checkInitialized();

    final crdt = _crdts[crdtId];
    if (crdt == null) {
      throw CRDTException('CRDT with ID $crdtId not found', crdtId: crdtId);
    }

    final crdtOp = CRDTOperation.withId(
      crdtId: crdtId,
      operation: operation,
      data: data,
      nodeId: _gossipNode.config.nodeId,
      timestamp: DateTime.now(),
    );

    try {
      // Apply locally first
      crdt.applyOperation(crdtOp);
      await _store.saveCRDT(crdt);

      // Broadcast to other nodes
      await _gossipNode.createEvent({
        'type': 'crdt_operation',
        'operation': crdtOp.toJson(),
      });

      // Notify listeners
      _operationController.add(
        CRDTOperationEvent(
          operation: crdtOp,
          source: CRDTOperationSource.local,
          timestamp: DateTime.now(),
        ),
      );

      _updateController.add(
        CRDTUpdateEvent(
          crdtId: crdtId,
          type: CRDTUpdateType.operationApplied,
          timestamp: DateTime.now(),
          operation: crdtOp,
        ),
      );
    } catch (e) {
      throw CRDTException(
        'Failed to perform operation $operation on CRDT $crdtId: $e',
        crdtId: crdtId,
        operation: crdtOp,
        cause: e,
      );
    }
  }

  /// Synchronize CRDT state with another node.
  ///
  /// This sends the current state of all registered CRDTs to the specified peer.
  /// Useful for explicit synchronization or when a new node joins the network.
  ///
  /// Parameters:
  /// - [peerId]: The ID of the peer to synchronize with
  Future<void> syncWith(String peerId) async {
    _checkInitialized();

    final states = <String, Map<String, dynamic>>{};
    for (final crdt in _crdts.values) {
      states[crdt.id] = crdt.getState();
    }

    await _gossipNode.createEvent({
      'type': 'crdt_sync',
      'states': states,
      'targetPeer': peerId,
    });

    _syncController.add(
      CRDTSyncEvent(
        peerId: peerId,
        type: CRDTSyncType.initiated,
        crdtCount: states.length,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Force synchronization of all CRDTs.
  ///
  /// This broadcasts the current state of all CRDTs to all peers.
  /// Should be used sparingly as it can generate significant network traffic.
  Future<void> forceSync() async {
    _checkInitialized();

    final states = <String, Map<String, dynamic>>{};
    for (final crdt in _crdts.values) {
      states[crdt.id] = crdt.getState();
    }

    await _gossipNode.createEvent({
      'type': 'crdt_force_sync',
      'states': states,
    });

    _syncController.add(
      CRDTSyncEvent(
        type: CRDTSyncType.forced,
        crdtCount: states.length,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Stream of CRDT update events.
  ///
  /// Emits events when CRDTs are registered, operations are applied, etc.
  Stream<CRDTUpdateEvent> get onUpdate => _updateController.stream;

  /// Stream of CRDT operation events.
  ///
  /// Emits events when operations are performed, both locally and from peers.
  Stream<CRDTOperationEvent> get onOperation => _operationController.stream;

  /// Stream of CRDT synchronization events.
  ///
  /// Emits events when synchronization operations occur.
  Stream<CRDTSyncEvent> get onSync => _syncController.stream;

  /// Close the CRDT manager and release resources.
  ///
  /// After calling this method, the manager should not be used.
  Future<void> close() async {
    if (_isClosed) return;

    _isClosed = true;
    _isInitialized = false;

    // Cancel subscriptions
    for (final subscription in _operationSubscriptions.values) {
      await subscription.cancel();
    }
    _operationSubscriptions.clear();

    // Close stream controllers
    await _updateController.close();
    await _operationController.close();
    await _syncController.close();

    // Close store
    await _store.close();
  }

  /// Handle incoming gossip events that might be CRDT-related.
  Future<void> _handleGossipEvent(ReceivedEvent receivedEvent) async {
    final event = receivedEvent.event;
    final eventType = event.payload['type'] as String?;

    switch (eventType) {
      case 'crdt_operation':
        await _handleCRDTOperation(receivedEvent);
        break;
      case 'crdt_sync':
        await _handleCRDTSync(receivedEvent);
        break;
      case 'crdt_force_sync':
        await _handleCRDTForceSync(receivedEvent);
        break;
    }
  }

  /// Handle a CRDT operation from another node.
  Future<void> _handleCRDTOperation(ReceivedEvent receivedEvent) async {
    try {
      final operationData =
          receivedEvent.event.payload['operation'] as Map<String, dynamic>;
      final operation = CRDTOperation.fromJson(operationData);

      final crdt = _crdts[operation.crdtId];
      if (crdt != null) {
        crdt.applyOperation(operation);
        await _store.saveCRDT(crdt);

        _operationController.add(
          CRDTOperationEvent(
            operation: operation,
            source: CRDTOperationSource.remote,
            timestamp: DateTime.now(),
          ),
        );

        _updateController.add(
          CRDTUpdateEvent(
            crdtId: operation.crdtId,
            type: CRDTUpdateType.operationApplied,
            timestamp: DateTime.now(),
            operation: operation,
          ),
        );
      }
    } catch (e) {
      // Log error but don't propagate - gossip should be resilient
    }
  }

  /// Handle CRDT state synchronization from another node.
  Future<void> _handleCRDTSync(ReceivedEvent receivedEvent) async {
    try {
      final targetPeer = receivedEvent.event.payload['targetPeer'] as String?;

      // Only process if this sync is targeted at us
      if (targetPeer != null && targetPeer != _gossipNode.config.nodeId) {
        return;
      }

      final states =
          receivedEvent.event.payload['states'] as Map<String, dynamic>;
      await _mergeCRDTStates(states);

      _syncController.add(
        CRDTSyncEvent(
          peerId: receivedEvent.event.nodeId,
          type: CRDTSyncType.received,
          crdtCount: states.length,
          timestamp: DateTime.now(),
        ),
      );
    } catch (e) {
      // Log error but don't propagate
    }
  }

  /// Handle forced CRDT synchronization from another node.
  Future<void> _handleCRDTForceSync(ReceivedEvent receivedEvent) async {
    try {
      final states =
          receivedEvent.event.payload['states'] as Map<String, dynamic>;
      await _mergeCRDTStates(states);

      _syncController.add(
        CRDTSyncEvent(
          peerId: receivedEvent.event.nodeId,
          type: CRDTSyncType.forcedReceived,
          crdtCount: states.length,
          timestamp: DateTime.now(),
        ),
      );
    } catch (e) {
      // Log error but don't propagate
    }
  }

  /// Merge CRDT states from another node.
  Future<void> _mergeCRDTStates(Map<String, dynamic> states) async {
    for (final entry in states.entries) {
      final crdtId = entry.key;
      final state = entry.value as Map<String, dynamic>;

      final crdt = _crdts[crdtId];
      if (crdt != null) {
        crdt.mergeState(state);
        await _store.saveCRDT(crdt);
      }
    }
  }

  /// Load previously saved CRDTs from storage.
  Future<void> _loadCRDTsFromStorage() async {
    try {
      await _store.getAllCRDTIds();
      // Note: This is a basic implementation. In practice, you'd need
      // a registry of CRDT factories to recreate CRDTs from stored state.
      // For now, we just track that CRDTs exist in storage.
    } catch (e) {
      // Log warning but continue - better to start fresh than fail
    }
  }

  /// Check that the manager has been initialized.
  void _checkInitialized() {
    if (!_isInitialized) {
      throw CRDTException('CRDT manager has not been initialized');
    }
    _checkNotClosed();
  }

  /// Check that the manager has not been closed.
  void _checkNotClosed() {
    if (_isClosed) {
      throw CRDTException('CRDT manager has been closed');
    }
  }

  /// Returns whether the manager is initialized.
  bool get isInitialized => _isInitialized;

  /// Returns whether the manager is closed.
  bool get isClosed => _isClosed;

  /// Get statistics about managed CRDTs.
  CRDTManagerStats getStats() {
    return CRDTManagerStats(
      totalCRDTs: _crdts.length,
      crdtTypes: _crdts.values.map((crdt) => crdt.type).toSet().toList(),
      isInitialized: _isInitialized,
      isClosed: _isClosed,
    );
  }
}

/// Types of CRDT updates.
enum CRDTUpdateType { registered, unregistered, operationApplied, stateMerged }

/// Sources of CRDT operations.
enum CRDTOperationSource { local, remote }

/// Types of CRDT synchronization.
enum CRDTSyncType { initiated, received, forced, forcedReceived }

/// Event emitted when a CRDT is updated.
class CRDTUpdateEvent {
  final String crdtId;
  final CRDTUpdateType type;
  final DateTime timestamp;
  final CRDTOperation? operation;

  const CRDTUpdateEvent({
    required this.crdtId,
    required this.type,
    required this.timestamp,
    this.operation,
  });

  @override
  String toString() =>
      'CRDTUpdateEvent(crdtId: $crdtId, type: $type, timestamp: $timestamp)';
}

/// Event emitted when a CRDT operation occurs.
class CRDTOperationEvent {
  final CRDTOperation operation;
  final CRDTOperationSource source;
  final DateTime timestamp;

  const CRDTOperationEvent({
    required this.operation,
    required this.source,
    required this.timestamp,
  });

  @override
  String toString() =>
      'CRDTOperationEvent(operation: ${operation.operation}, '
      'source: $source, timestamp: $timestamp)';
}

/// Event emitted when CRDT synchronization occurs.
class CRDTSyncEvent {
  final String? peerId;
  final CRDTSyncType type;
  final int crdtCount;
  final DateTime timestamp;

  const CRDTSyncEvent({
    this.peerId,
    required this.type,
    required this.crdtCount,
    required this.timestamp,
  });

  @override
  String toString() =>
      'CRDTSyncEvent(peerId: $peerId, type: $type, '
      'crdtCount: $crdtCount, timestamp: $timestamp)';
}

/// Statistics about a CRDT manager.
class CRDTManagerStats {
  final int totalCRDTs;
  final List<String> crdtTypes;
  final bool isInitialized;
  final bool isClosed;

  const CRDTManagerStats({
    required this.totalCRDTs,
    required this.crdtTypes,
    required this.isInitialized,
    required this.isClosed,
  });

  @override
  String toString() =>
      'CRDTManagerStats(totalCRDTs: $totalCRDTs, '
      'crdtTypes: $crdtTypes, isInitialized: $isInitialized, '
      'isClosed: $isClosed)';
}
