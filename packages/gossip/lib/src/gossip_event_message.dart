/// Gossip event message for the final step of gossip protocol.
///
/// This module defines the GossipEventMessage class which represents the
/// third and final step in the gossip protocol where the original sender
/// responds with the events that were requested.
library;

import 'event.dart';
import 'gossip_node_id.dart';

/// Final message in the gossip exchange containing requested events.
///
/// This represents the third and final step where the original sender
/// responds with the events that were requested.
class GossipEventMessage {
  /// The ID of the node sending this message.
  final GossipNodeID senderId;

  /// The events being sent.
  final List<Event> events;

  /// Timestamp when this message was created.
  final DateTime createdAt;

  const GossipEventMessage({
    required this.senderId,
    required this.events,
    required this.createdAt,
  });

  /// Creates a message from a JSON representation.
  factory GossipEventMessage.fromJson(Map<String, dynamic> json) {
    final eventsJson = json['events'] as List;
    final events = eventsJson
        .cast<Map<String, dynamic>>()
        .map((e) => Event.fromJson(e))
        .toList();

    return GossipEventMessage(
      senderId: GossipNodeID(json['senderId'] as String),
      events: events,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    );
  }

  /// Converts this message to a JSON representation.
  Map<String, dynamic> toJson() {
    return {
      'senderId': senderId.value,
      'events': events.map((e) => e.toJson()).toList(),
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  @override
  String toString() {
    return 'GossipEventMessage(senderId: $senderId, events: ${events.length})';
  }
}
