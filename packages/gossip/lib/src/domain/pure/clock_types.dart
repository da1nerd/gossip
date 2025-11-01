import '../../gossip_node_id.dart';

/// Pure, type-safe wrapper around a vector clock summary.
/// Keys are strongly typed as `GossipNodeID` to prevent mixing node IDs with
/// arbitrary strings. Values are monotonically increasing logical timestamps.
///
/// This type is immutable. All mutating operations return a new instance.
class ClockSummary {
  /// Per-node logical timestamps.
  final Map<GossipNodeID, int> byNode;

  /// Creates an immutable clock summary from the provided map.
  /// The input is defensively copied.
  ClockSummary(Map<GossipNodeID, int> byNode)
    : byNode = Map.unmodifiable(Map<GossipNodeID, int>.of(byNode));

  /// Constructs from a String-backed map (e.g. wire/storage format).
  factory ClockSummary.fromStringMap(Map<String, int> map) {
    return ClockSummary({
      for (final e in map.entries) GossipNodeID(e.key): e.value,
    });
  }

  /// Converts to a String-backed map (e.g. for wire/storage).
  Map<String, int> toStringMap() {
    return {for (final e in byNode.entries) e.key.value: e.value};
  }

  /// Returns the timestamp for a node, or 0 if missing.
  int getTimestamp(GossipNodeID nodeId) => byNode[nodeId] ?? 0;

  /// Returns a new summary with the timestamp for [nodeId] set to [timestamp].
  ClockSummary withTimestamp(GossipNodeID nodeId, int timestamp) {
    final next = Map<GossipNodeID, int>.of(byNode);
    next[nodeId] = timestamp;
    return ClockSummary(next);
  }

  /// Returns a new summary that is the element-wise max (join) of this and [other].
  ClockSummary mergedMax(ClockSummary other) {
    final keys = <GossipNodeID>{...byNode.keys, ...other.byNode.keys};
    final merged = <GossipNodeID, int>{};
    for (final k in keys) {
      final a = byNode[k] ?? 0;
      final b = other.byNode[k] ?? 0;
      merged[k] = a >= b ? a : b;
    }
    return ClockSummary(merged);
  }

  /// Whether this summary dominates (is greater-or-equal) another summary
  /// for all nodes. Useful for partial ordering checks in vector clocks.
  bool dominates(ClockSummary other) {
    // this >= other if for all nodes n: this[n] >= other[n]
    final keys = <GossipNodeID>{...byNode.keys, ...other.byNode.keys};
    for (final k in keys) {
      final a = byNode[k] ?? 0;
      final b = other.byNode[k] ?? 0;
      if (a < b) return false;
    }
    return true;
  }

  @override
  String toString() => 'ClockSummary(${toStringMap()})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ClockSummary) return false;
    if (byNode.length != other.byNode.length) return false;
    for (final entry in byNode.entries) {
      if ((other.byNode[entry.key] ?? -1) != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    // Order-independent hash: xor of key/value hashes.
    var h = 0;
    for (final e in byNode.entries) {
      h ^= Object.hash(e.key, e.value);
    }
    return h;
  }
}
