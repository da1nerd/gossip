/// Observed-Remove Map CRDT implementation.
///
/// An OR-Map (Observed-Remove Map) is a state-based CRDT that represents a map
/// where keys can be added and removed, with each value being another CRDT.
/// It solves the problem of concurrent adds and removes by keeping track of
/// unique tags for each key addition, allowing removes to only affect keys
/// they have observed.
///
/// The OR-Map guarantees that:
/// - All replicas will eventually converge to the same map
/// - Keys can be both added and removed
/// - Concurrent add/remove operations are resolved deterministically
/// - Values are CRDTs that can be independently updated
/// - Operations are commutative, associative, and idempotent
///
/// This implementation is suitable for use cases like:
/// - Distributed configuration management
/// - User permissions with dynamic properties
/// - Product catalogs with add/remove items
/// - Any map structure that needs both add and remove operations
library;

import 'dart:convert';
import 'dart:math' as math;

import 'crdt.dart';

/// An observed-remove map CRDT with CRDT values.
///
/// The OR-Map maintains two internal structures:
/// - Key-Tag pairs for additions (each key addition gets a unique tag)
/// - Set of observed tags for removals
/// - CRDT instances for each key's value
/// The current map is computed as keys whose tags haven't been removed.
///
/// ## Example Usage
///
/// ```dart
/// final map1 = ORMap<String, GCounter>('user-counters');
/// final map2 = ORMap<String, GCounter>('user-counters');
///
/// // Node A adds and removes keys
/// final counter1 = GCounter('user1-counter');
/// await manager.performOperation(map1.id, 'add', {
///   'key': 'user1',
///   'crdtType': 'GCounter',
///   'crdtId': 'user1-counter'
/// });
/// await manager.performOperation(map1.id, 'remove', {'key': 'user1'});
///
/// // Node B adds keys concurrently
/// final counter2 = GCounter('user1-counter-new');
/// await manager.performOperation(map2.id, 'add', {
///   'key': 'user1',
///   'crdtType': 'GCounter',
///   'crdtId': 'user1-counter-new'
/// });
///
/// // After synchronization, user1 key appears because node B's addition
/// // wasn't observed by node A's removal
/// ```
class ORMap<K, V extends CRDT> implements CRDT<Map<K, V>> {
  @override
  final String id;

  // Map from keys to sets of tags (unique identifiers for each addition)
  final Map<K, Set<String>> _keyTags = {};

  // Set of tags that have been removed
  final Set<String> _removedTags = {};

  // CRDT instances for each key
  final Map<K, V> _values = {};

  // Factory function to create CRDT values
  final V Function(String crdtId, String crdtType)? _crdtFactory;

  final math.Random _random = math.Random();

  /// Creates a new OR-Map with the specified ID.
  ///
  /// Parameters:
  /// - [id]: Unique identifier for this map across all nodes
  /// - [crdtFactory]: Optional factory function to create CRDT values
  ORMap(this.id, {V Function(String crdtId, String crdtType)? crdtFactory})
      : _crdtFactory = crdtFactory;

  @override
  String get type => 'ORMap';

  @override
  Map<K, V> get value {
    final result = <K, V>{};

    for (final entry in _keyTags.entries) {
      final key = entry.key;
      final tags = entry.value;

      // Key is in the map if it has at least one non-removed tag
      if (tags.any((tag) => !_removedTags.contains(tag))) {
        final crdt = _values[key];
        if (crdt != null) {
          result[key] = crdt;
        }
      }
    }

    return Map<K, V>.unmodifiable(result);
  }

  /// Check if the map contains a specific key.
  ///
  /// Parameters:
  /// - [key]: The key to check for
  bool containsKey(K key) {
    final tags = _keyTags[key];
    if (tags == null || tags.isEmpty) return false;

    // Key exists if it has at least one non-removed tag
    return tags.any((tag) => !_removedTags.contains(tag));
  }

  /// Get the CRDT value for a specific key.
  ///
  /// Returns null if the key is not present in the map.
  V? operator [](K key) {
    if (!containsKey(key)) return null;
    return _values[key];
  }

  /// Get all keys in the map.
  Set<K> get keys => value.keys.toSet();

  /// Get all CRDT values in the map.
  Iterable<V> get values => value.values;

