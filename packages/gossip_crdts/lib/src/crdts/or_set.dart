/// Observed-Remove Set CRDT implementation.
///
/// An OR-Set (Observed-Remove Set) is a state-based CRDT that represents a set
/// that supports both add and remove operations. It solves the problem of
/// concurrent adds and removes by keeping track of unique tags for each
/// addition, allowing removes to only affect elements they have observed.
///
/// The OR-Set guarantees that:
/// - All replicas will eventually converge to the same set
/// - Elements can be both added and removed
/// - Concurrent add/remove operations are resolved deterministically
/// - Operations are commutative, associative, and idempotent
///
/// This implementation is suitable for use cases like:
/// - Shopping carts with add/remove items
/// - User permissions (grant/revoke access)
/// - Dynamic configuration sets
/// - Any collection that needs both add and remove operations
library;

import 'dart:convert';
import 'dart:math' as math;

import 'crdt.dart';

/// An observed-remove set CRDT.
///
/// The OR-Set maintains two internal structures:
/// - Element-Tag pairs for additions (each add gets a unique tag)
/// - Set of observed tags for removals
/// The current set is computed as elements whose tags haven't been removed.
///
/// ## Example Usage
///
/// ```dart
/// final set1 = ORSet<String>('shopping-cart');
/// final set2 = ORSet<String>('shopping-cart');
///
/// // Node A adds and removes items
/// await manager.performOperation(set1.id, 'add', {'element': 'apple'});
/// await manager.performOperation(set1.id, 'add', {'element': 'banana'});
/// await manager.performOperation(set1.id, 'remove', {'element': 'apple'});
/// print(set1.value); // {'banana'}
///
/// // Node B adds items concurrently
/// await manager.performOperation(set2.id, 'add', {'element': 'apple'});
/// await manager.performOperation(set2.id, 'add', {'element': 'cherry'});
/// print(set2.value); // {'apple', 'cherry'}
///
/// // After synchronization
/// set1.mergeState(set2.getState());
/// print(set1.value); // {'apple', 'banana', 'cherry'}
/// // Note: apple appears because node B's addition wasn't observed by node A's removal
/// ```
class ORSet<T> implements CRDT<Set<T>> {
  @override
  final String id;

  // Map from elements to sets of tags (unique identifiers for each addition)
  final Map<T, Set<String>> _elementTags = {};

  // Set of tags that have been removed
  final Set<String> _removedTags = {};

  final math.Random _random = math.Random();

  /// Creates a new OR-Set with the specified ID.
  ///
  /// Parameters:
  /// - [id]: Unique identifier for this set across all nodes
  ORSet(this.id);

  @override
  String get type => 'ORSet';

  @override
  Set<T> get value {
    final result = <T>{};

    for (final entry in _elementTags.entries) {
      final element = entry.key;
      final tags = entry.value;

      // Element is in the set if it has at least one non-removed tag
      if (tags.any((tag) => !_removedTags.contains(tag))) {
        result.add(element);
      }
    }

    return Set<T>.unmodifiable(result);
  }

  /// Check if the set contains a specific element.
  ///
  /// Parameters:
  /// - [element]: The element to check for
  bool contains(T element) {
    final tags = _elementTags[element];
    if (tags == null || tags.isEmpty) return false;

    // Element exists if it has at least one non-removed tag
    return tags.any((tag) => !_removedTags.contains(tag));
  }

  /// Get the number of elements in the set.
  int get size => value.length;

  /// Check if the set is empty.
  bool get isEmpty => value.isEmpty;

  /// Check if the set is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Get all elements as a list.
  ///
  /// Note: The order of elements is not guaranteed to be consistent
  /// across different replicas.
  List<T> get elements => value.toList();

  /// Get the total number of tags for an element (including removed ones).
  ///
  /// This is useful for debugging and understanding the internal state.
  int getTagCountFor(T element) {
    return _elementTags[element]?.length ?? 0;
  }

