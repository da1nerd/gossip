/// Gossip digest response for the second step of gossip protocol.
///
/// This module defines the GossipDigestResponse class which represents the
/// second step in the gossip protocol where the receiver responds with events
/// the sender is missing and requests events they need.
library;

import 'event.dart';
import 'gossip_node_id.dart';

/// Response to a gossip digest, containing events and requests.
///
/// This represents the second step in the gossip protocol where the
/// receiver responds with events the sender is missing and requests
/// events they need.
class GossipDigestResponse {
  /// The ID of the node sending this response.
  final GossipNodeID senderId;

  /// Events that the digest sender is missing.
  final List<Event> events;

  /// Requests for events that this node is missing.
  /// Map of nodeId -> timestamp (send events after this timestamp).
  final Map<GossipNodeID, int> eventRequests;

  /// Timestamp when this response was created.
  final DateTime createdAt;

  const GossipDigestResponse({
    required this.senderId,
    required this.events,
    required this.eventRequests,
    required this.createdAt,
  });

  /// Creates a response from a JSON representation.
  factory GossipDigestResponse.fromJson(Map<String, dynamic> json) {
    final eventsJson = json['events'] as List;
    final events = eventsJson
        .cast<Map<String, dynamic>>()
        .map((e) => Event.fromJson(e))
        .toList();

    return GossipDigestResponse(
      senderId: GossipNodeID(json['senderId'] as String),
      events: events,
      eventRequests: (json['eventRequests'] as Map).map(
        (key, value) => MapEntry(GossipNodeID(key as String), value as int),
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    );
  }

  /// Converts this response to a JSON representation.
  Map<String, dynamic> toJson() {
    return {
      'senderId': senderId.value,
      'events': events.map((e) => e.toJson()).toList(),
      'eventRequests': eventRequests.map(
        (key, value) => MapEntry(key.value, value),
      ),
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  @override
  String toString() {
    return 'GossipDigestResponse(senderId: $senderId, '
        'events: ${events.length}, requests: ${eventRequests.length})';
  }
}
