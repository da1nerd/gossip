/// Multi-Value Register CRDT implementation.
///
/// An MV-Register (Multi-Value Register) is a state-based CRDT that represents
/// a single value that can be updated, but preserves all concurrent updates
/// instead of resolving conflicts. When concurrent updates occur, the register
/// maintains all conflicting values until they are resolved by subsequent updates.
///
/// The MV-Register guarantees that:
/// - All replicas will eventually converge to the same set of values
/// - Concurrent updates are preserved (not lost)
/// - Operations are commutative, associative, and idempotent
///
/// This implementation is suitable for use cases like:
/// - User profile information with conflict detection
/// - Configuration values that need manual conflict resolution
/// - Any single value where concurrent updates should be preserved
/// - Building blocks for more complex conflict resolution strategies
library;

import 'crdt.dart';

/// A multi-value register CRDT that preserves concurrent updates.
///
/// The MV-Register stores multiple values along with their vector clocks to
/// track causality. When values are concurrent (neither causally dominates
/// the other), both are preserved. When one value causally dominates another,
/// only the dominating value is kept.
///
/// ## Example Usage
///
/// ```dart
/// final register1 = MVRegister<String>('user-status');
/// final register2 = MVRegister<String>('user-status');
///
/// // Node A sets status
/// await manager.performOperation(register1.id, 'set', {
///   'value': 'online',
///   'vectorClock': {'nodeA': 1},
/// });
///
/// // Node B sets status concurrently (same vector clock context)
/// await manager.performOperation(register2.id, 'set', {
///   'value': 'busy',
///   'vectorClock': {'nodeB': 1},
/// });
///
/// // After synchronization, both values are preserved
/// register1.mergeState(register2.getState());
/// print(register1.values); // ['online', 'busy'] - both values preserved
/// print(register1.hasConflict); // true - indicates concurrent updates
/// ```
class MVRegister<T> implements CRDT<Set<T>> {
  @override
  final String id;

  // Map from values to their vector clocks
  final Map<T, Map<String, int>> _valueClocks = {};

  // Internal vector clock for this register
  final Map<String, int> _vectorClock = {};

  /// Creates a new MV-Register with the specified ID.
  ///
  /// Parameters:
  /// - [id]: Unique identifier for this register across all nodes
  /// - [initialValue]: Optional initial value with initial vector clock
  MVRegister(this.id, [T? initialValue]) {
    if (initialValue != null) {
      _valueClocks[initialValue] = <String, int>{};
    }
  }

  @override
  String get type => 'MVRegister';

  @override
  Set<T> get value => Set<T>.unmodifiable(_valueClocks.keys);

  /// Get all values in the register.
  ///
  /// When there are no conflicts, this will contain a single value.
  /// When there are concurrent updates, this will contain multiple values.
  Set<T> get values => value;

  /// Get the single value if there's no conflict.
  ///
  /// Returns null if there are multiple concurrent values or no value at all.
  T? get singleValue {
    if (_valueClocks.length == 1) {
      return _valueClocks.keys.first;
    }
    return null;
  }

  /// Check if there are conflicting concurrent values.
  bool get hasConflict => _valueClocks.length > 1;

  /// Check if the register has any value.
  bool get hasValue => _valueClocks.isNotEmpty;

  /// Check if the register is empty (no values set).
  bool get isEmpty => _valueClocks.isEmpty;

  /// Get the number of concurrent values.
  int get valueCount => _valueClocks.length;

  /// Get the vector clock for a specific value.
  ///
  /// Returns null if the value is not in the register.
  Map<String, int>? getVectorClockFor(T value) {
    final clock = _valueClocks[value];
    return clock != null ? Map<String, int>.from(clock) : null;
  }

  /// Check if a specific value is present in the register.
  bool containsValue(T value) => _valueClocks.containsKey(value);

