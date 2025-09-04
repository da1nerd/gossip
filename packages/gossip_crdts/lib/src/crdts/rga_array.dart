/// Replicated Growable Array CRDT implementation.
///
/// An RGA (Replicated Growable Array) is a sequence-based CRDT that maintains
/// a totally ordered sequence of elements. It's particularly well-suited for
/// collaborative text editing, as it preserves the intention of insertions
/// even when operations are applied in different orders.
///
/// The RGA guarantees that:
/// - All replicas will eventually converge to the same sequence
/// - Insertions maintain their intended position relative to existing elements
/// - Deletions are preserved even with concurrent operations
/// - Operations are commutative, associative, and idempotent
///
/// This implementation is suitable for use cases like:
/// - Collaborative text editing
/// - Shared document editing
/// - Chat message ordering
/// - Any sequence that requires collaborative editing
library;

import 'dart:convert';
import 'dart:math' as math;

import 'crdt.dart';

/// A replicated growable array CRDT for collaborative sequences.
///
/// The RGA maintains a sequence of elements where each element has a unique
/// identifier (UID) that determines its position in the total order. Elements
/// can be inserted at specific positions and marked as deleted (tombstoned).
///
/// ## Example Usage
///
/// ```dart
/// final text1 = RGAArray<String>('shared-text');
/// final text2 = RGAArray<String>('shared-text');
///
/// // Node A inserts characters
/// await manager.performOperation(text1.id, 'insert', {
///   'index': 0,
///   'element': 'H',
/// });
/// await manager.performOperation(text1.id, 'insert', {
///   'index': 1,
///   'element': 'i',
/// });
///
/// // Node B inserts concurrently
/// await manager.performOperation(text2.id, 'insert', {
///   'index': 0,
///   'element': 'W',
/// });
///
/// // After synchronization, both will have consistent ordering
/// text1.mergeState(text2.getState());
/// print(text1.toList()); // Deterministic order based on UIDs
/// ```
class RGAArray<T> implements CRDT<List<T>> {
  @override
  final String id;

  // List of RGA elements (including tombstoned ones)
  final List<_RGAElement<T>> _elements = [];

  // Map from UID to element index for fast lookups
  final Map<String, int> _uidToIndex = {};

  final math.Random _random = math.Random();

  /// Creates a new RGA Array with the specified ID.
  ///
  /// Parameters:
  /// - [id]: Unique identifier for this array across all nodes
  RGAArray(this.id);

  @override
  String get type => 'RGAArray';

  @override
  List<T> get value {
    return _elements
        .where((element) => !element.isDeleted)
        .map((element) => element.value)
        .toList();
  }

  /// Get the visible length of the array (excluding deleted elements).
  int get length => value.length;

  /// Check if the array is empty (no visible elements).
  bool get isEmpty => value.isEmpty;

  /// Check if the array is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Get the total number of elements (including tombstoned ones).
  int get totalElements => _elements.length;

  /// Get the number of deleted elements.
  int get deletedCount => _elements.where((e) => e.isDeleted).length;

  /// Get element at visible index.
  ///
  /// Parameters:
  /// - [index]: The visible index (0-based, excluding deleted elements)
  ///
  /// Throws [RangeError] if index is out of bounds.
  T operator [](int index) {
    final visibleElements = value;
    if (index < 0 || index >= visibleElements.length) {
      throw RangeError.index(index, visibleElements, 'index');
    }
    return visibleElements[index];
  }

  /// Get all elements as a list (excluding deleted elements).
  List<T> toList() => value;

  /// Get all elements including deleted ones (for debugging).
  List<_RGAElement<T>> getAllElements() => List.unmodifiable(_elements);

