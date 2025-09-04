/// Last-Writer-Wins Register CRDT implementation.
///
/// An LWW-Register (Last-Writer-Wins Register) is a state-based CRDT that
/// represents a single value that can be updated. When concurrent updates
/// occur, conflicts are resolved by selecting the value with the latest
/// timestamp (or using a deterministic tie-breaker like node ID).
///
/// The LWW-Register guarantees that:
/// - All replicas will eventually converge to the same value
/// - The most recent update (by timestamp) wins in case of conflicts
/// - Operations are commutative, associative, and idempotent
///
/// This implementation is suitable for use cases like:
/// - Configuration values
/// - User profile information
/// - Status indicators
/// - Any single value that needs distributed updates
library;

import 'crdt.dart';

/// A last-writer-wins register CRDT.
///
/// The LWW-Register stores a single value along with a timestamp and node ID
/// for conflict resolution. When merging states, the value with the highest
/// timestamp wins. In case of timestamp ties, the lexicographically larger
/// node ID wins to ensure deterministic resolution.
///
/// ## Example Usage
///
/// ```dart
/// final register1 = LWWRegister<String>('user-status');
/// final register2 = LWWRegister<String>('user-status');
///
/// // Node A sets status
/// await manager.performOperation(register1.id, 'set', {
///   'value': 'online',
///   'timestamp': DateTime.now().millisecondsSinceEpoch,
/// });
/// print(register1.value); // 'online'
///
/// // Node B sets status slightly later
/// await manager.performOperation(register2.id, 'set', {
///   'value': 'busy',
///   'timestamp': DateTime.now().millisecondsSinceEpoch + 1000,
/// });
/// print(register2.value); // 'busy'
///
/// // After synchronization, both will show 'busy' (latest timestamp wins)
/// register1.mergeState(register2.getState());
/// print(register1.value); // 'busy'
/// ```
class LWWRegister<T> implements CRDT<T?> {
  @override
  final String id;

  T? _value;
  int _timestamp = 0;
  String _nodeId = '';

  /// Creates a new LWW-Register with the specified ID.
  ///
  /// Parameters:
  /// - [id]: Unique identifier for this register across all nodes
  /// - [initialValue]: Optional initial value
  LWWRegister(this.id, [T? initialValue]) : _value = initialValue;

  @override
  String get type => 'LWWRegister';

  @override
  T? get value => _value;

  /// Get the timestamp of the current value.
  int get timestamp => _timestamp;

  /// Get the node ID that set the current value.
  String get nodeId => _nodeId;

  /// Check if the register has been set (has a value).
  bool get hasValue => _value != null || _timestamp > 0;

  /// Check if the register is empty (no value set).
  bool get isEmpty => !hasValue;

  /// Set a new value in the register.
  ///
  /// This is typically called internally by the CRDT manager when applying
  /// operations. Direct calls should be avoided in favor of using the
  /// manager's performOperation method.
  ///
  /// Parameters:
  /// - [newValue]: The new value to set
  /// - [timestamp]: The timestamp of this update
  /// - [nodeId]: The node ID performing the update
  ///
  /// Returns true if the value was updated, false if the update was ignored
  /// due to an older timestamp.
  bool set(T? newValue, int timestamp, String nodeId) {
    if (_shouldUpdate(timestamp, nodeId)) {
      _value = newValue;
      _timestamp = timestamp;
      _nodeId = nodeId;
      return true;
    }
    return false;
  }

  /// Determine if an update should be applied based on timestamp and node ID.
  bool _shouldUpdate(int newTimestamp, String newNodeId) {
    // No existing value, always accept
    if (_timestamp == 0) return true;

    // Higher timestamp wins
    if (newTimestamp > _timestamp) return true;
    if (newTimestamp < _timestamp) return false;

    // Timestamp tie: lexicographically larger node ID wins
    return newNodeId.compareTo(_nodeId) > 0;
  }

