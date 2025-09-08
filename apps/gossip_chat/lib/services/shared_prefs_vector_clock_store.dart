import 'dart:async';
import 'dart:convert';

import 'package:gossip/gossip.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences-based implementation of VectorClockStore.
///
/// This implementation persists vector clocks using the shared_preferences
/// plugin, making it suitable for Flutter apps on Android, iOS, macOS, etc.
/// Each node's vector clock is stored as a JSON string under a unique key.
///
/// ## Key Structure
///   vector_clock_{nodeId}
///
/// ## Durability
/// SharedPreferences is not as durable as a database or file system, but is
/// sufficient for most mobile use cases where app restarts are the main concern.
class SharedPrefsVectorClockStore implements VectorClockStore {
  bool _isClosed = false;

  String _keyForNode(String nodeId) => 'vector_clock_$nodeId';

  @override
  Future<void> saveVectorClock(String nodeId, VectorClock vectorClock) async {
    _checkNotClosed();

    if (nodeId.isEmpty) {
      throw VectorClockStoreException(
        'Node ID cannot be empty',
        nodeId: nodeId,
        operation: 'save',
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(vectorClock.toJson());
      final success = await prefs.setString(_keyForNode(nodeId), jsonStr);
      if (!success) {
        throw VectorClockStoreException(
          'Failed to save vector clock for node $nodeId (write failed)',
          nodeId: nodeId,
          operation: 'save',
        );
      }
    } catch (e, stackTrace) {
      throw VectorClockStoreException(
        'Failed to save vector clock for node $nodeId: $e',
        cause: e,
        stackTrace: stackTrace,
        nodeId: nodeId,
        operation: 'save',
      );
    }
  }

  @override
  Future<VectorClock?> loadVectorClock(String nodeId) async {
    _checkNotClosed();

    if (nodeId.isEmpty) {
      throw VectorClockStoreException(
        'Node ID cannot be empty',
        nodeId: nodeId,
        operation: 'load',
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_keyForNode(nodeId));
      if (jsonStr == null) return null;
      final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
      return VectorClock.fromJson(jsonMap);
    } catch (e, stackTrace) {
      throw VectorClockStoreException(
        'Failed to load vector clock for node $nodeId: $e',
        cause: e,
        stackTrace: stackTrace,
        nodeId: nodeId,
        operation: 'load',
      );
    }
  }

  @override
  Future<bool> hasVectorClock(String nodeId) async {
    _checkNotClosed();

    if (nodeId.isEmpty) {
      throw VectorClockStoreException(
        'Node ID cannot be empty',
        nodeId: nodeId,
        operation: 'has',
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_keyForNode(nodeId));
    } catch (e, stackTrace) {
      throw VectorClockStoreException(
        'Failed to check vector clock existence for node $nodeId: $e',
        cause: e,
        stackTrace: stackTrace,
        nodeId: nodeId,
        operation: 'has',
      );
    }
  }

  @override
  Future<bool> deleteVectorClock(String nodeId) async {
    _checkNotClosed();

    if (nodeId.isEmpty) {
      throw VectorClockStoreException(
        'Node ID cannot be empty',
        nodeId: nodeId,
        operation: 'delete',
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(_keyForNode(nodeId))) return false;
      return await prefs.remove(_keyForNode(nodeId));
    } catch (e, stackTrace) {
      throw VectorClockStoreException(
        'Failed to delete vector clock for node $nodeId: $e',
        cause: e,
        stackTrace: stackTrace,
        nodeId: nodeId,
        operation: 'delete',
      );
    }
  }

  @override
  Future<void> close() async {
    _isClosed = true;
  }

  void _checkNotClosed() {
    if (_isClosed) {
      throw const VectorClockStoreException(
        'Vector clock store has been closed',
      );
    }
  }
}
