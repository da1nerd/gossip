/// Last-Writer-Wins Map CRDT implementation.
///
/// An LWW-Map (Last-Writer-Wins Map) is a state-based CRDT that represents a map
/// where keys can be added, updated, and removed, with conflicts resolved using
/// timestamps and node IDs. When concurrent updates occur, the operation with
/// the latest timestamp wins (or the lexicographically larger node ID in case
/// of timestamp ties).
///
/// The LWW-Map guarantees that:
/// - All replicas will eventually converge to the same map
/// - Keys can be added, updated, and removed
/// - Concurrent operations are resolved deterministically using timestamps
/// - Operations are commutative, associative, and idempotent
///
/// This implementation is suitable for use cases like:
/// - Configuration management
/// - User preferences and settings
/// - Metadata storage
/// - Any map where latest update should win conflicts
library;

import 'dart:convert';
import 'crdt.dart';

/// A last-writer-wins map CRDT.
///
/// The LWW-Map stores key-value pairs along with timestamps and node IDs
/// for conflict resolution. Each key maintains separate timestamps for
/// addition and removal operations. A key is present in the map if its
/// addition timestamp is greater than its removal timestamp.
///
/// ## Example Usage
///
/// ```dart
/// final map1 = LWWMap<String, String>('user-settings');
/// final map2 = LWWMap<String, String>('user-settings');
///
/// // Node A sets values
/// await manager.performOperation(map1.id, 'put', {
///   'key': 'theme',
///   'value': 'dark',
///   'timestamp': DateTime.now().millisecondsSinceEpoch,
/// });
///
/// // Node B updates the same key later
/// await manager.performOperation(map2.id, 'put', {
///   'key': 'theme',
///   'value': 'light',
///   'timestamp': DateTime.now().millisecondsSinceEpoch + 1000,
/// });
///
/// // After synchronization, both will show 'light' (latest timestamp wins)
/// map1.mergeState(map2.getState());
/// print(map1['theme']); // 'light'
/// ```
class LWWMap<K, V> implements CRDT<Map<K, V>> {
  @override
  final String id;

  // Map from keys to their values
  final Map<K, V> _values = {};

  // Map from keys to their addition timestamps and node IDs
  final Map<K, _TimestampEntry> _addTimestamps = {};

  // Map from keys to their removal timestamps and node IDs
  final Map<K, _TimestampEntry> _removeTimestamps = {};

  /// Creates a new LWW-Map with the specified ID.
  ///
  /// Parameters:
  /// - [id]: Unique identifier for this map across all nodes
  LWWMap(this.id);

  @override
  String get type => 'LWWMap';

  @override
  Map<K, V> get value {
    final result = <K, V>{};

    for (final key in _values.keys) {
      if (_isKeyPresent(key)) {
        result[key] = _values[key]!;
      }
    }

    return Map<K, V>.unmodifiable(result);
  }

  /// Check if the map contains a specific key.
  ///
  /// A key is present if its addition timestamp is greater than its removal timestamp.
  ///
  /// Parameters:
  /// - [key]: The key to check for
  bool containsKey(K key) => _isKeyPresent(key);

  /// Get the value for a specific key.
  ///
  /// Returns null if the key is not present in the map.
  V? operator [](K key) {
    if (!_isKeyPresent(key)) return null;
    return _values[key];
  }

  /// Get all keys in the map.
  Set<K> get keys => value.keys.toSet();

  /// Get all values in the map.
  Iterable<V> get values => value.values;

  /// Get all entries in the map.
  Iterable<MapEntry<K, V>> get entries => value.entries;

  /// Get the number of keys in the map.
  int get length => value.length;

  /// Check if the map is empty.
  bool get isEmpty => value.isEmpty;

  /// Check if the map is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Get the addition timestamp for a key.
  ///
  /// Returns null if the key has never been added.
  int? getAddTimestamp(K key) => _addTimestamps[key]?.timestamp;

  /// Get the removal timestamp for a key.
  ///
  /// Returns null if the key has never been removed.
  int? getRemoveTimestamp(K key) => _removeTimestamps[key]?.timestamp;

  /// Get the node ID that last added a key.
  String? getAddNodeId(K key) => _addTimestamps[key]?.nodeId;

  /// Get the node ID that last removed a key.
  String? getRemoveNodeId(K key) => _removeTimestamps[key]?.nodeId;

