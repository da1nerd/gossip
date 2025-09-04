/// Grow-only Counter CRDT implementation.
///
/// A G-Counter (Grow-only Counter) is a state-based CRDT that represents
/// a counter that can only be incremented. It maintains a separate counter
/// for each node in the system and computes the total value as the sum of
/// all individual counters.
///
/// The G-Counter guarantees that:
/// - All replicas will eventually converge to the same value
/// - The counter can only increase (monotonic)
/// - Operations are commutative, associative, and idempotent
///
/// This implementation is suitable for use cases like:
/// - View counters
/// - Like counters
/// - Download counters
/// - Any metric that only increases over time
library;

import 'dart:math' as math;
import 'crdt.dart';

/// A grow-only counter CRDT.
///
/// The G-Counter maintains a vector of counters, one for each node that has
/// incremented the counter. The global value is the sum of all individual
/// node counters. When merging with another replica, each node counter is
/// set to the maximum of the two values (since counters can only increase).
///
/// ## Example Usage
///
/// ```dart
/// final counter1 = GCounter('page-views');
/// final counter2 = GCounter('page-views');
///
/// // Node A increments
/// await manager.performOperation(counter1.id, 'increment', {'amount': 5});
/// print(counter1.value); // 5
///
/// // Node B increments
/// await manager.performOperation(counter2.id, 'increment', {'amount': 3});
/// print(counter2.value); // 3
///
/// // After synchronization, both will show 8
/// counter1.mergeState(counter2.getState());
/// print(counter1.value); // 8
/// ```
class GCounter implements CRDT<int> {
  @override
  final String id;

  final Map<String, int> _counters = {};

  /// Creates a new G-Counter with the specified ID.
  ///
  /// Parameters:
  /// - [id]: Unique identifier for this counter across all nodes
  GCounter(this.id);

  @override
  String get type => 'GCounter';

  @override
  int get value {
    if (_counters.isEmpty) return 0;
    return _counters.values.fold(0, (sum, counter) => sum + counter);
  }

  /// Get the counter value for a specific node.
  ///
  /// Returns 0 if the node has never incremented this counter.
  ///
  /// Parameters:
  /// - [nodeId]: The node ID to get the counter for
  int getCounterFor(String nodeId) {
    return _counters[nodeId] ?? 0;
  }

  /// Get all node counters.
  ///
  /// Returns a read-only map of node IDs to their counter values.
  Map<String, int> get counters => Map.unmodifiable(_counters);

  /// Get the list of nodes that have incremented this counter.
  List<String> get nodes => _counters.keys.toList();

  /// Check if the counter is empty (has no increments).
  bool get isEmpty => _counters.isEmpty;

  /// Increment the counter for a specific node.
  ///
  /// This is typically called internally by the CRDT manager when applying
  /// operations. Direct calls should be avoided in favor of using the
  /// manager's performOperation method.
  ///
  /// Parameters:
  /// - [nodeId]: The node performing the increment
  /// - [amount]: The amount to increment by (must be positive)
  ///
  /// Throws [ArgumentError] if amount is negative.
  void increment(String nodeId, [int amount = 1]) {
    if (amount < 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Amount must be non-negative',
      );
    }
    if (amount == 0) return; // No-op for zero increment

    _counters[nodeId] = (_counters[nodeId] ?? 0) + amount;
  }

  @override
  void applyOperation(CRDTOperation operation) {
    switch (operation.operation) {
      case 'increment':
        final amount = operation.data['amount'] as int? ?? 1;
        increment(operation.nodeId, amount);
        break;
      default:
        throw CRDTException(
          'Unknown operation: ${operation.operation}',
          crdtId: id,
          operation: operation,
        );
    }
  }

  @override
  Map<String, dynamic> getState() => {
        'type': type,
        'id': id,
        'counters': Map<String, int>.from(_counters),
      };

  @override
  void mergeState(Map<String, dynamic> otherState) {
    // Validate state format
    if (otherState['type'] != type) {
      throw CRDTException(
        'Cannot merge state of type ${otherState['type']} into $type',
        crdtId: id,
      );
    }

    if (otherState['id'] != id) {
      throw CRDTException(
        'Cannot merge state from CRDT ${otherState['id']} into $id',
        crdtId: id,
      );
    }

    final otherCounters = otherState['counters'] as Map<String, dynamic>? ?? {};

    for (final entry in otherCounters.entries) {
      final nodeId = entry.key;
      final otherValue = entry.value as int;
      final currentValue = _counters[nodeId] ?? 0;

      // Take the maximum (since counters can only increase)
      _counters[nodeId] = math.max(currentValue, otherValue);
    }
  }

  @override
  CRDTOperation createOperation(
    String operationType,
    Map<String, dynamic> data, {
    String? nodeId,
    DateTime? timestamp,
  }) {
    return CRDTOperation.withId(
      crdtId: id,
      operation: operationType,
      data: data,
      nodeId: nodeId ?? '',
      timestamp: timestamp ?? DateTime.now(),
    );
  }

  @override
  CRDT<int> copy() {
    final copy = GCounter(id);
    copy._counters.addAll(_counters);
    return copy;
  }

  @override
  void reset() {
    _counters.clear();
  }

  @override
  void validate() {
    // Ensure all counter values are non-negative
    for (final entry in _counters.entries) {
      if (entry.value < 0) {
        throw CRDTException(
          'Counter for node ${entry.key} has negative value: ${entry.value}',
          crdtId: id,
        );
      }
    }
  }

  /// Create a new G-Counter from a saved state.
  ///
  /// This factory constructor recreates a G-Counter from previously saved state,
  /// typically loaded from persistent storage.
  ///
  /// Parameters:
  /// - [state]: The state map returned by [getState]
  ///
  /// Throws [CRDTException] if the state format is invalid.
  factory GCounter.fromState(Map<String, dynamic> state) {
    if (state['type'] != 'GCounter') {
      throw CRDTException('Invalid state type: ${state['type']}');
    }

    final id = state['id'] as String;
    final counter = GCounter(id);

    final counters = state['counters'] as Map<String, dynamic>? ?? {};
    for (final entry in counters.entries) {
      final nodeId = entry.key;
      final value = entry.value as int;
      if (value < 0) {
        throw CRDTException(
          'Invalid counter value for node $nodeId: $value',
          crdtId: id,
        );
      }
      counter._counters[nodeId] = value;
    }

    return counter;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! GCounter) return false;
    return super == other;
  }

  @override
  int get hashCode => super.hashCode;

  @override
  String toString() =>
      'GCounter(id: $id, value: $value, nodes: ${nodes.length})';
}