  /// Get all entries in the map.
  Iterable<MapEntry<K, V>> get entries => value.entries;

  /// Get the number of keys in the map.
  int get length => value.length;

  /// Check if the map is empty.
  bool get isEmpty => value.isEmpty;

  /// Check if the map is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Get the total number of tags for a key (including removed ones).
  ///
  /// This is useful for debugging and understanding the internal state.
  int getTagCountFor(K key) {
    return _keyTags[key]?.length ?? 0;
  }

  /// Get the number of removed tags for a key.
  int getRemovedTagCountFor(K key) {
    final tags = _keyTags[key];
    if (tags == null) return 0;

    return tags.where((tag) => _removedTags.contains(tag)).length;
  }

  /// Add a key-value pair to the map with a new unique tag.
  ///
  /// This is typically called internally by the CRDT manager when applying
  /// operations. Direct calls should be avoided in favor of using the
  /// manager's performOperation method.
  ///
  /// Parameters:
  /// - [key]: The key to add to the map
  /// - [crdt]: The CRDT value to associate with the key
  /// - [nodeId]: The node performing the addition
  /// - [customTag]: Optional custom tag (for testing/debugging)
  ///
  /// Returns the tag used for this addition.
  String add(K key, V crdt, String nodeId, {String? customTag}) {
    final tag = customTag ?? _generateTag(nodeId);

    _keyTags.putIfAbsent(key, () => <String>{}).add(tag);
    _values[key] = crdt;

    return tag;
  }

  /// Remove a key from the map by marking all its observed tags as removed.
  ///
  /// This is typically called internally by the CRDT manager when applying
  /// operations. Direct calls should be avoided in favor of using the
  /// manager's performOperation method.
  ///
  /// Parameters:
  /// - [key]: The key to remove from the map
  ///
  /// Returns true if the key was present and removed, false otherwise.
  bool remove(K key) {
    final tags = _keyTags[key];
    if (tags == null || tags.isEmpty) return false;

    // Mark all currently observed tags as removed
    final tagsToRemove =
        tags.where((tag) => !_removedTags.contains(tag)).toSet();
    _removedTags.addAll(tagsToRemove);

    return tagsToRemove.isNotEmpty;
  }

  /// Remove a key by specific tag.
  ///
  /// This allows for more precise removal operations when the tag is known.
  ///
  /// Parameters:
  /// - [key]: The key to remove
  /// - [tag]: The specific tag to remove
  ///
  /// Returns true if the tag was found and removed, false otherwise.
  bool removeByTag(K key, String tag) {
    final tags = _keyTags[key];
    if (tags == null || !tags.contains(tag)) return false;

    _removedTags.add(tag);
    return true;
  }

  /// Update the CRDT value for an existing key.
  ///
  /// This applies an operation to the CRDT associated with the key.
  ///
  /// Parameters:
  /// - [key]: The key whose value to update
  /// - [operation]: The CRDT operation to apply
  ///
  /// Returns true if the key exists and was updated, false otherwise.
  bool updateValue(K key, CRDTOperation operation) {
    if (!containsKey(key)) return false;

    final crdt = _values[key];
    if (crdt != null) {
      crdt.applyOperation(operation);
      return true;
    }

    return false;
  }