  /// Put a key-value pair in the map.
  ///
  /// This is typically called internally by the CRDT manager when applying
  /// operations. Direct calls should be avoided in favor of using the
  /// manager's performOperation method.
  ///
  /// Parameters:
  /// - [key]: The key to add or update
  /// - [value]: The value to associate with the key
  /// - [timestamp]: The timestamp of this operation
  /// - [nodeId]: The node performing the operation
  ///
  /// Returns true if the operation was applied, false if it was ignored due
  /// to an older timestamp.
  bool put(K key, V value, int timestamp, String nodeId) {
    final currentAdd = _addTimestamps[key];

    if (_shouldUpdate(currentAdd, timestamp, nodeId)) {
      _values[key] = value;
      _addTimestamps[key] = _TimestampEntry(timestamp, nodeId);
      return true;
    }

    return false;
  }

  /// Remove a key from the map.
  ///
  /// This is typically called internally by the CRDT manager when applying
  /// operations. Direct calls should be avoided in favor of using the
  /// manager's performOperation method.
  ///
  /// Parameters:
  /// - [key]: The key to remove
  /// - [timestamp]: The timestamp of this operation
  /// - [nodeId]: The node performing the operation
  ///
  /// Returns true if the operation was applied, false if it was ignored due
  /// to an older timestamp.
  bool remove(K key, int timestamp, String nodeId) {
    final currentRemove = _removeTimestamps[key];

    if (_shouldUpdate(currentRemove, timestamp, nodeId)) {
      _removeTimestamps[key] = _TimestampEntry(timestamp, nodeId);
      return true;
    }

    return false;
  }

  /// Clear all entries from the map.
  ///
  /// This removes all keys by setting their removal timestamps to the given timestamp.
  ///
  /// Parameters:
  /// - [timestamp]: The timestamp of this operation
  /// - [nodeId]: The node performing the operation
  void clear(int timestamp, String nodeId) {
    for (final key in _values.keys.toList()) {
      remove(key, timestamp, nodeId);
    }
  }