  /// Insert an element at the specified visible index.
  ///
  /// This is typically called internally by the CRDT manager when applying
  /// operations. Direct calls should be avoided in favor of using the
  /// manager's performOperation method.
  ///
  /// Parameters:
  /// - [index]: The visible index where to insert (0-based)
  /// - [element]: The element to insert
  /// - [nodeId]: The node performing the insertion
  /// - [timestamp]: Optional timestamp for the operation
  /// - [customUid]: Optional custom UID (for testing)
  ///
  /// Returns the UID of the inserted element.
  String insert(
    int index,
    T element,
    String nodeId, {
    DateTime? timestamp,
    String? customUid,
  }) {
    final visibleElements = _getVisibleElements();

    if (index < 0 || index > visibleElements.length) {
      throw RangeError.index(index, visibleElements, 'index');
    }

    final uid = customUid ?? _generateUID(nodeId, timestamp);

    final newElement = _RGAElement<T>(
      uid: uid,
      value: element,
      timestamp: timestamp ?? DateTime.now(),
      nodeId: nodeId,
    );

    // Find the position to insert based on visible index
    int insertPosition;
    if (index == 0) {
      // Insert at the beginning
      insertPosition = 0;
    } else if (index >= visibleElements.length) {
      // Insert at the end
      insertPosition = _elements.length;
    } else {
      // Find the position after the (index-1)th visible element
      int visibleCount = 0;
      insertPosition = 0;

      for (int i = 0; i < _elements.length; i++) {
        if (!_elements[i].isDeleted) {
          if (visibleCount == index) {
            insertPosition = i;
            break;
          }
          visibleCount++;
        }
        if (visibleCount < index) {
          insertPosition = i + 1;
        }
      }
    }

    _elements.insert(insertPosition, newElement);
    _rebuildUidIndex();

    return uid;
  }

  /// Delete an element at the specified visible index.
  ///
  /// This marks the element as deleted (tombstone) rather than removing it,
  /// which is necessary for maintaining causal consistency.
  ///
  /// Parameters:
  /// - [index]: The visible index of the element to delete
  ///
  /// Returns true if the element was found and deleted, false otherwise.
  bool deleteAt(int index) {
    final visibleElements = _getVisibleElements();

    if (index < 0 || index >= visibleElements.length) {
      return false;
    }

    final elementToDelete = visibleElements[index];
    elementToDelete.isDeleted = true;

    return true;
  }

  /// Delete an element by its UID.
  ///
  /// Parameters:
  /// - [uid]: The unique identifier of the element to delete
  ///
  /// Returns true if the element was found and deleted, false otherwise.
  bool deleteByUID(String uid) {
    final elementIndex = _uidToIndex[uid];
    if (elementIndex == null) return false;

    _elements[elementIndex].isDeleted = true;
    return true;
  }

  /// Get the visible index of an element by its UID.
  ///
  /// Returns null if the element is not found or is deleted.
  int? getVisibleIndex(String uid) {
    final elementIndex = _uidToIndex[uid];
    if (elementIndex == null) return null;

    final element = _elements[elementIndex];
    if (element.isDeleted) return null;

    // Count non-deleted elements before this one
    int visibleIndex = 0;
    for (int i = 0; i < elementIndex; i++) {
      if (!_elements[i].isDeleted) {
        visibleIndex++;
      }
    }

    return visibleIndex;
  }

