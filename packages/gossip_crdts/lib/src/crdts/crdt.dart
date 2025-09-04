/// Base interface for all CRDT implementations.
///
/// This module defines the core abstractions for Conflict-free Replicated Data Types
/// (CRDTs) that can be synchronized across distributed nodes using the gossip protocol.
///
/// CRDTs guarantee eventual consistency without requiring coordination between nodes.
/// They achieve this by ensuring that all operations are commutative, associative,
/// and idempotent, allowing them to be applied in any order with the same result.
library;

import 'dart:convert';

/// Abstract base class for all CRDT implementations.
///
/// CRDTs must implement merge semantics that are:
/// - **Commutative**: merge(A, B) = merge(B, A)
/// - **Associative**: merge(merge(A, B), C) = merge(A, merge(B, C))
/// - **Idempotent**: merge(A, A) = A
abstract class CRDT<T> {
  /// Unique identifier for this CRDT instance across all nodes.
  String get id;

  /// Current value of the CRDT.
  ///
  /// This represents the resolved state after applying all known operations.
  T get value;

  /// Apply a CRDT operation to this instance.
  ///
  /// Operations should be applied idempotently - applying the same operation
  /// multiple times should have the same effect as applying it once.
  void applyOperation(CRDTOperation operation);

  /// Get the current state for synchronization with other replicas.
  ///
  /// This state should contain all information necessary to reconstruct
  /// the CRDT's current value on another node.
  Map<String, dynamic> getState();

  /// Merge state from another replica.
  ///
  /// This method implements the core CRDT merge semantics. After merging,
  /// this CRDT should represent the union of knowledge from both replicas.
  void mergeState(Map<String, dynamic> otherState);

  /// Create an operation for this CRDT.
  ///
  /// This is a factory method for creating properly formatted operations
  /// that can be applied to other replicas of this CRDT.
  CRDTOperation createOperation(
    String operationType,
    Map<String, dynamic> data, {
    String? nodeId,
    DateTime? timestamp,
  });

  /// Creates a deep copy of this CRDT.
  CRDT<T> copy();

  /// Reset the CRDT to its initial empty state.
  ///
  /// This is primarily useful for testing or when starting fresh.
  void reset();

  /// Get the type name of this CRDT.
  ///
  /// Used for serialization and deserialization of CRDT state.
  String get type;

  /// Validate that the CRDT is in a consistent state.
  ///
  /// Throws [CRDTException] if the CRDT is in an invalid state.
  /// This is primarily used for debugging and testing.
  void validate() {
    // Default implementation does nothing
  }

  /// Compare this CRDT with another for equality.
  ///
  /// Two CRDTs are equal if they have the same ID and equivalent state.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CRDT<T>) return false;
    return id == other.id && _stateEquals(getState(), other.getState());
  }

  @override
  int get hashCode => Object.hash(id, _stateHashCode(getState()));

  @override
  String toString() => '$type(id: $id, value: $value)';

  /// Helper method to compare CRDT states for equality.
  bool _stateEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      final valueA = a[key];
      final valueB = b[key];
      if (!_deepEquals(valueA, valueB)) return false;
    }
    return true;
  }

  /// Helper method to compute hash code for CRDT state.
  int _stateHashCode(Map<String, dynamic> state) {
    int hash = 0;
    for (final entry in state.entries) {
      hash ^= entry.key.hashCode ^ _deepHashCode(entry.value);
    }
    return hash;
  }

  /// Deep equality check for dynamic values.
  bool _deepEquals(dynamic a, dynamic b) {
    if (identical(a, b)) return true;
    if (a.runtimeType != b.runtimeType) return false;

    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) {
          return false;
        }
      }
      return true;
    }

    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (int i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }

    if (a is Set && b is Set) {
      if (a.length != b.length) return false;
      return a.containsAll(b) && b.containsAll(a);
    }

    return a == b;
  }

  /// Deep hash code for dynamic values.
  int _deepHashCode(dynamic value) {
    if (value == null) return 0;
    if (value is Map) {
      int hash = 0;
      for (final entry in value.entries) {
        hash ^= entry.key.hashCode ^ _deepHashCode(entry.value);
      }
      return hash;
    }
    if (value is List) {
      return Object.hashAll(value.map(_deepHashCode));
    }
    if (value is Set) {
      int hash = 0;
      for (final item in value) {
        hash ^= _deepHashCode(item);
      }
      return hash;
    }
    return value.hashCode;
  }
}

/// Represents a CRDT operation that can be applied across replicas.
///
/// Operations are the unit of change in CRDTs. They must be designed to be
/// commutative, associative, and idempotent to ensure convergence.
class CRDTOperation {
  /// The ID of the CRDT this operation applies to.
  final String crdtId;

  /// The type of operation (e.g., 'increment', 'add', 'remove').
  final String operation;

  /// Operation-specific data payload.
  final Map<String, dynamic> data;

  /// The ID of the node that created this operation.
  final String nodeId;

  /// When this operation was created.
  final DateTime timestamp;

