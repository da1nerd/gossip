/// Type-safe identifier for gossip nodes.
///
/// This module defines the GossipNodeID class used to identify nodes
/// in the gossip network with type safety.
library;

/// Type-safe identifier for gossip peers (stable node IDs).
class GossipNodeID {
  /// The underlying string identifier.
  final String value;

  /// Creates a gossip peer ID.
  const GossipNodeID(this.value);

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! GossipNodeID) return false;
    return value == other.value;
  }

  @override
  int get hashCode => value.hashCode;
}