  @override
  void applyOperation(CRDTOperation operation) {
    final timestamp = operation.data['timestamp'] as int? ??
        operation.timestamp.millisecondsSinceEpoch;

    switch (operation.operation) {
      case 'put':
        final key = operation.data['key'];
        final value = operation.data['value'];
        if (key != null && value != null) {
          put(key as K, value as V, timestamp, operation.nodeId);
        }
        break;

      case 'remove':
        final key = operation.data['key'];
        if (key != null) {
          remove(key as K, timestamp, operation.nodeId);
        }
        break;

      case 'clear':
        clear(timestamp, operation.nodeId);
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
        'values': _values.map(
          (key, value) => MapEntry(_serializeKey(key), _serializeValue(value)),
        ),
        'addTimestamps': _addTimestamps.map(
          (key, entry) => MapEntry(_serializeKey(key), {
            'timestamp': entry.timestamp,
            'nodeId': entry.nodeId,
          }),
        ),
        'removeTimestamps': _removeTimestamps.map(
          (key, entry) => MapEntry(_serializeKey(key), {
            'timestamp': entry.timestamp,
            'nodeId': entry.nodeId,
          }),
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

    final otherValues = otherState['values'] as Map<String, dynamic>? ?? {};
    final otherAddTimestamps =
        otherState['addTimestamps'] as Map<String, dynamic>? ?? {};
    final otherRemoveTimestamps =
        otherState['removeTimestamps'] as Map<String, dynamic>? ?? {};

    // Merge values and add timestamps
    for (final entry in otherValues.entries) {
      final keyStr = entry.key;
      final valueData = entry.value;
      final key = _deserializeKey(keyStr);
      final value = _deserializeValue(valueData);

      final addData = otherAddTimestamps[keyStr] as Map<String, dynamic>?;
      if (addData != null) {
        final timestamp = addData['timestamp'] as int;
        final nodeId = addData['nodeId'] as String;
        put(key, value, timestamp, nodeId);
      }
    }

    // Merge remove timestamps
    for (final entry in otherRemoveTimestamps.entries) {
      final keyStr = entry.key;
      final removeData = entry.value as Map<String, dynamic>;
      final key = _deserializeKey(keyStr);
      final timestamp = removeData['timestamp'] as int;
      final nodeId = removeData['nodeId'] as String;

      remove(key, timestamp, nodeId);
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
  CRDT<Map<K, V>> copy() {
    final copy = LWWMap<K, V>(id);

    // Copy values
    copy._values.addAll(_values);

    // Copy timestamps
    for (final entry in _addTimestamps.entries) {
      copy._addTimestamps[entry.key] = _TimestampEntry(
        entry.value.timestamp,
        entry.value.nodeId,
      );
    }

    for (final entry in _removeTimestamps.entries) {
      copy._removeTimestamps[entry.key] = _TimestampEntry(
        entry.value.timestamp,
        entry.value.nodeId,
      );
    }

    return copy;
  }

  @override
  void reset() {
    _values.clear();
    _addTimestamps.clear();
    _removeTimestamps.clear();
  }

  @override
  void validate() {
    // Validate that all values have corresponding add timestamps
    for (final key in _values.keys) {
      if (!_addTimestamps.containsKey(key)) {
        throw CRDTException(
          'Value exists for key $key but no add timestamp found',
          crdtId: id,
        );
      }
    }

    // Validate that all add timestamps have non-negative values
    for (final entry in _addTimestamps.entries) {
      if (entry.value.timestamp < 0) {
        throw CRDTException(
          'Negative add timestamp for key ${entry.key}: ${entry.value.timestamp}',
          crdtId: id,
        );
      }
    }

    // Validate that all remove timestamps have non-negative values
    for (final entry in _removeTimestamps.entries) {
      if (entry.value.timestamp < 0) {
        throw CRDTException(
          'Negative remove timestamp for key ${entry.key}: ${entry.value.timestamp}',
          crdtId: id,
        );
      }
    }
  }

  /// Check if a key is currently present in the map.
  bool _isKeyPresent(K key) {
    final addEntry = _addTimestamps[key];
    final removeEntry = _removeTimestamps[key];

    // Key is present if it has been added and either:
    // 1. Never been removed, or
    // 2. Add timestamp is greater than remove timestamp, or
    // 3. Timestamps are equal but add node ID is lexicographically larger
    if (addEntry == null) return false;

    if (removeEntry == null) return true;

    if (addEntry.timestamp > removeEntry.timestamp) return true;
    if (addEntry.timestamp < removeEntry.timestamp) return false;

    // Timestamp tie: lexicographically larger node ID wins for adds
    return addEntry.nodeId.compareTo(removeEntry.nodeId) > 0;
  }

  /// Determine if an update should be applied based on timestamp and node ID.
  bool _shouldUpdate(
    _TimestampEntry? current,
    int newTimestamp,
    String newNodeId,
  ) {
    if (current == null) return true;

    // Higher timestamp wins
    if (newTimestamp > current.timestamp) return true;
    if (newTimestamp < current.timestamp) return false;

    // Timestamp tie: lexicographically larger node ID wins
    return newNodeId.compareTo(current.nodeId) > 0;
  }

  /// Serialize a key to a string for state storage.
  String _serializeKey(K key) {
    if (key is String) return key;
    if (key is num) return key.toString();
    if (key is bool) return key.toString();
    return jsonEncode(key);
  }

  /// Deserialize a key from a string.
  K _deserializeKey(String keyStr) {
    // For basic types, try to parse appropriately
    if (K == String) return keyStr as K;
    if (K == int) return int.parse(keyStr) as K;
    if (K == double) return double.parse(keyStr) as K;
    if (K == bool) return (keyStr == 'true') as K;

    // For complex types, use JSON decoding
    try {
      return jsonDecode(keyStr) as K;
    } catch (e) {
      // Fallback: return as string and let the caller handle type conversion
      return keyStr as K;
    }
  }

  /// Serialize a value to a dynamic type for state storage.
  dynamic _serializeValue(V value) {
    if (value is String || value is num || value is bool) return value;
    return jsonEncode(value);
  }

  /// Deserialize a value from a dynamic type.
  V _deserializeValue(dynamic valueData) {
    // For basic types, return as-is if they match
    if (valueData is V) return valueData;

    // For basic types, try to parse appropriately
    if (V == String) return valueData.toString() as V;
    if (V == int && valueData is num) return valueData.toInt() as V;
    if (V == double && valueData is num) return valueData.toDouble() as V;
    if (V == bool) return (valueData.toString() == 'true') as V;

    // For complex types, try JSON decoding if it's a string
    if (valueData is String) {
      try {
        return jsonDecode(valueData) as V;
      } catch (e) {
        // Fallback: return as-is and let the caller handle type conversion
        return valueData as V;
      }
    }

    return valueData as V;
  }

  /// Get all keys that have been added (regardless of current presence).
  Set<K> get allAddedKeys => Set<K>.from(_addTimestamps.keys);

  /// Get all keys that have been removed (regardless of current presence).
  Set<K> get allRemovedKeys => Set<K>.from(_removeTimestamps.keys);

  /// Get all keys that have ever been in this map.
  Set<K> get allKeys => {...allAddedKeys, ...allRemovedKeys};

  /// Check if a key has ever been added to this map.
  bool wasAdded(K key) => _addTimestamps.containsKey(key);

  /// Check if a key has ever been removed from this map.
  bool wasRemoved(K key) => _removeTimestamps.containsKey(key);

  /// Compare the timestamps of two keys.
  ///
  /// Returns:
  /// - Negative if key1's last operation was before key2's
  /// - Zero if they have the same timestamp (should not happen in practice)
  /// - Positive if key1's last operation was after key2's
  int compareKeys(K key1, K key2) {
    final add1 = _addTimestamps[key1];
    final remove1 = _removeTimestamps[key1];
    final add2 = _addTimestamps[key2];
    final remove2 = _removeTimestamps[key2];

    // Find the latest timestamp for each key
    final latest1 = _getLatestTimestamp(add1, remove1);
    final latest2 = _getLatestTimestamp(add2, remove2);

    if (latest1 == null && latest2 == null) return 0;
    if (latest1 == null) return -1;
    if (latest2 == null) return 1;

    if (latest1.timestamp != latest2.timestamp) {
      return latest1.timestamp.compareTo(latest2.timestamp);
    }

    return latest1.nodeId.compareTo(latest2.nodeId);
  }

  /// Get the latest timestamp entry between add and remove for a key.
  _TimestampEntry? _getLatestTimestamp(
    _TimestampEntry? add,
    _TimestampEntry? remove,
  ) {
    if (add == null && remove == null) return null;
    if (add == null) return remove;
    if (remove == null) return add;

    if (add.timestamp > remove.timestamp) return add;
    if (add.timestamp < remove.timestamp) return remove;

    // Timestamp tie: return the one with larger node ID
    return add.nodeId.compareTo(remove.nodeId) > 0 ? add : remove;
  }

  /// Create a new LWW-Map from a saved state.
  ///
  /// This factory constructor recreates an LWW-Map from previously saved state,
  /// typically loaded from persistent storage.
  ///
  /// Parameters:
  /// - [state]: The state map returned by [getState]
  ///
  /// Throws [CRDTException] if the state format is invalid.
  static LWWMap<K, V> fromState<K, V>(Map<String, dynamic> state) {
    if (state['type'] != 'LWWMap') {
      throw CRDTException('Invalid state type: ${state['type']}');
    }

    final id = state['id'] as String;
    final map = LWWMap<K, V>(id);

    final values = state['values'] as Map<String, dynamic>? ?? {};
    final addTimestamps = state['addTimestamps'] as Map<String, dynamic>? ?? {};
    final removeTimestamps =
        state['removeTimestamps'] as Map<String, dynamic>? ?? {};

    // Restore values and add timestamps
    for (final entry in values.entries) {
      final keyStr = entry.key;
      final valueData = entry.value;
      final key = map._deserializeKey(keyStr);
      final value = map._deserializeValue(valueData);

      map._values[key] = value;

      final addData = addTimestamps[keyStr] as Map<String, dynamic>?;
      if (addData != null) {
        map._addTimestamps[key] = _TimestampEntry(
          addData['timestamp'] as int,
          addData['nodeId'] as String,
        );
      }
    }

    // Restore remove timestamps
    for (final entry in removeTimestamps.entries) {
      final keyStr = entry.key;
      final removeData = entry.value as Map<String, dynamic>;
      final key = map._deserializeKey(keyStr);

      map._removeTimestamps[key] = _TimestampEntry(
        removeData['timestamp'] as int,
        removeData['nodeId'] as String,
      );
    }

    return map;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LWWMap<K, V>) return false;
    return super == other;
  }

  @override
  int get hashCode => super.hashCode;

  @override
  String toString() => 'LWWMap<$K, $V>(id: $id, length: $length, '
      'totalKeys: ${allKeys.length})';
}

/// Internal class to store timestamp and node ID pairs.
class _TimestampEntry {
  final int timestamp;
  final String nodeId;

  const _TimestampEntry(this.timestamp, this.nodeId);

  @override
  String toString() => 'TimestampEntry(timestamp: $timestamp, nodeId: $nodeId)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _TimestampEntry) return false;
    return timestamp == other.timestamp && nodeId == other.nodeId;
  }

  @override
  int get hashCode => Object.hash(timestamp, nodeId);
}