  /// Unique identifier for this operation.
  ///
  /// Used to ensure idempotent application of operations.
  final String operationId;

  const CRDTOperation({
    required this.crdtId,
    required this.operation,
    required this.data,
    required this.nodeId,
    required this.timestamp,
    String? operationId,
  }) : operationId = operationId ?? '';

  /// Create an operation with a generated unique ID.
  CRDTOperation.withId({
    required this.crdtId,
    required this.operation,
    required this.data,
    required this.nodeId,
    required this.timestamp,
  }) : operationId = _generateOperationId(nodeId, timestamp);

  /// Serialize this operation to JSON.
  Map<String, dynamic> toJson() => {
        'crdtId': crdtId,
        'operation': operation,
        'data': data,
        'nodeId': nodeId,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'operationId': operationId,
      };

  /// Deserialize an operation from JSON.
  factory CRDTOperation.fromJson(Map<String, dynamic> json) {
    return CRDTOperation(
      crdtId: json['crdtId'] as String,
      operation: json['operation'] as String,
      data: Map<String, dynamic>.from(json['data'] as Map),
      nodeId: json['nodeId'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      operationId: json['operationId'] as String? ?? '',
    );
  }

  /// Generate a unique operation ID.
  static String _generateOperationId(String nodeId, DateTime timestamp) {
    final data = utf8.encode('$nodeId-${timestamp.millisecondsSinceEpoch}');
    return base64Encode(data).replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CRDTOperation) return false;
    return operationId == other.operationId &&
        crdtId == other.crdtId &&
        operation == other.operation &&
        nodeId == other.nodeId &&
        timestamp == other.timestamp;
  }

  @override
  int get hashCode =>
      Object.hash(operationId, crdtId, operation, nodeId, timestamp);

  @override
  String toString() => 'CRDTOperation('
      'id: $operationId, '
      'crdtId: $crdtId, '
      'operation: $operation, '
      'nodeId: $nodeId, '
      'timestamp: $timestamp'
      ')';
}

/// Exception thrown when CRDT operations fail.
class CRDTException implements Exception {
  /// The error message describing what went wrong.
  final String message;

  /// The CRDT ID associated with the error, if any.
  final String? crdtId;

  /// The operation that caused the error, if any.
  final CRDTOperation? operation;

  /// The underlying cause of the error, if any.
  final Object? cause;

  const CRDTException(this.message, {this.crdtId, this.operation, this.cause});

  @override
  String toString() {
    final buffer = StringBuffer('CRDTException: $message');
    if (crdtId != null) {
      buffer.write(' (CRDT ID: $crdtId)');
    }
    if (operation != null) {
      buffer.write(' (Operation: ${operation!.operation})');
    }
    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }
    return buffer.toString();
  }
}

/// Mixin for CRDTs that need to track vector clocks for causality.
///
/// This is useful for CRDTs that need to determine the causal relationship
/// between operations from different nodes.
mixin VectorClockMixin<T> on CRDT<T> {
  final Map<String, int> _vectorClock = {};

  /// Get the current vector clock.
  Map<String, int> get vectorClock => Map.unmodifiable(_vectorClock);

  /// Update the vector clock with an operation.
  void updateVectorClock(CRDTOperation operation) {
    _vectorClock[operation.nodeId] = (_vectorClock[operation.nodeId] ?? 0) + 1;
  }

  /// Merge vector clock from another replica.
  void mergeVectorClock(Map<String, int> otherClock) {
    for (final entry in otherClock.entries) {
      final currentValue = _vectorClock[entry.key] ?? 0;
      _vectorClock[entry.key] =
          currentValue > entry.value ? currentValue : entry.value;
    }
  }

  /// Check if this vector clock happens before another.
  bool happensBefore(Map<String, int> other) {
    bool isLessOrEqual = true;
    bool isStrictlyLess = false;

    final allNodes = <String>{..._vectorClock.keys, ...other.keys};
    for (final node in allNodes) {
      final thisValue = _vectorClock[node] ?? 0;
      final otherValue = other[node] ?? 0;

      if (thisValue > otherValue) {
        isLessOrEqual = false;
        break;
      } else if (thisValue < otherValue) {
        isStrictlyLess = true;
      }
    }

    return isLessOrEqual && isStrictlyLess;
  }

  /// Check if two vector clocks are concurrent.
  bool isConcurrentWith(Map<String, int> other) {
    return !happensBefore(other) && !_otherHappensBefore(other);
  }

  bool _otherHappensBefore(Map<String, int> other) {
    bool isLessOrEqual = true;
    bool isStrictlyLess = false;

    final allNodes = <String>{..._vectorClock.keys, ...other.keys};
    for (final node in allNodes) {
      final thisValue = _vectorClock[node] ?? 0;
      final otherValue = other[node] ?? 0;

      if (otherValue > thisValue) {
        isLessOrEqual = false;
        break;
      } else if (otherValue < thisValue) {
        isStrictlyLess = true;
      }
    }

    return isLessOrEqual && isStrictlyLess;
  }
}