  /// Set a new value in the register with the given vector clock.
  ///
  /// This is typically called internally by the CRDT manager when applying
  /// operations. Direct calls should be avoided in favor of using the
  /// manager's performOperation method.
  ///
  /// Parameters:
  /// - [newValue]: The new value to set
  /// - [vectorClock]: The vector clock for this update
  ///
  /// Returns true if the value was added/updated, false if it was dominated
  /// by existing values.
  bool set(T newValue, Map<String, int> vectorClock) {
    // Remove any values that are dominated by the new value
    final toRemove = <T>[];
    for (final entry in _valueClocks.entries) {
      final existingValue = entry.key;
      final existingClock = entry.value;

      if (_clockDominates(vectorClock, existingClock)) {
        toRemove.add(existingValue);
      } else if (_clockDominates(existingClock, vectorClock)) {
        // The new value is dominated by an existing value, ignore it
        return false;
      }
    }

    // Remove dominated values
    for (final value in toRemove) {
      _valueClocks.remove(value);
    }

    // Add the new value
    _valueClocks[newValue] = Map<String, int>.from(vectorClock);
    return true;
  }

  /// Remove a specific value from the register.
  ///
  /// This removes the value regardless of its vector clock. Use with caution
  /// as this can lead to inconsistencies if not properly coordinated.
  bool remove(T value) {
    return _valueClocks.remove(value) != null;
  }

  /// Clear all values from the register.
  void clear() {
    _valueClocks.clear();
  }