  @override
  void applyOperation(CRDTOperation operation) {
    switch (operation.operation) {
      case 'add':
        final key = operation.data['key'];
        final crdtType = operation.data['crdtType'] as String?;
        final crdtId = operation.data['crdtId'] as String?;
        final tag = operation.data['tag'] as String?;

        if (key != null && crdtType != null && crdtId != null) {
          // Create CRDT value using factory if available
          V? crdt;
          if (_crdtFactory != null) {
            crdt = _crdtFactory!(crdtId, crdtType);
          } else {
            // Cannot create CRDT without factory - this is a limitation
            throw CRDTException(
              'Cannot add key $key: no CRDT factory provided',
              crdtId: id,
              operation: operation,
            );
          }

          add(key as K, crdt, operation.nodeId, customTag: tag);
        }
        break;

      case 'remove':
        final key = operation.data['key'];
        final tag = operation.data['tag'] as String?;

        if (key != null && tag != null) {
          removeByTag(key as K, tag);
        } else if (key != null) {
          remove(key as K);
        }
        break;

      case 'updateValue':
        final key = operation.data['key'];
        final valueOperation =
            operation.data['valueOperation'] as Map<String, dynamic>?;

        if (key != null && valueOperation != null) {
          final crdtOp = CRDTOperation.fromJson(valueOperation);
          updateValue(key as K, crdtOp);
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
  Map<String, dynamic> getState() => {
        'type': type,
        'id': id,
        'keyTags': _keyTags.map(
          (key, tags) => MapEntry(_serializeKey(key), tags.toList()),
        ),
        'removedTags': _removedTags.toList(),
        'values': _values.map(
          (key, crdt) => MapEntry(_serializeKey(key), crdt.getState()),
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

    final otherKeyTags = otherState['keyTags'] as Map<String, dynamic>? ?? {};
    final otherRemovedTags =
        (otherState['removedTags'] as List?)?.cast<String>() ?? [];
    final otherValues = otherState['values'] as Map<String, dynamic>? ?? {};

    // Merge key tags (union of all tags for each key)
    for (final entry in otherKeyTags.entries) {
      final keyStr = entry.key;
      final otherTags = (entry.value as List).cast<String>();
      final key = _deserializeKey(keyStr);

      _keyTags.putIfAbsent(key, () => <String>{}).addAll(otherTags);
    }

    // Merge removed tags (union of all removed tags)
    _removedTags.addAll(otherRemovedTags);

    // Merge CRDT values
    for (final entry in otherValues.entries) {
      final keyStr = entry.key;
      final otherCrdtState = entry.value as Map<String, dynamic>;
      final key = _deserializeKey(keyStr);

      final existingCrdt = _values[key];
      if (existingCrdt != null) {
        // Merge with existing CRDT
        existingCrdt.mergeState(otherCrdtState);
      } else if (_crdtFactory != null) {
        // Create new CRDT and merge state
        final crdtType = otherCrdtState['type'] as String;
        final crdtId = otherCrdtState['id'] as String;
        final newCrdt = _crdtFactory!(crdtId, crdtType);
        newCrdt.mergeState(otherCrdtState);
        _values[key] = newCrdt;
      }
      // If no factory, we can't create the CRDT - skip it
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

    // For add operations, generate a tag if not provided
    if (operationType == 'add' && !operationData.containsKey('tag')) {
      operationData['tag'] = _generateTag(nodeId ?? '');
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
    final copy = ORMap<K, V>(id, crdtFactory: _crdtFactory);

    // Deep copy key tags
    for (final entry in _keyTags.entries) {
      copy._keyTags[entry.key] = Set<String>.from(entry.value);
    }

    // Copy removed tags
    copy._removedTags.addAll(_removedTags);

    // Deep copy CRDT values
    for (final entry in _values.entries) {
      copy._values[entry.key] = entry.value.copy() as V;
    }

    return copy;
  }

  @override
  void reset() {
    _keyTags.clear();
    _removedTags.clear();
    _values.clear();
  }

  @override
  void validate() {
    // Validate that all keys in _values have corresponding tags
    for (final key in _values.keys) {
      if (!_keyTags.containsKey(key)) {
        throw CRDTException(
          'Value exists for key $key but no tags found',
          crdtId: id,
        );
      }
    }

    // Validate that all removed tags exist in some key's tag set
    final allTags = <String>{};
    for (final tags in _keyTags.values) {
      allTags.addAll(tags);
    }

    final orphanedRemovedTags = _removedTags.difference(allTags);
    if (orphanedRemovedTags.isNotEmpty) {
      throw CRDTException(
        'Removed tags exist without corresponding key tags: $orphanedRemovedTags',
        crdtId: id,
      );
    }

    // Validate all CRDT values
    for (final crdt in _values.values) {
      crdt.validate();
    }
  }

  /// Generate a unique tag for a key addition.
  String _generateTag(String nodeId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = _random.nextInt(999999).toString().padLeft(6, '0');
    return '${nodeId}_${timestamp}_$randomSuffix';
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

  /// Apply an operation to a specific key's CRDT value.
  ///
  /// This is a convenience method for updating CRDT values within the map.
  ///
  /// Parameters:
  /// - [key]: The key whose CRDT value to update
  /// - [operation]: The operation type
  /// - [data]: Operation-specific data
  /// - [nodeId]: The node performing the operation
  ///
  /// Returns true if the operation was applied, false if key doesn't exist.
  bool applyCRDTOperation(
    K key,
    String operation,
    Map<String, dynamic> data,
    String nodeId,
  ) {
    if (!containsKey(key)) return false;

    final crdt = _values[key];
    if (crdt != null) {
      final crdtOp = CRDTOperation.withId(
        crdtId: crdt.id,
        operation: operation,
        data: data,
        nodeId: nodeId,
        timestamp: DateTime.now(),
      );
      crdt.applyOperation(crdtOp);
      return true;
    }

    return false;
  }

  /// Get statistics about the map's internal structure.
  ORMapStats getStats() {
    final totalTags = _keyTags.values.fold(0, (sum, tags) => sum + tags.length);
    final activeTags = totalTags - _removedTags.length;

    return ORMapStats(
      totalKeys: _keyTags.length,
      activeKeys: value.length,
      totalTags: totalTags,
      removedTags: _removedTags.length,
      activeTags: activeTags,
      crdtTypes: _values.values.map((crdt) => crdt.type).toSet().toList(),
    );
  }

  /// Create a new OR-Map from a saved state.
  ///
  /// This factory constructor recreates an OR-Map from previously saved state,
  /// typically loaded from persistent storage. Note that a CRDT factory must
  /// be provided to recreate the CRDT values.
  ///
  /// Parameters:
  /// - [state]: The state map returned by [getState]
  /// - [crdtFactory]: Factory function to create CRDT values
  ///
  /// Throws [CRDTException] if the state format is invalid.
  static ORMap<K, V> fromState<K, V extends CRDT>(
    Map<String, dynamic> state,
    V Function(String crdtId, String crdtType) crdtFactory,
  ) {
    if (state['type'] != 'ORMap') {
      throw CRDTException('Invalid state type: ${state['type']}');
    }

    final id = state['id'] as String;
    final map = ORMap<K, V>(id, crdtFactory: crdtFactory);

    final keyTags = state['keyTags'] as Map<String, dynamic>? ?? {};
    final removedTags = (state['removedTags'] as List?)?.cast<String>() ?? [];
    final values = state['values'] as Map<String, dynamic>? ?? {};

    // Restore key tags
    for (final entry in keyTags.entries) {
      final keyStr = entry.key;
      final tags = (entry.value as List).cast<String>();
      final key = map._deserializeKey(keyStr);

      map._keyTags[key] = Set<String>.from(tags);
    }

    // Restore removed tags
    map._removedTags.addAll(removedTags);

    // Restore CRDT values
    for (final entry in values.entries) {
      final keyStr = entry.key;
      final crdtState = entry.value as Map<String, dynamic>;
      final key = map._deserializeKey(keyStr);

      final crdtType = crdtState['type'] as String;
      final crdtId = crdtState['id'] as String;
      final crdt = crdtFactory(crdtId, crdtType);
      crdt.mergeState(crdtState);

      map._values[key] = crdt;
    }

    return map;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ORMap<K, V>) return false;
    return super == other;
  }

  @override
  int get hashCode => super.hashCode;

  @override
  String toString() => 'ORMap<$K, $V>(id: $id, length: $length, '
      'totalTags: ${_keyTags.values.fold(0, (sum, tags) => sum + tags.length)}, '
      'removedTags: ${_removedTags.length})';
}

/// Statistics about an OR-Map's internal structure.
class ORMapStats {
  final int totalKeys;
  final int activeKeys;
  final int totalTags;
  final int removedTags;
  final int activeTags;
  final List<String> crdtTypes;

  const ORMapStats({
    required this.totalKeys,
    required this.activeKeys,
    required this.totalTags,
    required this.removedTags,
    required this.activeTags,
    required this.crdtTypes,
  });

  @override
  String toString() =>
      'ORMapStats(totalKeys: $totalKeys, activeKeys: $activeKeys, '
      'totalTags: $totalTags, removedTags: $removedTags, '
      'activeTags: $activeTags, crdtTypes: $crdtTypes)';
}
