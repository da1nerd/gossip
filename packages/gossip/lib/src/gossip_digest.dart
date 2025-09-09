/// Gossip digest for vector clock information exchange.
///
/// This module defines the GossipDigest class which represents the first step
/// in the gossip protocol where nodes exchange their current knowledge of the
/// distributed system state through vector clock summaries.
library;

import 'gossip_node_id.dart';

/// A gossip digest containing vector clock information.
///
/// This is sent as the first step in a gossip exchange to communicate
/// the sender's current knowledge of the distributed system state.
class GossipDigest {
  /// The ID of the node sending this digest.
  final GossipNodeID senderId;

  /// Vector clock summary representing the sender's knowledge.
  final Map<String, int> vectorClock;

  /// Timestamp when this digest was created.
  final DateTime createdAt;

  /// Optional additional metadata.
  final Map<String, dynamic> metadata;

  const GossipDigest({
    required this.senderId,
    required this.vectorClock,
    required this.createdAt,
    this.metadata = const {},
  });

  /// Creates a digest from a JSON representation.
  factory GossipDigest.fromJson(Map<String, dynamic> json) {
    return GossipDigest(
      senderId: GossipNodeID(json['senderId'] as String),
      vectorClock: Map<String, int>.from(json['vectorClock'] as Map),
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? {}),
    );
  }

  /// Converts this digest to a JSON representation.
  Map<String, dynamic> toJson() {
    return {
      'senderId': senderId.value,
      'vectorClock': vectorClock,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'metadata': metadata,
    };
  }

  @override
  String toString() {
    return 'GossipDigest(senderId: $senderId, vectorClock: $vectorClock, '
        'createdAt: $createdAt)';
  }
}
