/// Storage interface for CRDT state persistence.
///
/// This module defines the abstract interface for persisting CRDT state
/// and provides a memory-based implementation for development and testing.
/// Production applications should implement custom storage backends.
library;

import 'dart:async';
import 'dart:convert';

import 'crdts/crdt.dart';

/// Abstract interface for CRDT state storage.
///
/// CRDT stores are responsible for persisting CRDT state across restarts
/// and providing efficient access to CRDT instances. Different implementations
/// can use various storage backends (memory, file system, databases, etc.).
abstract class CRDTStore {
  /// Save a CRDT's current state to persistent storage.
  ///
  /// The CRDT's state should be serialized and stored in a way that allows
  /// it to be restored later. The storage should be atomic to prevent
  /// corruption during concurrent access.
  ///
  /// Parameters:
  /// - [crdt]: The CRDT instance to save
  ///
  /// Throws [CRDTStoreException] if the save operation fails.
  Future<void> saveCRDT(CRDT crdt);

  /// Load a CRDT's state from persistent storage.
  ///
  /// Returns the serialized state that can be used to reconstruct the CRDT,
  /// or null if no state exists for the given CRDT ID.
  ///
  /// Parameters:
  /// - [crdtId]: The unique identifier of the CRDT to load
  ///
  /// Returns:
  /// - The CRDT's serialized state, or null if not found
  ///
  /// Throws [CRDTStoreException] if the load operation fails.
  Future<Map<String, dynamic>?> loadCRDTState(String crdtId);

  /// Check if a CRDT exists in storage.
  ///
  /// This can be more efficient than loading the full state when you only
  /// need to check existence.
  ///
  /// Parameters:
  /// - [crdtId]: The unique identifier of the CRDT to check
  ///
  /// Returns:
  /// - true if the CRDT exists in storage, false otherwise
  ///
  /// Throws [CRDTStoreException] if the check operation fails.
  Future<bool> hasCRDT(String crdtId);

  /// Get a list of all CRDT IDs in storage.
  ///
  /// This is useful for discovering existing CRDTs during initialization
  /// or for administrative operations.
  ///
  /// Returns:
  /// - A list of all CRDT IDs currently in storage
  ///
  /// Throws [CRDTStoreException] if the operation fails.
  Future<List<String>> getAllCRDTIds();

  /// Remove a CRDT from storage.
  ///
  /// This permanently deletes the CRDT's state. Use with caution as this
  /// operation cannot be undone.
  ///
  /// Parameters:
  /// - [crdtId]: The unique identifier of the CRDT to remove
  ///
  /// Returns:
  /// - true if the CRDT was found and removed, false if it didn't exist
  ///
  /// Throws [CRDTStoreException] if the removal operation fails.
  Future<bool> removeCRDT(String crdtId);

  /// Clear all CRDTs from storage.
  ///
  /// This removes all CRDT state from the store. Primarily useful for
  /// testing or when resetting the entire system.
  ///
  /// Throws [CRDTStoreException] if the clear operation fails.
  Future<void> clear();

  /// Get statistics about the store.
  ///
  /// Returns information about the number of CRDTs stored, storage size,
  /// and other metrics that may be useful for monitoring.
  Future<CRDTStoreStats> getStats();

  /// Close the store and release any resources.
  ///
  /// After calling this method, the store should not be used. Any pending
  /// operations should be completed or cancelled gracefully.
  Future<void> close();
}

/// Statistics about a CRDT store's current state.
class CRDTStoreStats {
  /// Total number of CRDTs in the store.
  final int totalCRDTs;

  /// Approximate size of stored data in bytes.
  final int? sizeInBytes;

  /// Additional store-specific statistics.
  final Map<String, dynamic> additionalStats;

  const CRDTStoreStats({
    required this.totalCRDTs,
    this.sizeInBytes,
    this.additionalStats = const {},
  });

  @override
  String toString() {
    final buffer = StringBuffer('CRDTStoreStats(');
    buffer.write('totalCRDTs: $totalCRDTs');
    if (sizeInBytes != null) {
      buffer.write(', sizeInBytes: $sizeInBytes');
    }
    if (additionalStats.isNotEmpty) {
      buffer.write(', additionalStats: $additionalStats');
    }
    buffer.write(')');
    return buffer.toString();
  }
}

/// Exception thrown when CRDT storage operations fail.
class CRDTStoreException implements Exception {
  /// The error message describing what went wrong.
  final String message;

  /// The CRDT ID associated with the error, if any.
  final String? crdtId;

  /// The underlying cause of the error, if any.
  final Object? cause;

  /// Stack trace from the original error, if available.
  final StackTrace? stackTrace;

  const CRDTStoreException(
    this.message, {
    this.crdtId,
    this.cause,
    this.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer('CRDTStoreException: $message');
    if (crdtId != null) {
      buffer.write(' (CRDT ID: $crdtId)');
    }
    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }
    return buffer.toString();
  }
}

/// In-memory implementation of CRDTStore for development and testing.
///
/// **Warning**: This implementation does not provide actual persistence!
/// All CRDT state is stored in memory and will be lost when the application
/// terminates.
///
/// This implementation is suitable for:
/// - Development and testing
/// - Prototyping
/// - Single-session applications
///
/// For production use, implement a persistent storage backend.
class MemoryCRDTStore implements CRDTStore {
  final Map<String, Map<String, dynamic>> _crdtStates = {};
  bool _isClosed = false;

  @override
  Future<void> saveCRDT(CRDT crdt) async {
    _checkNotClosed();

    try {
      _crdtStates[crdt.id] = Map<String, dynamic>.from(crdt.getState());
    } catch (e, stackTrace) {
      throw CRDTStoreException(
        'Failed to save CRDT',
        crdtId: crdt.id,
        cause: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<Map<String, dynamic>?> loadCRDTState(String crdtId) async {
    _checkNotClosed();

    try {
      final state = _crdtStates[crdtId];
      return state != null ? Map<String, dynamic>.from(state) : null;
    } catch (e, stackTrace) {
      throw CRDTStoreException(
        'Failed to load CRDT state',
        crdtId: crdtId,
        cause: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<bool> hasCRDT(String crdtId) async {
    _checkNotClosed();
    return _crdtStates.containsKey(crdtId);
  }

  @override
  Future<List<String>> getAllCRDTIds() async {
    _checkNotClosed();
    return List<String>.from(_crdtStates.keys);
  }

  @override
  Future<bool> removeCRDT(String crdtId) async {
    _checkNotClosed();
    return _crdtStates.remove(crdtId) != null;
  }

  @override
  Future<void> clear() async {
    _checkNotClosed();
    _crdtStates.clear();
  }

  @override
  Future<CRDTStoreStats> getStats() async {
    _checkNotClosed();

    int totalSize = 0;
    for (final state in _crdtStates.values) {
      try {
        final jsonString = jsonEncode(state);
        totalSize += jsonString.length * 2; // Rough UTF-16 estimate
      } catch (e) {
        // Skip states that can't be serialized
      }
    }

    return CRDTStoreStats(
      totalCRDTs: _crdtStates.length,
      sizeInBytes: totalSize,
      additionalStats: {'implementation': 'memory', 'isClosed': _isClosed},
    );
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    _crdtStates.clear();
  }

  /// Check if the store has been closed.
  void _checkNotClosed() {
    if (_isClosed) {
      throw CRDTStoreException('CRDT store has been closed');
    }
  }

  /// Returns whether the store has been closed (for testing).
  bool get isClosed => _isClosed;

  /// Returns the current number of stored CRDTs (for testing).
  int get count => _crdtStates.length;
}
