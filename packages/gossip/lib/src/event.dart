/// Core event data structure for the gossip protocol.
///
/// Events represent discrete occurrences in the distributed system that need
/// to be synchronized across nodes. Each event contains metadata for causality
/// tracking and a flexible payload for application data.
library;

import 'gossip_node_id.dart';
import 'gossip_peer.dart';

/// Base class for unified event handling in gossip streams.
abstract class GossipEventBase {
  Event get event;
}

class GossipEventCreated extends GossipEventBase {
  @override
  final Event event;

  GossipEventCreated(this.event);
}

class GossipEventReceived extends GossipEventBase {
  /// The received event.
  final ReceivedEvent receivedEvent;

  GossipEventReceived(this.receivedEvent);

  @override
  Event get event => receivedEvent.event;
}

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
  final GossipNodeID nodeId;

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
        nodeId: GossipNodeID(json['nodeId'] as String),
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
      'nodeId': nodeId.value,
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
    GossipNodeID? nodeId,
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
        creationTimestamp == other.creationTimestamp; // &&
    // _mapEquals(payload, other.payload);
  }

  @override
  int get hashCode {
    return Object.hash(id, nodeId, timestamp, creationTimestamp);
  }

  @override
  String toString() {
    return 'Event(id: $id, nodeId: $nodeId, timestamp: $timestamp, '
        'creationTimestamp: $creationTimestamp, payload: $payload)';
  }
}

/// A wrapper around an Event that includes information about the peer that sent it.
///
/// This is used by the gossip node to provide additional context when events
/// are received from remote peers, allowing applications to correlate transport
/// peer information with gossip events.
class ReceivedEvent {
  /// The event that was received.
  final Event event;

  /// The peer that sent this event.
  final GossipPeer fromPeer;

  /// When this event was received locally.
  final DateTime receivedAt;

  const ReceivedEvent({
    required this.event,
    required this.fromPeer,
    required this.receivedAt,
  });

  /// Convenience getter for the event ID.
  String get id => event.id;

  /// Convenience getter for the node ID that created the event.
  GossipNodeID get nodeId => event.nodeId;

  /// Convenience getter for the event timestamp.
  int get timestamp => event.timestamp;

  /// Convenience getter for the event creation timestamp.
  int get creationTimestamp => event.creationTimestamp;

  /// Convenience getter for the event payload.
  Map<String, dynamic> get payload => event.payload;

  @override
  String toString() {
    return 'ReceivedEvent(event: $event, fromPeer: ${fromPeer.id}, '
        'receivedAt: $receivedAt)';
  }
}
