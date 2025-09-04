/// Grow-only Set CRDT implementation.
///
/// A G-Set (Grow-only Set) is a state-based CRDT that represents a set
/// that can only have elements added to it. Elements cannot be removed
/// once they are added.
///
/// The G-Set guarantees that:
/// - All replicas will eventually converge to the same set
/// - Elements can only be added (monotonic growth)
/// - Operations are commutative, associative, and idempotent
///
/// This implementation is suitable for use cases like:
/// - Tag collections
/// - User interest sets
/// - Configuration flags
/// - Any collection that only grows over time
library;

import 'crdt.dart';

/// A grow-only set CRDT.
///
/// The G-Set maintains a set of elements that can only grow. When merging
/// with another replica, the result is the union of both sets.
///
/// ## Example Usage
///
/// ```dart
/// final set1 = GSet<String>('user-tags');
/// final set2 = GSet<String>('user-tags');
///
/// // Node A adds elements
/// await manager.performOperation(set1.id, 'add', {'element': 'music'});
/// await manager.performOperation(set1.id, 'add', {'element': 'sports'});
/// print(set1.value); // {'music', 'sports'}
///
/// // Node B adds elements
/// await manager.performOperation(set2.id, 'add', {'element': 'art'});
/// await manager.performOperation(set2.id, 'add', {'element': 'music'});
/// print(set2.value); // {'art', 'music'}
///
/// // After synchronization, both will show {'music', 'sports', 'art'}
/// set1.mergeState(set2.getState());
/// print(set1.value); // {'music', 'sports', 'art'}
/// ```
class GSet<T> implements CRDT<Set<T>> {
  @override
  final String id;

  final Set<T> _elements = <T>{};

  /// Creates a new G-Set with the specified ID.
  ///
  /// Parameters:
  /// - [id]: Unique identifier for this set across all nodes
  GSet(this.id);

  @override
  String get type => 'GSet';

  @override
  Set<T> get value => Set<T>.unmodifiable(_elements);

  /// Check if the set contains a specific element.
  ///
  /// Parameters:
  /// - [element]: The element to check for
  bool contains(T element) => _elements.contains(element);

  /// Get the number of elements in the set.
  int get size => _elements.length;

  /// Check if the set is empty.
  bool get isEmpty => _elements.isEmpty;

  /// Check if the set is not empty.
  bool get isNotEmpty => _elements.isNotEmpty;

  /// Get all elements as a list.
  ///
  /// Note: The order of elements is not guaranteed to be consistent
  /// across different replicas.
  List<T> get elements => _elements.toList();

  /// Add an element to the set.
  ///
  /// This is typically called internally by the CRDT manager when applying
  /// operations. Direct calls should be avoided in favor of using the
  /// manager's performOperation method.
  ///
  /// Parameters:
  /// - [element]: The element to add to the set
  ///
  /// Returns true if the element was added (wasn't already present),
  /// false if it was already in the set.
  bool add(T element) {
    return _elements.add(element);
  }

  /// Add multiple elements to the set.
  ///
  /// Parameters:
  /// - [elements]: The elements to add to the set
  ///
  /// Returns the number of elements that were actually added
  /// (weren't already present).
  int addAll(Iterable<T> elements) {
    final initialSize = _elements.length;
    _elements.addAll(elements);
    return _elements.length - initialSize;
  }

  @override
  void applyOperation(CRDTOperation operation) {
    switch (operation.operation) {
      case 'add':
        final element = operation.data['element'];
        if (element != null) {
          add(element as T);
        }
        break;
      case 'addAll':
        final elements = operation.data['elements'] as List?;
        if (elements != null) {
          addAll(elements.cast<T>());
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
        'elements': _elements.toList(),
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

    final otherElements = otherState['elements'] as List? ?? [];

    // Union: add all elements from the other set
    for (final element in otherElements) {
      _elements.add(element as T);
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
  CRDT<Set<T>> copy() {
    final copy = GSet<T>(id);
    copy._elements.addAll(_elements);
    return copy;
  }

  @override
  void reset() {
    _elements.clear();
  }

  @override
  void validate() {
    // No additional validation needed for a simple set
  }

  /// Check if this set is a subset of another set.
  ///
  /// Parameters:
  /// - [other]: The other set to compare with
  bool isSubsetOf(Set<T> other) {
    return _elements.every((element) => other.contains(element));
  }

  /// Check if this set is a superset of another set.
  ///
  /// Parameters:
  /// - [other]: The other set to compare with
  bool isSupersetOf(Set<T> other) {
    return other.every((element) => _elements.contains(element));
  }

  /// Get the union of this set with another set.
  ///
  /// Parameters:
  /// - [other]: The other set to union with
  Set<T> union(Set<T> other) {
    return {..._elements, ...other};
  }

  /// Get the intersection of this set with another set.
  ///
  /// Parameters:
  /// - [other]: The other set to intersect with
  Set<T> intersection(Set<T> other) {
    return _elements.where((element) => other.contains(element)).toSet();
  }

  /// Get the difference of this set with another set.
  ///
  /// Returns elements that are in this set but not in the other set.
  ///
  /// Parameters:
  /// - [other]: The other set to compute difference with
  Set<T> difference(Set<T> other) {
    return _elements.where((element) => !other.contains(element)).toSet();
  }

  /// Create a new G-Set from a saved state.
  ///
  /// This factory constructor recreates a G-Set from previously saved state,
  /// typically loaded from persistent storage.
  ///
  /// Parameters:
  /// - [state]: The state map returned by [getState]
  ///
  /// Throws [CRDTException] if the state format is invalid.
  static GSet<T> fromState<T>(Map<String, dynamic> state) {
    if (state['type'] != 'GSet') {
      throw CRDTException('Invalid state type: ${state['type']}');
    }

    final id = state['id'] as String;
    final set = GSet<T>(id);

    final elements = state['elements'] as List? ?? [];
    for (final element in elements) {
      set._elements.add(element as T);
    }

    return set;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! GSet<T>) return false;
    return super == other;
  }

  @override
  int get hashCode => super.hashCode;

  @override
  String toString() => 'GSet<$T>(id: $id, size: $size, elements: $_elements)';
}