  @override
  void applyOperation(CRDTOperation operation) {
    switch (operation.operation) {
      case 'set':
        final newValue = operation.data['value'] as T?;
        final timestamp = operation.data['timestamp'] as int? ??
            operation.timestamp.millisecondsSinceEpoch;
        set(newValue, timestamp, operation.nodeId);
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
        'value': _value,
        'timestamp': _timestamp,
        'nodeId': _nodeId,
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

    final otherValue = otherState['value'] as T?;
    final otherTimestamp = otherState['timestamp'] as int? ?? 0;
    final otherNodeId = otherState['nodeId'] as String? ?? '';

    set(otherValue, otherTimestamp, otherNodeId);
  }

  @override
  CRDTOperation createOperation(
    String operationType,
    Map<String, dynamic> data, {
    String? nodeId,
    DateTime? timestamp,
  }) {
    final operationData = Map<String, dynamic>.from(data);

    // Ensure timestamp is included
    if (!operationData.containsKey('timestamp')) {
      operationData['timestamp'] =
          (timestamp ?? DateTime.now()).millisecondsSinceEpoch;
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
  CRDT<T?> copy() {
    final copy = LWWRegister<T>(id);
    copy._value = _value;
    copy._timestamp = _timestamp;
    copy._nodeId = _nodeId;
    return copy;
  }

  @override
  void reset() {
    _value = null;
    _timestamp = 0;
    _nodeId = '';
  }

  @override
  void validate() {
    // Validate that if we have a value, we also have a timestamp and node ID
    if (_timestamp > 0) {
      if (_nodeId.isEmpty) {
        throw CRDTException(
          'Register has timestamp but no node ID',
          crdtId: id,
        );
      }
    }

    // Validate timestamp is not negative
    if (_timestamp < 0) {
      throw CRDTException(
        'Register has negative timestamp: $_timestamp',
        crdtId: id,
      );
    }
  }

  /// Compare this register with another value based on timestamp and node ID.
  ///
  /// Returns:
  /// - Negative if this register is "older" than the comparison
  /// - Zero if they are equivalent
  /// - Positive if this register is "newer" than the comparison
  int compareWith(int otherTimestamp, String otherNodeId) {
    if (_timestamp != otherTimestamp) {
      return _timestamp.compareTo(otherTimestamp);
    }
    return _nodeId.compareTo(otherNodeId);
  }

  /// Check if this register's value is newer than another register's value.
  bool isNewerThan(LWWRegister<T> other) {
    return compareWith(other._timestamp, other._nodeId) > 0;
  }

  /// Check if this register's value is older than another register's value.
  bool isOlderThan(LWWRegister<T> other) {
    return compareWith(other._timestamp, other._nodeId) < 0;
  }

  /// Check if this register's value is concurrent with another register's value.
  ///
  /// Values are concurrent if they have the same timestamp but different node IDs.
  bool isConcurrentWith(LWWRegister<T> other) {
    return _timestamp == other._timestamp && _nodeId != other._nodeId;
  }

  /// Create a new LWW-Register from a saved state.
  ///
  /// This factory constructor recreates an LWW-Register from previously saved state,
  /// typically loaded from persistent storage.
  ///
  /// Parameters:
  /// - [state]: The state map returned by [getState]
  ///
  /// Throws [CRDTException] if the state format is invalid.
  static LWWRegister<T> fromState<T>(Map<String, dynamic> state) {
    if (state['type'] != 'LWWRegister') {
      throw CRDTException('Invalid state type: ${state['type']}');
    }

    final id = state['id'] as String;
    final register = LWWRegister<T>(id);

    register._value = state['value'] as T?;
    register._timestamp = state['timestamp'] as int? ?? 0;
    register._nodeId = state['nodeId'] as String? ?? '';

    // Validate the loaded state
    register.validate();

    return register;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LWWRegister<T>) return false;
    return super == other;
  }

  @override
  int get hashCode => super.hashCode;

  @override
  String toString() => 'LWWRegister<$T>(id: $id, value: $_value, '
      'timestamp: $_timestamp, nodeId: $_nodeId)';
}
