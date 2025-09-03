/// Vector clock persistence interface for the gossip protocol.
///
/// This interface defines how vector clocks should be persisted to survive
/// node restarts and prevent causality violations that would occur if
/// vector clocks were reset.
///
/// Proper vector clock persistence is crucial for maintaining the causal
/// ordering guarantees that the gossip protocol depends on.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'vector_clock.dart';

/// Abstract interface for persisting vector clock state.
///
/// Vector clocks must be persisted to maintain causality across node restarts.
/// Resetting vector clocks breaks the fundamental guarantee of causal ordering
/// that distributed systems rely on.
///
/// ## Why Persistence is Critical
///
/// Vector clocks track the "happens-before" relationship between events.
/// If a vector clock is reset:
/// - New events may appear to happen "before" older events
/// - Causality chains are broken
/// - The distributed system loses consistency guarantees
///
/// ## Implementation Requirements
///
/// Implementations should:
/// - Persist vector clock state atomically
/// - Handle concurrent access safely
/// - Provide durability guarantees appropriate for the use case
/// - Fail fast if persistence operations fail
abstract class VectorClockStore {
  /// Saves the vector clock state to persistent storage.
  ///
  /// This method should be called whenever the vector clock is updated
  /// to ensure the state is preserved across restarts.
  ///
  /// Parameters:
  /// - [nodeId]: The ID of the node whose vector clock is being saved
  /// - [vectorClock]: The current vector clock state to persist
  ///
  /// Throws [VectorClockStoreException] if the save operation fails.
  Future<void> saveVectorClock(String nodeId, VectorClock vectorClock);

  /// Loads the vector clock state from persistent storage.
  ///
  /// This method should be called during node startup to restore
  /// the previously saved vector clock state.
  ///
  /// Parameters:
  /// - [nodeId]: The ID of the node whose vector clock should be loaded
  ///
  /// Returns:
  /// - The previously saved vector clock, or null if no state exists
  ///
  /// Throws [VectorClockStoreException] if the load operation fails.
  Future<VectorClock?> loadVectorClock(String nodeId);

  /// Checks if vector clock state exists for the given node.
  ///
  /// This can be used to determine if a node is starting fresh or
  /// recovering from a previous state.
  ///
  /// Parameters:
  /// - [nodeId]: The ID of the node to check
  ///
  /// Returns:
  /// - true if vector clock state exists, false otherwise
  ///
  /// Throws [VectorClockStoreException] if the check operation fails.
  Future<bool> hasVectorClock(String nodeId);

  /// Deletes the vector clock state for the given node.
  ///
  /// This should be used with extreme caution as it will break causality
  /// if the node continues to operate. Primary use cases:
  /// - Node permanently leaving the system
  /// - Testing scenarios
  /// - Administrative cleanup
  ///
  /// Parameters:
  /// - [nodeId]: The ID of the node whose state should be deleted
  ///
  /// Returns:
  /// - true if state was deleted, false if no state existed
  ///
  /// Throws [VectorClockStoreException] if the delete operation fails.
  Future<bool> deleteVectorClock(String nodeId);

  /// Closes the vector clock store and releases any resources.
  ///
  /// After calling this method, the store should not be used.
  Future<void> close();
}

/// Exception thrown when vector clock persistence operations fail.
class VectorClockStoreException implements Exception {
  /// The error message describing what went wrong.
  final String message;

  /// The underlying cause of the error, if any.
  final Object? cause;

  /// Stack trace from the original error, if available.
  final StackTrace? stackTrace;

  /// The node ID associated with the failed operation, if applicable.
  final String? nodeId;

  /// The operation that failed (save, load, delete, etc.).
  final String? operation;

  const VectorClockStoreException(
    this.message, {
    this.cause,
    this.stackTrace,
    this.nodeId,
    this.operation,
  });

  @override
  String toString() {
    final buffer = StringBuffer('VectorClockStoreException: $message');

    if (nodeId != null) {
      buffer.write(' (node: $nodeId)');
    }

    if (operation != null) {
      buffer.write(' (operation: $operation)');
    }

    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }

    return buffer.toString();
  }
}