  /// Get the number of removed tags for an element.
  int getRemovedTagCountFor(T element) {
    final tags = _elementTags[element];
    if (tags == null) return 0;

    return tags.where((tag) => _removedTags.contains(tag)).length;
  }

  /// Add an element to the set with a new unique tag.
  ///
  /// This is typically called internally by the CRDT manager when applying
  /// operations. Direct calls should be avoided in favor of using the
  /// manager's performOperation method.
  ///
  /// Parameters:
  /// - [element]: The element to add to the set
  /// - [nodeId]: The node performing the addition
  /// - [customTag]: Optional custom tag (for testing/debugging)
  ///
  /// Returns the tag used for this addition.
  String add(T element, String nodeId, {String? customTag}) {
    final tag = customTag ?? _generateTag(nodeId);

    _elementTags.putIfAbsent(element, () => <String>{}).add(tag);

    return tag;
  }

  /// Remove an element from the set by marking all its observed tags as removed.
  ///
  /// This is typically called internally by the CRDT manager when applying
  /// operations. Direct calls should be avoided in favor of using the
  /// manager's performOperation method.
  ///
  /// Parameters:
  /// - [element]: The element to remove from the set
  ///
  /// Returns true if the element was present and removed, false otherwise.
  bool remove(T element) {
    final tags = _elementTags[element];
    if (tags == null || tags.isEmpty) return false;

    // Mark all currently observed tags as removed
    final tagsToRemove = tags
        .where((tag) => !_removedTags.contains(tag))
        .toSet();
    _removedTags.addAll(tagsToRemove);

    return tagsToRemove.isNotEmpty;
  }

  /// Remove an element by specific tag.
  ///
  /// This allows for more precise removal operations when the tag is known.
  ///
  /// Parameters:
  /// - [element]: The element to remove
  /// - [tag]: The specific tag to remove
  ///
  /// Returns true if the tag was found and removed, false otherwise.
  bool removeByTag(T element, String tag) {
    final tags = _elementTags[element];
    if (tags == null || !tags.contains(tag)) return false;

    _removedTags.add(tag);
    return true;
  }

