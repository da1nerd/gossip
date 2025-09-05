/// Increment/Decrement Counter CRDT implementation.
///
/// A PN-Counter (Positive-Negative Counter) is a state-based CRDT that represents
/// a counter that can be both incremented and decremented. It combines two
/// G-Counters: one for increments (P) and one for decrements (N).
/// The final value is computed as P - N.
///
/// The PN-Counter guarantees that:
/// - All replicas will eventually converge to the same value
/// - Operations are commutative, associative, and idempotent
/// - Both increment and decrement operations are supported
///
/// This implementation is suitable for use cases like:
/// - Vote tallies (upvotes/downvotes)
/// - Inventory counters
/// - Score counters in games
/// - Any metric that can both increase and decrease
library;

import 'dart:math' as math;
import 'crdt.dart';

/// A positive-negative counter CRDT.
///
/// The PN-Counter maintains two separate G-Counters internally:
/// - P-Counter: tracks all increment operations
/// - N-Counter: tracks all decrement operations
/// The final value is computed as sum(P) - sum(N).
///
/// ## Example Usage
///
/// ```dart
/// final counter1 = PNCounter('vote-tally');
/// final counter2 = PNCounter('vote-tally');
///
/// // Node A increments and decrements
/// await manager.performOperation(counter1.id, 'increment', {'amount': 10});
/// await manager.performOperation(counter1.id, 'decrement', {'amount': 3});
/// print(counter1.value); // 7
///
/// // Node B decrements
/// await manager.performOperation(counter2.id, 'decrement', {'amount': 2});
/// print(counter2.value); // -2
///
/// // After synchronization, both will show 5 (10 - 3 - 2)
/// counter1.mergeState(counter2.getState());
/// print(counter1.value); // 5
/// ```
class PNCounter implements CRDT<int> {
  @override
  final String id;

  // Separate counters for increments (P) and decrements (N)
  final Map<String, int> _pCounters = {}; // Positive counters
  final Map<String, int> _nCounters = {}; // Negative counters

  /// Creates a new PN-Counter with the specified ID.
  ///
  /// Parameters:
  /// - [id]: Unique identifier for this counter across all nodes
  PNCounter(this.id);

  @override
  String get type => 'PNCounter';

  @override
  int get value {
    final pSum = _pCounters.values.fold(0, (sum, counter) => sum + counter);
    final nSum = _nCounters.values.fold(0, (sum, counter) => sum + counter);
    return pSum - nSum;
  }

  /// Get the positive counter value for a specific node.
  ///
  /// Returns 0 if the node has never incremented this counter.
  ///
  /// Parameters:
  /// - [nodeId]: The node ID to get the counter for
  int getPositiveCounterFor(String nodeId) {
    return _pCounters[nodeId] ?? 0;
  }

  /// Get the negative counter value for a specific node.
  ///
  /// Returns 0 if the node has never decremented this counter.
  ///
  /// Parameters:
  /// - [nodeId]: The node ID to get the counter for
  int getNegativeCounterFor(String nodeId) {
    return _nCounters[nodeId] ?? 0;
  }

  /// Get the net counter value for a specific node.
  ///
  /// Returns the difference between positive and negative counters for the node.
  ///
  /// Parameters:
  /// - [nodeId]: The node ID to get the counter for
  int getNetCounterFor(String nodeId) {
    return getPositiveCounterFor(nodeId) - getNegativeCounterFor(nodeId);
  }

  /// Get all positive counters.
  ///
  /// Returns a read-only map of node IDs to their positive counter values.
  Map<String, int> get positiveCounters => Map.unmodifiable(_pCounters);

  /// Get all negative counters.
  ///
  /// Returns a read-only map of node IDs to their negative counter values.
  Map<String, int> get negativeCounters => Map.unmodifiable(_nCounters);

  /// Get the total positive value across all nodes.
  int get totalPositive {
    return _pCounters.values.fold(0, (sum, counter) => sum + counter);
  }

  /// Get the total negative value across all nodes.
  int get totalNegative {
    return _nCounters.values.fold(0, (sum, counter) => sum + counter);
  }

  /// Get the list of nodes that have modified this counter.
  List<String> get nodes {
    final allNodes = <String>{..._pCounters.keys, ..._nCounters.keys};
    return allNodes.toList();
  }

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
  /// Throws [ArgumentError] if amount is negative or zero.
  void increment(String nodeId, [int amount = 1]) {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Amount must be positive');
    }