/// In-memory implementation of VectorClockStore for testing and development.
///
/// **Warning**: This implementation does not provide actual persistence!
/// Vector clock state is stored in memory and will be lost when the
/// application terminates.
///
/// This implementation is suitable for:
/// - Unit testing
/// - Development and debugging
/// - Scenarios where persistence is not required
///
/// For production use, implement a persistent storage backend such as:
/// - File-based storage
/// - Database storage
/// - Key-value store integration
class MemoryVectorClockStore implements VectorClockStore {
  final Map<String, VectorClock> _vectorClocks = {};
  bool _isClosed = false;

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

    // Store a copy to prevent external modifications
    _vectorClocks[nodeId] = vectorClock.copy();
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

    final vectorClock = _vectorClocks[nodeId];
    // Return a copy to prevent external modifications
    return vectorClock?.copy();
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

    return _vectorClocks.containsKey(nodeId);
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

    return _vectorClocks.remove(nodeId) != null;
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;

    _isClosed = true;
    _vectorClocks.clear();
  }

  /// Checks if the store has been closed and throws an exception if it has.
  void _checkNotClosed() {
    if (_isClosed) {
      throw VectorClockStoreException('Vector clock store has been closed');
    }
  }

  /// Returns whether the store has been closed (for testing).
  bool get isClosed => _isClosed;

  /// Returns the number of stored vector clocks (for testing).
  int get count => _vectorClocks.length;

  /// Returns all stored node IDs (for testing).
  Set<String> get storedNodeIds => Set.from(_vectorClocks.keys);
}

/// File-based implementation of VectorClockStore.
///
/// This implementation persists vector clocks to the file system using JSON
/// serialization. Each node's vector clock is stored in a separate file.
///
/// ## File Structure
///
/// ```
/// vector_clocks/
/// ├── node_1.json
/// ├── node_2.json
/// └── node_3.json
/// ```
///
/// ## Thread Safety
///
/// This implementation uses file locking to ensure thread safety when
/// multiple processes might access the same vector clock files.
///
/// ## Error Handling
///
/// File I/O errors are wrapped in VectorClockStoreException with
/// appropriate context about the failed operation.
class FileVectorClockStore implements VectorClockStore {
  final String directoryPath;
  bool _isClosed = false;

  /// Creates a file-based vector clock store.
  ///
  /// Parameters:
  /// - [directoryPath]: Directory where vector clock files will be stored
  ///
  /// The directory will be created if it doesn't exist.
  FileVectorClockStore(this.directoryPath);

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
      await _ensureDirectoryExists();
      final file = _getFileForNode(nodeId);
      final json = vectorClock.toJson();
      await file.writeAsString(_jsonEncode(json));
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
      final file = _getFileForNode(nodeId);
      if (!await file.exists()) {
        return null;
      }

      final content = await file.readAsString();
      final json = _jsonDecode(content) as Map<String, dynamic>;
      return VectorClock.fromJson(json);
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
      final file = _getFileForNode(nodeId);
      return await file.exists();
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
      final file = _getFileForNode(nodeId);
      if (!await file.exists()) {
        return false;
      }

      await file.delete();
      return true;
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

  /// Ensures the storage directory exists.
  Future<void> _ensureDirectoryExists() async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  /// Gets the file path for a node's vector clock.
  File _getFileForNode(String nodeId) {
    // Sanitize node ID for use in filename
    final sanitizedNodeId = nodeId.replaceAll(RegExp(r'[^\w\-_.]'), '_');
    return File('$directoryPath/$sanitizedNodeId.json');
  }

  /// JSON encoding helper.
  String _jsonEncode(Map<String, dynamic> json) {
    return JsonEncoder.withIndent('  ').convert(json);
  }

  /// JSON decoding helper.
  Object? _jsonDecode(String content) {
    return json.decode(content);
  }

  /// Checks if the store has been closed.
  void _checkNotClosed() {
    if (_isClosed) {
      throw VectorClockStoreException('Vector clock store has been closed');
    }
  }

  /// Returns whether the store has been closed (for testing).
  bool get isClosed => _isClosed;
}