  @override
  void applyOperation(CRDTOperation operation) {
    switch (operation.operation) {
      case 'add':
        final element = operation.data['element'];
        final tag = operation.data['tag'] as String?;
        if (element != null) {
          add(element as T, operation.nodeId, customTag: tag);
        }
        break;
      case 'remove':
        final element = operation.data['element'];
        final tag = operation.data['tag'] as String?;
        if (element != null && tag != null) {
          removeByTag(element as T, tag);
        } else if (element != null) {
          remove(element as T);
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
    'elementTags': _elementTags.map(
      (element, tags) => MapEntry(_serializeElement(element), tags.toList()),
    ),
    'removedTags': _removedTags.toList(),
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

    final otherElementTags =
        otherState['elementTags'] as Map<String, dynamic>? ?? {};
    final otherRemovedTags =
        (otherState['removedTags'] as List?)?.cast<String>() ?? [];

    // Merge element tags (union of all tags for each element)
    for (final entry in otherElementTags.entries) {
      final elementStr = entry.key;
      final otherTags = (entry.value as List).cast<String>();
      final element = _deserializeElement(elementStr);

      _elementTags.putIfAbsent(element, () => <String>{}).addAll(otherTags);
    }

    // Merge removed tags (union of all removed tags)
    _removedTags.addAll(otherRemovedTags);
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
  CRDT<Set<T>> copy() {
    final copy = ORSet<T>(id);

    // Deep copy element tags
    for (final entry in _elementTags.entries) {
      copy._elementTags[entry.key] = Set<String>.from(entry.value);
    }

    // Copy removed tags
    copy._removedTags.addAll(_removedTags);

    return copy;
  }

  @override
  void reset() {
    _elementTags.clear();
    _removedTags.clear();
  }

  @override
  void validate() {
    // Validate that all removed tags exist in some element's tag set
    final allTags = <String>{};
    for (final tags in _elementTags.values) {
      allTags.addAll(tags);
    }

    final orphanedRemovedTags = _removedTags.difference(allTags);
    if (orphanedRemovedTags.isNotEmpty) {
      throw CRDTException(
        'Removed tags exist without corresponding element tags: $orphanedRemovedTags',
        crdtId: id,
      );
    }
  }

  /// Generate a unique tag for an element addition.
  String _generateTag(String nodeId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = _random.nextInt(999999).toString().padLeft(6, '0');
    return '${nodeId}_${timestamp}_$randomSuffix';
  }

  /// Serialize an element to a string for state storage.
  String _serializeElement(T element) {
    if (element is String) return element;
    if (element is num) return element.toString();
    if (element is bool) return element.toString();
    return jsonEncode(element);
  }

  /// Deserialize an element from a string.
  T _deserializeElement(String elementStr) {
    // For basic types, try to parse appropriately
    if (T == String) return elementStr as T;
    if (T == int) return int.parse(elementStr) as T;
    if (T == double) return double.parse(elementStr) as T;
    if (T == bool) return (elementStr == 'true') as T;

    // For complex types, use JSON decoding
    try {
      return jsonDecode(elementStr) as T;
    } catch (e) {
      // Fallback: return as string and let the caller handle type conversion
      return elementStr as T;
    }
  }

  /// Check if this set is a subset of another set.
  ///
  /// Parameters:
  /// - [other]: The other set to compare with
  bool isSubsetOf(Set<T> other) {
    return value.every((element) => other.contains(element));
  }

  /// Check if this set is a superset of another set.
  ///
  /// Parameters:
  /// - [other]: The other set to compare with
  bool isSupersetOf(Set<T> other) {
    return other.every((element) => contains(element));
  }

  /// Get the union of this set with another set.
  ///
  /// Parameters:
  /// - [other]: The other set to union with
  Set<T> union(Set<T> other) {
    return {...value, ...other};
  }

  /// Get the intersection of this set with another set.
  ///
  /// Parameters:
  /// - [other]: The other set to intersect with
  Set<T> intersection(Set<T> other) {
    return value.where((element) => other.contains(element)).toSet();
  }

  /// Get the difference of this set with another set.
  ///
  /// Returns elements that are in this set but not in the other set.
  ///
  /// Parameters:
  /// - [other]: The other set to compute difference with
  Set<T> difference(Set<T> other) {
    return value.where((element) => !other.contains(element)).toSet();
  }

  /// Create a new OR-Set from a saved state.
  ///
  /// This factory constructor recreates an OR-Set from previously saved state,
  /// typically loaded from persistent storage.
  ///
  /// Parameters:
  /// - [state]: The state map returned by [getState]
  ///
  /// Throws [CRDTException] if the state format is invalid.
  static ORSet<T> fromState<T>(Map<String, dynamic> state) {
    if (state['type'] != 'ORSet') {
      throw CRDTException('Invalid state type: ${state['type']}');
    }

    final id = state['id'] as String;
    final set = ORSet<T>(id);

    final elementTags = state['elementTags'] as Map<String, dynamic>? ?? {};
    final removedTags = (state['removedTags'] as List?)?.cast<String>() ?? [];

    // Restore element tags
    for (final entry in elementTags.entries) {
      final elementStr = entry.key;
      final tags = (entry.value as List).cast<String>();
      final element = set._deserializeElement(elementStr);

      set._elementTags[element] = Set<String>.from(tags);
    }

    // Restore removed tags
    set._removedTags.addAll(removedTags);

    return set;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ORSet<T>) return false;
    return super == other;
  }

  @override
  int get hashCode => super.hashCode;

  @override
  String toString() =>
      'ORSet<$T>(id: $id, size: $size, '
      'totalTags: ${_elementTags.values.fold(0, (sum, tags) => sum + tags.length)}, '
      'removedTags: ${_removedTags.length})';
}