  @override
  void applyOperation(CRDTOperation operation) {
    switch (operation.operation) {
      case 'insert':
        final index = operation.data['index'] as int? ?? 0;
        final element = operation.data['element'];
        final uid = operation.data['uid'] as String?;

        if (element != null) {
          insert(
            index,
            element as T,
            operation.nodeId,
            timestamp: operation.timestamp,
            customUid: uid,
          );
        }
        break;

      case 'delete':
        final index = operation.data['index'] as int?;
        final uid = operation.data['uid'] as String?;

        if (uid != null) {
          deleteByUID(uid);
        } else if (index != null) {
          deleteAt(index);
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
        'elements': _elements
            .map(
              (element) => {
                'uid': element.uid,
                'value': _serializeValue(element.value),
                'timestamp': element.timestamp.millisecondsSinceEpoch,
                'nodeId': element.nodeId,
                'isDeleted': element.isDeleted,
              },
            )
            .toList(),
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

    // Track existing UIDs to avoid duplicates
    final existingUIDs = <String>{};
    for (final element in _elements) {
      existingUIDs.add(element.uid);
    }

    // Add elements from other state that we don't have
    for (final elementData in otherElements) {
      final data = elementData as Map<String, dynamic>;
      final uid = data['uid'] as String;

      if (!existingUIDs.contains(uid)) {
        final element = _RGAElement<T>(
          uid: uid,
          value: _deserializeValue(data['value']),
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            data['timestamp'] as int,
          ),
          nodeId: data['nodeId'] as String,
          isDeleted: data['isDeleted'] as bool? ?? false,
        );

        _elements.add(element);
      } else {
        // Update deletion status if needed
        final existingIndex = _uidToIndex[uid];
        if (existingIndex != null) {
          final isDeleted = data['isDeleted'] as bool? ?? false;
          if (isDeleted && !_elements[existingIndex].isDeleted) {
            _elements[existingIndex].isDeleted = true;
          }
        }
      }
    }

    // Rebuild index and sort
    _rebuildUidIndex();
    _sortElements();
  }

  @override
  CRDTOperation createOperation(
    String operationType,
    Map<String, dynamic> data, {
    String? nodeId,
    DateTime? timestamp,
  }) {
    final operationData = Map<String, dynamic>.from(data);

    // For insert operations, generate UID if not provided
    if (operationType == 'insert' && !operationData.containsKey('uid')) {
      operationData['uid'] = _generateUID(nodeId ?? '', timestamp);
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
  CRDT<List<T>> copy() {
    final copy = RGAArray<T>(id);

    for (final element in _elements) {
      copy._elements.add(
        _RGAElement<T>(
          uid: element.uid,
          value: element.value,
          timestamp: element.timestamp,
          nodeId: element.nodeId,
          isDeleted: element.isDeleted,
        ),
      );
    }

    copy._rebuildUidIndex();
    return copy;
  }

  @override
  void reset() {
    _elements.clear();
    _uidToIndex.clear();
  }

  @override
  void validate() {
    // Validate that UID index is consistent
    if (_uidToIndex.length != _elements.length) {
      throw CRDTException(
        'UID index size (${_uidToIndex.length}) does not match elements size (${_elements.length})',
        crdtId: id,
      );
    }

    // Validate that all UIDs are unique
    final uids = _elements.map((e) => e.uid).toSet();
    if (uids.length != _elements.length) {
      throw CRDTException('Duplicate UIDs found in RGA array', crdtId: id);
    }

    // Validate element ordering (should be sorted by UID)
    for (int i = 1; i < _elements.length; i++) {
      if (_compareUIDs(_elements[i - 1].uid, _elements[i].uid) > 0) {
        throw CRDTException(
          'Elements are not properly sorted by UID',
          crdtId: id,
        );
      }
    }
  }

  /// Get list of visible (non-deleted) elements.
  List<_RGAElement<T>> _getVisibleElements() {
    return _elements.where((element) => !element.isDeleted).toList();
  }

  /// Rebuild the UID to index mapping.
  void _rebuildUidIndex() {
    _uidToIndex.clear();
    for (int i = 0; i < _elements.length; i++) {
      _uidToIndex[_elements[i].uid] = i;
    }
  }

  /// Sort elements by their UID to maintain RGA ordering.
  void _sortElements() {
    _elements.sort((a, b) => _compareUIDs(a.uid, b.uid));
    _rebuildUidIndex();
  }

  /// Compare two UIDs for ordering.
  ///
  /// UIDs are compared lexicographically to provide a total order.
  int _compareUIDs(String uid1, String uid2) {
    return uid1.compareTo(uid2);
  }

  /// Generate a unique identifier for an element.
  String _generateUID(String nodeId, [DateTime? timestamp]) {
    final ts = timestamp ?? DateTime.now();
    final randomSuffix = _random.nextInt(999999).toString().padLeft(6, '0');
    return '${nodeId}_${ts.millisecondsSinceEpoch}_$randomSuffix';
  }

  /// Serialize a value for state storage.
  dynamic _serializeValue(T value) {
    if (value is String || value is num || value is bool) return value;
    return jsonEncode(value);
  }

  /// Deserialize a value from state storage.
  T _deserializeValue(dynamic valueData) {
    // For basic types, return as-is if they match
    if (valueData is T) return valueData;

    // For basic types, try to parse appropriately
    if (T == String) return valueData.toString() as T;
    if (T == int && valueData is num) return valueData.toInt() as T;
    if (T == double && valueData is num) return valueData.toDouble() as T;
    if (T == bool) return (valueData.toString() == 'true') as T;

    // For complex types, try JSON decoding if it's a string
    if (valueData is String) {
      try {
        return jsonDecode(valueData) as T;
      } catch (e) {
        return valueData as T;
      }
    }

    return valueData as T;
  }

  /// Insert text at the specified position (convenience method for text editing).
  ///
  /// This method is specifically designed for text editing use cases where
  /// you want to insert a string at a specific character position.
  ///
  /// Parameters:
  /// - [index]: The character position where to insert
  /// - [text]: The text to insert
  /// - [nodeId]: The node performing the insertion
  ///
  /// Returns a list of UIDs for the inserted characters.
  List<String> insertText(int index, String text, String nodeId) {
    if (T != String) {
      throw CRDTException(
        'insertText can only be used with RGAArray<String>',
        crdtId: id,
      );
    }

    final uids = <String>[];
    for (int i = 0; i < text.length; i++) {
      final uid = insert(index + i, text[i] as T, nodeId);
      uids.add(uid);
    }
    return uids;
  }

  /// Delete text range (convenience method for text editing).
  ///
  /// Parameters:
  /// - [start]: The start index (inclusive)
  /// - [end]: The end index (exclusive)
  ///
  /// Returns the number of characters actually deleted.
  int deleteRange(int start, int end) {
    if (start < 0 || end < start || start >= length) {
      return 0;
    }

    final actualEnd = math.min(end, length);
    int deletedCount = 0;

    // Delete from end to start to maintain indices
    for (int i = actualEnd - 1; i >= start; i--) {
      if (deleteAt(i)) {
        deletedCount++;
      }
    }

    return deletedCount;
  }

  /// Get the text content as a string (only works with RGAArray<String>).
  String getText() {
    if (T != String) {
      throw CRDTException(
        'getText can only be used with RGAArray<String>',
        crdtId: id,
      );
    }

    return value.join('');
  }

  /// Create a new RGA Array from a saved state.
  ///
  /// This factory constructor recreates an RGA Array from previously saved state,
  /// typically loaded from persistent storage.
  ///
  /// Parameters:
  /// - [state]: The state map returned by [getState]
  ///
  /// Throws [CRDTException] if the state format is invalid.
  static RGAArray<T> fromState<T>(Map<String, dynamic> state) {
    if (state['type'] != 'RGAArray') {
      throw CRDTException('Invalid state type: ${state['type']}');
    }

    final id = state['id'] as String;
    final array = RGAArray<T>(id);

    final elements = state['elements'] as List? ?? [];

    for (final elementData in elements) {
      final data = elementData as Map<String, dynamic>;
      final element = _RGAElement<T>(
        uid: data['uid'] as String,
        value: array._deserializeValue(data['value']),
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          data['timestamp'] as int,
        ),
        nodeId: data['nodeId'] as String,
        isDeleted: data['isDeleted'] as bool? ?? false,
      );

      array._elements.add(element);
    }

    array._rebuildUidIndex();
    array._sortElements();

    return array;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RGAArray<T>) return false;
    return super == other;
  }

  @override
  int get hashCode => super.hashCode;

  @override
  String toString() => 'RGAArray<$T>(id: $id, length: $length, '
      'totalElements: $totalElements, deletedCount: $deletedCount)';
}

/// Internal class representing an element in the RGA array.
class _RGAElement<T> {
  final String uid;
  final T value;
  final DateTime timestamp;
  final String nodeId;
  bool isDeleted;

  _RGAElement({
    required this.uid,
    required this.value,
    required this.timestamp,
    required this.nodeId,
    this.isDeleted = false,
  });

  @override
  String toString() => '_RGAElement(uid: $uid, value: $value, '
      'timestamp: $timestamp, nodeId: $nodeId, isDeleted: $isDeleted)';
}
