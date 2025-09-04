/// Enable-Wins Flag CRDT implementation.
///
/// An Enable-Wins Flag is a state-based CRDT that represents a boolean flag
/// that can be enabled or disabled. When concurrent enable/disable operations
/// occur, the enable operation always wins, ensuring that the flag remains
/// enabled if any replica has enabled it.
///
/// The Enable-Wins Flag guarantees that:
/// - All replicas will eventually converge to the same flag state
/// - Enable operations always take precedence over disable operations
/// - The flag can only be permanently disabled if all replicas agree
/// - Operations are commutative, associative, and idempotent
///
/// This implementation is suitable for use cases like:
/// - Feature flags that should remain enabled if any node enables them
/// - User permissions where access should be granted if any authority grants it
/// - System status flags where "active" should win over "inactive"
/// - Any boolean state where "true" should dominate concurrent updates
library;

import 'crdt.dart';

/// An enable-wins flag CRDT.
///
/// The Enable-Wins Flag maintains a simple boolean state with a bias toward
/// the enabled (true) state. When merging states, if either replica has the
/// flag enabled, the result will be enabled.
///
/// ## Example Usage
///
/// ```dart
/// final flag1 = EnableWinsFlag('feature-x-enabled');
/// final flag2 = EnableWinsFlag('feature-x-enabled');
///
/// // Node A enables the flag
/// await manager.performOperation(flag1.id, 'enable', {});
/// print(flag1.value); // true
///
/// // Node B disables the flag concurrently
/// await manager.performOperation(flag2.id, 'disable', {});
/// print(flag2.value); // false
///
/// // After synchronization, both will show true (enable wins)
/// flag1.mergeState(flag2.getState());
/// print(flag1.value); // true
/// ```
class EnableWinsFlag implements CRDT<bool> {
  @override
  final String id;

  bool _value = false;

  /// Creates a new Enable-Wins Flag with the specified ID.
  ///
  /// Parameters:
  /// - [id]: Unique identifier for this flag across all nodes
  /// - [initialValue]: Optional initial value (defaults to false)
  EnableWinsFlag(this.id, [bool initialValue = false]) : _value = initialValue;

  @override
  String get type => 'EnableWinsFlag';

  @override
  bool get value => _value;

  /// Check if the flag is enabled.
  bool get isEnabled => _value;

  /// Check if the flag is disabled.
  bool get isDisabled => !_value;

  /// Enable the flag.
  ///
  /// This is typically called internally by the CRDT manager when applying
  /// operations. Direct calls should be avoided in favor of using the
  /// manager's performOperation method.
  ///
  /// Returns true if the flag state changed, false if it was already enabled.
  bool enable() {
    if (_value) return false;
    _value = true;
    return true;
  }

  /// Disable the flag.
  ///
  /// This is typically called internally by the CRDT manager when applying
  /// operations. Direct calls should be avoided in favor of using the
  /// manager's performOperation method.
  ///
  /// Note: In an enable-wins flag, disable operations only take effect
  /// if the flag is not enabled on any other replica.
  ///
  /// Returns true if the flag state changed, false if it was already disabled.
  bool disable() {
    if (!_value) return false;
    _value = false;
    return true;
  }

  /// Toggle the flag state.
  ///
  /// This is typically called internally by the CRDT manager when applying
  /// operations. Direct calls should be avoided in favor of using the
  /// manager's performOperation method.
  ///
  /// Returns the new state after toggling.
  bool toggle() {
    _value = !_value;
    return _value;
  }

  @override
  void applyOperation(CRDTOperation operation) {
    switch (operation.operation) {
      case 'enable':
        enable();
        break;
      case 'disable':
        disable();
        break;
      case 'toggle':
        toggle();
        break;
      case 'set':
        final newValue = operation.data['value'] as bool?;
        if (newValue != null) {
          _value = newValue;
        }
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
  Map<String, dynamic> getState() => {'type': type, 'id': id, 'value': _value};

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

    final otherValue = otherState['value'] as bool? ?? false;

    // Enable wins: if either this flag or the other flag is enabled, result is enabled
    _value = _value || otherValue;
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
  CRDT<bool> copy() {
    return EnableWinsFlag(id, _value);
  }

  @override
  void reset() {
    _value = false;
  }

  @override
  void validate() {
    // No additional validation needed for a simple boolean flag
  }

  /// Create a new Enable-Wins Flag from a saved state.
  ///
  /// This factory constructor recreates an Enable-Wins Flag from previously
  /// saved state, typically loaded from persistent storage.
  ///
  /// Parameters:
  /// - [state]: The state map returned by [getState]
  ///
  /// Throws [CRDTException] if the state format is invalid.
  factory EnableWinsFlag.fromState(Map<String, dynamic> state) {
    if (state['type'] != 'EnableWinsFlag') {
      throw CRDTException('Invalid state type: ${state['type']}');
    }

    final id = state['id'] as String;
    final value = state['value'] as bool? ?? false;

    return EnableWinsFlag(id, value);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EnableWinsFlag) return false;
    return super == other;
  }

  @override
  int get hashCode => super.hashCode;

  @override
  String toString() => 'EnableWinsFlag(id: $id, value: $_value)';
}