    _pCounters[nodeId] = (_pCounters[nodeId] ?? 0) + amount;
  }

  /// Decrement the counter for a specific node.
  ///
  /// This is typically called internally by the CRDT manager when applying
  /// operations. Direct calls should be avoided in favor of using the
  /// manager's performOperation method.
  ///
  /// Parameters:
  /// - [nodeId]: The node performing the decrement
  /// - [amount]: The amount to decrement by (must be positive)
  ///
  /// Throws [ArgumentError] if amount is negative or zero.
  void decrement(String nodeId, [int amount = 1]) {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Amount must be positive');
    }

    _nCounters[nodeId] = (_nCounters[nodeId] ?? 0) + amount;
  }

  @override
  void applyOperation(CRDTOperation operation) {
    final amount = operation.data['amount'] as int? ?? 1;

    switch (operation.operation) {
      case 'increment':
        increment(operation.nodeId, amount);
        break;
      case 'decrement':
        decrement(operation.nodeId, amount);
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
    'pCounters': Map<String, int>.from(_pCounters),
    'nCounters': Map<String, int>.from(_nCounters),
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

    final otherPCounters =
        otherState['pCounters'] as Map<String, dynamic>? ?? {};
    final otherNCounters =
        otherState['nCounters'] as Map<String, dynamic>? ?? {};

    // Merge positive counters (take maximum)
    for (final entry in otherPCounters.entries) {
      final nodeId = entry.key;
      final otherValue = entry.value as int;
      final currentValue = _pCounters[nodeId] ?? 0;
      _pCounters[nodeId] = math.max(currentValue, otherValue);
    }

    // Merge negative counters (take maximum)
    for (final entry in otherNCounters.entries) {
      final nodeId = entry.key;
      final otherValue = entry.value as int;
      final currentValue = _nCounters[nodeId] ?? 0;
      _nCounters[nodeId] = math.max(currentValue, otherValue);
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
    final copy = PNCounter(id);
    copy._pCounters.addAll(_pCounters);
    copy._nCounters.addAll(_nCounters);
    return copy;
  }

  @override
  void reset() {
    _pCounters.clear();
    _nCounters.clear();
  }

  @override
  void validate() {
    // Ensure all counter values are non-negative
    for (final entry in _pCounters.entries) {
      if (entry.value < 0) {
        throw CRDTException(
          'Positive counter for node ${entry.key} has negative value: ${entry.value}',
          crdtId: id,
        );
      }
    }

    for (final entry in _nCounters.entries) {
      if (entry.value < 0) {
        throw CRDTException(
          'Negative counter for node ${entry.key} has negative value: ${entry.value}',
          crdtId: id,
        );
      }
    }
  }

  /// Create a new PN-Counter from a saved state.
  ///
  /// This factory constructor recreates a PN-Counter from previously saved state,
  /// typically loaded from persistent storage.
  ///
  /// Parameters:
  /// - [state]: The state map returned by [getState]
  ///
  /// Throws [CRDTException] if the state format is invalid.
  factory PNCounter.fromState(Map<String, dynamic> state) {
    if (state['type'] != 'PNCounter') {
      throw CRDTException('Invalid state type: ${state['type']}');
    }

    final id = state['id'] as String;
    final counter = PNCounter(id);

    final pCounters = state['pCounters'] as Map<String, dynamic>? ?? {};
    final nCounters = state['nCounters'] as Map<String, dynamic>? ?? {};

    // Restore positive counters
    for (final entry in pCounters.entries) {
      final nodeId = entry.key;
      final value = entry.value as int;
      if (value < 0) {
        throw CRDTException(
          'Invalid positive counter value for node $nodeId: $value',
          crdtId: id,
        );
      }
      counter._pCounters[nodeId] = value;
    }

    // Restore negative counters
    for (final entry in nCounters.entries) {
      final nodeId = entry.key;
      final value = entry.value as int;
      if (value < 0) {
        throw CRDTException(
          'Invalid negative counter value for node $nodeId: $value',
          crdtId: id,
        );
      }
      counter._nCounters[nodeId] = value;
    }

    return counter;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PNCounter) return false;
    return super == other;
  }

  @override
  int get hashCode => super.hashCode;

  @override
  String toString() =>
      'PNCounter(id: $id, value: $value, positive: $totalPositive, '
      'negative: $totalNegative, nodes: ${nodes.length})';
}
