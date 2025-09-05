/// Vector clock implementation for tracking causality in distributed events.
///
/// Vector clocks are used to determine the causal ordering of events across
/// nodes in a distributed system. They help identify which events happened
/// before others, which are concurrent, and ensure proper event synchronization.
library;

/// A Vector Clock to track the logical time of events across nodes.
///
/// This is crucial for determining the causality of events and ensuring
/// that events are not missed during synchronization. Each node maintains
/// a vector clock that tracks the latest known timestamp for every node
/// in the system.
///
/// Vector clocks enable the gossip protocol to:
/// - Determine which events a peer is missing
/// - Maintain causal ordering of events
/// - Detect concurrent events
/// - Prevent duplicate event processing
class VectorClock {
  final Map<String, int> _clocks;

  /// Creates a new empty vector clock.
  VectorClock() : _clocks = <String, int>{};

  /// Creates a vector clock from an existing map of node timestamps.
  VectorClock.fromMap(Map<String, int> clocks)
    : _clocks = Map<String, int>.from(clocks);

  /// Creates a vector clock from a JSON representation.
  ///
  /// Throws [FormatException] if the JSON structure is invalid.
  factory VectorClock.fromJson(Map<String, dynamic> json) {
    try {
      final clocks = <String, int>{};
      for (final entry in json.entries) {
        clocks[entry.key] = entry.value as int;
      }
      return VectorClock.fromMap(clocks);
    } catch (e) {
      throw FormatException('Invalid vector clock JSON structure: $e');
    }
  }

  /// Gets the current timestamp for a given node.
  ///
  /// Returns 0 if the node is not known to this vector clock.
  int getTimestampFor(String nodeId) {
    if (nodeId.isEmpty) {
      throw ArgumentError.value(nodeId, 'nodeId', 'Node ID cannot be empty');
    }
    return _clocks[nodeId] ?? 0;
  }

  /// Sets the timestamp for a specific node.
  ///
  /// Throws [ArgumentError] if the timestamp is negative or if the node ID is empty.
  void setTimestampFor(String nodeId, int timestamp) {
    if (nodeId.isEmpty) {
      throw ArgumentError.value(nodeId, 'nodeId', 'Node ID cannot be empty');
    }
    if (timestamp < 0) {
      throw ArgumentError.value(
        timestamp,
        'timestamp',
        'Timestamp cannot be negative',
      );
    }
    _clocks[nodeId] = timestamp;
  }

  /// Increments the timestamp for a given node.
  ///
  /// If the node doesn't exist in the clock, it's initialized to 1.
  /// Throws [ArgumentError] if the node ID is empty.
  void increment(String nodeId) {
    if (nodeId.isEmpty) {
      throw ArgumentError.value(nodeId, 'nodeId', 'Node ID cannot be empty');
    }
    _clocks[nodeId] = getTimestampFor(nodeId) + 1;
  }

  /// Merges this vector clock with another, taking the maximum of each entry.
  ///
  /// This operation is used when receiving events from other nodes to update
  /// the local knowledge of the distributed system's state.
  void merge(VectorClock other) {
    for (final entry in other._clocks.entries) {
      final localTimestamp = getTimestampFor(entry.key);
      if (entry.value > localTimestamp) {
        _clocks[entry.key] = entry.value;
      }
    }
  }

  /// Creates a new vector clock that is the result of merging this clock with another.
  ///
  /// This operation doesn't modify either of the original clocks.
  VectorClock merged(VectorClock other) {
    final result = VectorClock.fromMap(_clocks);
    result.merge(other);
    return result;
  }

  /// Compares this vector clock with another to determine their relationship.
  ///
  /// Returns:
  /// - [ClockComparison.before] if this clock is entirely before the other
  /// - [ClockComparison.after] if this clock is entirely after the other
  /// - [ClockComparison.concurrent] if the clocks are concurrent (partial order)
  /// - [ClockComparison.equal] if the clocks are identical
  ClockComparison compareTo(VectorClock other) {
    final allNodes = <String>{..._clocks.keys, ...other._clocks.keys};

    bool thisIsLessOrEqual = true;
    bool otherIsLessOrEqual = true;

    for (final nodeId in allNodes) {
      final thisTime = getTimestampFor(nodeId);
      final otherTime = other.getTimestampFor(nodeId);

      if (thisTime < otherTime) {
        otherIsLessOrEqual = false;
      } else if (thisTime > otherTime) {
        thisIsLessOrEqual = false;
      }
    }

    if (thisIsLessOrEqual && otherIsLessOrEqual) {
      return ClockComparison.equal;
    } else if (thisIsLessOrEqual) {
      return ClockComparison.before;
    } else if (otherIsLessOrEqual) {
      return ClockComparison.after;
    } else {
      return ClockComparison.concurrent;
    }
  }

  /// Returns true if this vector clock happened before the other.
  bool isBefore(VectorClock other) {
    return compareTo(other) == ClockComparison.before;
  }

  /// Returns true if this vector clock happened after the other.
  bool isAfter(VectorClock other) {
    return compareTo(other) == ClockComparison.after;
  }

  /// Returns true if this vector clock is concurrent with the other.
  bool isConcurrentWith(VectorClock other) {
    return compareTo(other) == ClockComparison.concurrent;
  }

  /// Returns true if this vector clock is identical to the other.
  bool isEqualTo(VectorClock other) {
    return compareTo(other) == ClockComparison.equal;
  }

  /// Returns a list of node IDs that this clock knows about.
  List<String> get knownNodes => _clocks.keys.toList();

  /// Returns the number of nodes tracked by this vector clock.
  int get nodeCount => _clocks.length;

  /// Returns true if this vector clock has no entries.
  bool get isEmpty => _clocks.isEmpty;

  /// Returns true if this vector clock has entries.
  bool get isNotEmpty => _clocks.isNotEmpty;

  /// Returns a read-only summary of the vector clock.
  ///
  /// This is often used in the gossip digest to communicate the current
  /// state of knowledge to other nodes.
  Map<String, int> get summary => Map.unmodifiable(_clocks);

  /// Converts the vector clock to a JSON representation.
  Map<String, dynamic> toJson() => Map<String, dynamic>.from(_clocks);

  /// Creates a copy of this vector clock.
  VectorClock copy() => VectorClock.fromMap(_clocks);

  /// Clears all entries from this vector clock.
  void clear() {
    _clocks.clear();
  }

  /// Removes a specific node from the vector clock.
  ///
  /// This might be useful when a node permanently leaves the system.
  /// Returns true if the node was present and removed, false otherwise.
  bool removeNode(String nodeId) {
    return _clocks.remove(nodeId) != null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! VectorClock) return false;

    if (_clocks.length != other._clocks.length) return false;

    for (final entry in _clocks.entries) {
      if (other._clocks[entry.key] != entry.value) return false;
    }

    return true;
  }

  @override
  int get hashCode {
    int hash = 0;
    for (final entry in _clocks.entries) {
      hash ^= entry.key.hashCode ^ entry.value.hashCode;
    }
    return hash;
  }

  @override
  String toString() {
    if (_clocks.isEmpty) return 'VectorClock({})';

    final entries = _clocks.entries
        .map((e) => '${e.key}:${e.value}')
        .join(', ');
    return 'VectorClock({$entries})';
  }
}

/// Represents the relationship between two vector clocks.
enum ClockComparison {
  /// The first clock happened before the second clock.
  before,

  /// The first clock happened after the second clock.
  after,

  /// The clocks are concurrent (neither happened before the other).
  concurrent,

  /// The clocks are identical.
  equal,
}