  @override
  void applyOperation(CRDTOperation operation) {
    switch (operation.operation) {
      case 'set':
        final newValue = operation.data['value'] as T?;
        final vectorClockData =
            operation.data['vectorClock'] as Map<String, dynamic>?;

        if (newValue != null && vectorClockData != null) {
          final vectorClock = vectorClockData.cast<String, int>();
          set(newValue, vectorClock);
        }
        break;
      case 'remove':
        final value = operation.data['value'] as T?;
        if (value != null) {
          remove(value);
        }
        break;
      case 'clear':
        clear();
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
        'valueClocks': _valueClocks.map(
          (value, clock) => MapEntry(_serializeValue(value), clock),
        ),
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

    final otherValueClocks =
        otherState['valueClocks'] as Map<String, dynamic>? ?? {};

    for (final entry in otherValueClocks.entries) {
      final valueStr = entry.key;
      final otherClock =
          (entry.value as Map<String, dynamic>).cast<String, int>();
      final value = _deserializeValue(valueStr);

      set(value, otherClock);
    }
  }

  @override
  CRDTOperation createOperation(
    String operationType,
    Map<String, dynamic> data, {
    String? nodeId,
    DateTime? timestamp,
  }) {
    final operationData = Map<String, dynamic>.from(data);

    // For set operations, ensure vector clock is provided
    if (operationType == 'set' && !operationData.containsKey('vectorClock')) {
      // Create a simple vector clock with just this node
      final currentNodeId = nodeId ?? '';
      if (currentNodeId.isNotEmpty) {
        operationData['vectorClock'] = {currentNodeId: 1};
      }
    }

    return CRDTOperation.withId(
      crdtId: id,
      operation: operationType,
      data: operationData,
      nodeId: nodeId ?? '',
      timestamp: timestamp ?? DateTime.now(),
    );
  }

  @override
  CRDT<Set<T>> copy() {
    final copy = MVRegister<T>(id);

    // Deep copy value clocks
    for (final entry in _valueClocks.entries) {
      copy._valueClocks[entry.key] = Map<String, int>.from(entry.value);
    }

    // Copy vector clock
    copy._vectorClock.addAll(_vectorClock);

    return copy;
  }

  @override
  void reset() {
    _valueClocks.clear();
    _vectorClock.clear();
  }

  @override
  void validate() {
    // Validate that no value dominates another
    final values = _valueClocks.keys.toList();
    for (int i = 0; i < values.length; i++) {
      for (int j = i + 1; j < values.length; j++) {
        final clock1 = _valueClocks[values[i]]!;
        final clock2 = _valueClocks[values[j]]!;

        if (_clockDominates(clock1, clock2) ||
            _clockDominates(clock2, clock1)) {
          throw CRDTException(
            'Register contains dominated values: ${values[i]} and ${values[j]}',
            crdtId: id,
          );
        }
      }
    }
  }

  /// Check if one vector clock dominates another.
  ///
  /// Clock A dominates Clock B if A >= B for all nodes and A > B for at least one node.
  bool _clockDominates(Map<String, int> clockA, Map<String, int> clockB) {
    bool isGreaterOrEqual = true;
    bool isStrictlyGreater = false;

    final allNodes = <String>{...clockA.keys, ...clockB.keys};

    for (final node in allNodes) {
      final valueA = clockA[node] ?? 0;
      final valueB = clockB[node] ?? 0;

      if (valueA < valueB) {
        isGreaterOrEqual = false;
        break;
      } else if (valueA > valueB) {
        isStrictlyGreater = true;
      }
    }

    return isGreaterOrEqual && isStrictlyGreater;
  }

  /// Check if two vector clocks are concurrent.
  bool _clocksConcurrent(Map<String, int> clockA, Map<String, int> clockB) {
    return !_clockDominates(clockA, clockB) && !_clockDominates(clockB, clockA);
  }

  /// Serialize a value to a string for state storage.
  String _serializeValue(T value) {
    if (value is String) return value;
    if (value is num) return value.toString();
    if (value is bool) return value.toString();
    // For complex types, use toString() and let deserialization handle it
    return value.toString();
  }

  /// Deserialize a value from a string.
  T _deserializeValue(String valueStr) {
    // For basic types, try to parse appropriately
    if (T == String) return valueStr as T;
    if (T == int) return int.parse(valueStr) as T;
    if (T == double) return double.parse(valueStr) as T;
    if (T == bool) return (valueStr == 'true') as T;

    // For complex types, this is a limitation - in practice you'd need
    // proper serialization/deserialization for complex types
    return valueStr as T;
  }

  /// Get all values that are concurrent with each other.
  ///
  /// This groups values by their causal relationships. Values in the same
  /// group are concurrent with each other.
  List<Set<T>> getConcurrentGroups() {
    final groups = <Set<T>>[];
    final processed = <T>{};

    for (final value1 in _valueClocks.keys) {
      if (processed.contains(value1)) continue;

      final group = <T>{value1};
      processed.add(value1);

      for (final value2 in _valueClocks.keys) {
        if (processed.contains(value2)) continue;

        final clock1 = _valueClocks[value1]!;
        final clock2 = _valueClocks[value2]!;

        if (_clocksConcurrent(clock1, clock2)) {
          group.add(value2);
          processed.add(value2);
        }
      }

      groups.add(group);
    }

    return groups;
  }

  /// Resolve conflicts by selecting a single value using a resolver function.
  ///
  /// This creates a new register with only the resolved value, using a vector
  /// clock that dominates all the conflicting values.
  ///
  /// Parameters:
  /// - [resolver]: Function to select which value to keep from concurrent values
  /// - [nodeId]: The node ID for the resolution operation
  ///
  /// Returns a new MVRegister with the resolved value.
  MVRegister<T> resolve(
    T Function(Set<T> conflictingValues) resolver,
    String nodeId,
  ) {
    if (!hasConflict) {
      return copy() as MVRegister<T>;
    }

    final resolvedValue = resolver(values);
    final resolved = MVRegister<T>(id);

    // Create a vector clock that dominates all existing clocks
    final resolutionClock = <String, int>{};
    for (final clock in _valueClocks.values) {
      for (final entry in clock.entries) {
        resolutionClock[entry.key] =
            (resolutionClock[entry.key] ?? 0) > entry.value
                ? resolutionClock[entry.key]!
                : entry.value;
      }
    }

    // Increment the resolver's clock
    resolutionClock[nodeId] = (resolutionClock[nodeId] ?? 0) + 1;

    resolved.set(resolvedValue, resolutionClock);
    return resolved;
  }

  /// Create a new MV-Register from a saved state.
  ///
  /// This factory constructor recreates an MV-Register from previously saved state,
  /// typically loaded from persistent storage.
  ///
  /// Parameters:
  /// - [state]: The state map returned by [getState]
  ///
  /// Throws [CRDTException] if the state format is invalid.
  static MVRegister<T> fromState<T>(Map<String, dynamic> state) {
    if (state['type'] != 'MVRegister') {
      throw CRDTException('Invalid state type: ${state['type']}');
    }

    final id = state['id'] as String;
    final register = MVRegister<T>(id);

    final valueClocks = state['valueClocks'] as Map<String, dynamic>? ?? {};

    for (final entry in valueClocks.entries) {
      final valueStr = entry.key;
      final clock = (entry.value as Map<String, dynamic>).cast<String, int>();
      final value = register._deserializeValue(valueStr);

      register._valueClocks[value] = clock;
    }

    return register;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MVRegister<T>) return false;
    return super == other;
  }

  @override
  int get hashCode => super.hashCode;

  @override
  String toString() => 'MVRegister<$T>(id: $id, values: $valueCount, '
      'hasConflict: $hasConflict, values: $values)';
}
