/// Core event data structure for the gossip protocol.
///
/// Events represent discrete occurrences in the distributed system that need
/// to be synchronized across nodes. Each event contains metadata for causality
/// tracking and a flexible payload for application data.
library;

/// Represents a generic event in the distributed system.
///
/// Each event has a unique ID, the ID of the node that created it,
/// a logical timestamp for causality tracking, a creation timestamp
/// for total ordering, and a flexible payload containing application data.
///
/// Events are immutable once created and provide serialization support
/// for network transmission.
class Event {
  /// Unique identifier for this event.
  ///
  /// Should be unique across all nodes in the system. Common patterns include
  /// combining node ID with sequence numbers or using UUIDs.
  final String id;

  /// ID of the node that originally created this event.
  final String nodeId;

  /// Logical timestamp from the vector clock when this event was created.
  ///
  /// Used for causality tracking and determining event ordering across nodes.
  final int timestamp;

  /// Wall-clock timestamp when this event was created.
  ///
  /// Used for human-readable ordering and debugging. Measured in milliseconds
  /// since Unix epoch.
  final int creationTimestamp;

  /// Application-specific event payload.
  ///
  /// Contains the actual data for this event. The structure is determined
  /// by the application using the gossip library.
  final Map<String, dynamic> payload;

  /// Creates a new Event with the specified parameters.
  ///
  /// All parameters are required and the event is immutable once created.
  const Event({
    required this.id,
    required this.nodeId,
    required this.timestamp,
    required this.creationTimestamp,
    required this.payload,
  });

  /// Creates an Event from a JSON map.
  ///
  /// Used for deserializing events received over the network or from storage.
  /// Throws [FormatException] if the JSON structure is invalid.
  factory Event.fromJson(Map<String, dynamic> json) {
    try {
      return Event(
        id: json['id'] as String,
        nodeId: json['nodeId'] as String,
        timestamp: json['timestamp'] as int,
        creationTimestamp: json['creationTimestamp'] as int,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
      );
    } catch (e) {
      throw FormatException('Invalid event JSON structure: $e');
    }
  }

  /// Converts the Event to a JSON map.
  ///
  /// Used for serializing events for network transmission or storage.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nodeId': nodeId,
      'timestamp': timestamp,
      'creationTimestamp': creationTimestamp,
      'payload': payload,
    };
  }

  /// Creates a copy of this event with optionally modified fields.
  ///
  /// Useful for creating derived events or updating metadata while preserving
  /// the core event data.
  Event copyWith({
    String? id,
    String? nodeId,
    int? timestamp,
    int? creationTimestamp,
    Map<String, dynamic>? payload,
  }) {
    return Event(
      id: id ?? this.id,
      nodeId: nodeId ?? this.nodeId,
      timestamp: timestamp ?? this.timestamp,
      creationTimestamp: creationTimestamp ?? this.creationTimestamp,
      payload: payload ?? this.payload,
    );
  }

  /// Compares events for logical ordering based on vector clock timestamps.
  ///
  /// Returns:
  /// - Negative value if this event happened before [other]
  /// - Zero if events are concurrent
  /// - Positive value if this event happened after [other]
  int compareLogicalTime(Event other) {
    return timestamp.compareTo(other.timestamp);
  }

  /// Compares events for wall-clock ordering based on creation timestamps.
  ///
  /// Useful for displaying events in chronological order for users.
  int compareCreationTime(Event other) {
    return creationTimestamp.compareTo(other.creationTimestamp);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Event) return false;
    return id == other.id &&
        nodeId == other.nodeId &&
        timestamp == other.timestamp &&
        creationTimestamp == other.creationTimestamp &&
        _mapEquals(payload, other.payload);
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      nodeId,
      timestamp,
      creationTimestamp,
      _mapHashCode(payload),
    );
  }

  @override
  String toString() {
    return 'Event(id: $id, nodeId: $nodeId, timestamp: $timestamp, '
        'creationTimestamp: $creationTimestamp, payload: $payload)';
  }

  /// Deep equality check for maps.
  static bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      final aValue = a[key];
      final bValue = b[key];
      if (aValue is Map && bValue is Map) {
        if (!_mapEquals(aValue.cast(), bValue.cast())) return false;
      } else if (aValue is List && bValue is List) {
        if (!_listEquals(aValue, bValue)) return false;
      } else if (aValue != bValue) {
        return false;
      }
    }
    return true;
  }

  /// Deep equality check for lists.
  static bool _listEquals(List a, List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final aItem = a[i];
      final bItem = b[i];
      if (aItem is Map && bItem is Map) {
        if (!_mapEquals(aItem.cast(), bItem.cast())) return false;
      } else if (aItem is List && bItem is List) {
        if (!_listEquals(aItem, bItem)) return false;
      } else if (aItem != bItem) {
        return false;
      }
    }
    return true;
  }

  /// Compute hash code for nested map structures.
  static int _mapHashCode(Map<String, dynamic> map) {
    int hash = 0;
    for (final entry in map.entries) {
      final keyHash = entry.key.hashCode;
      final valueHash = entry.value is Map
          ? _mapHashCode((entry.value as Map).cast())
          : entry.value is List
          ? _listHashCode(entry.value as List)
          : entry.value.hashCode;
      hash ^= keyHash ^ valueHash;
    }
    return hash;
  }

  /// Compute hash code for lists.
  static int _listHashCode(List list) {
    int hash = 0;
    for (final item in list) {
      final itemHash = item is Map
          ? _mapHashCode((item as Map).cast())
          : item is List
          ? _listHashCode(item)
          : item.hashCode;
      hash ^= itemHash;
    }
    return hash;
  }
}
