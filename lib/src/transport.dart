/// Transport abstraction for network communication in the gossip protocol.
///
/// This module defines the interface for network communication between gossip
/// nodes. Different implementations can provide various transport mechanisms
/// (HTTP, TCP, UDP, WebSocket, etc.) while keeping the gossip protocol
/// transport-agnostic.
library;

import 'dart:async';

import 'event.dart';
import 'exceptions.dart';

/// Represents a peer in the gossip network.
///
/// A peer contains the necessary information to communicate with another
/// node in the gossip network. The exact format of the address depends
/// on the transport implementation.
class GossipPeer {
  /// Unique identifier for this peer.
  final String id;

  /// Transport-specific address for this peer.
  ///
  /// This could be an HTTP URL, TCP socket address, etc.
  /// The format depends on the transport implementation.
  final String address;

  /// Optional metadata about this peer.
  final Map<String, dynamic> metadata;

  /// When this peer was last contacted successfully.
  final DateTime? lastContactTime;

  /// Whether this peer is currently considered active.
  final bool isActive;

  const GossipPeer({
    required this.id,
    required this.address,
    this.metadata = const {},
    this.lastContactTime,
    this.isActive = true,
  });

  /// Creates a copy of this peer with optionally modified values.
  GossipPeer copyWith({
    String? id,
    String? address,
    Map<String, dynamic>? metadata,
    DateTime? lastContactTime,
    bool? isActive,
  }) {
    return GossipPeer(
      id: id ?? this.id,
      address: address ?? this.address,
      metadata: metadata ?? this.metadata,
      lastContactTime: lastContactTime ?? this.lastContactTime,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  String toString() {
    return 'GossipPeer(id: $id, address: $address, '
        'isActive: $isActive, lastContact: $lastContactTime)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! GossipPeer) return false;
    return id == other.id && address == other.address;
  }

  @override
  int get hashCode => Object.hash(id, address);
}

/// A gossip digest containing vector clock information.
///
/// This is sent as the first step in a gossip exchange to communicate
/// the sender's current knowledge of the distributed system state.
class GossipDigest {
  /// The ID of the node sending this digest.
  final String senderId;

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
      senderId: json['senderId'] as String,
      vectorClock: Map<String, int>.from(json['vectorClock'] as Map),
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? {}),
    );
  }

  /// Converts this digest to a JSON representation.
  Map<String, dynamic> toJson() {
    return {
      'senderId': senderId,
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

/// Response to a gossip digest, containing events and requests.
///
/// This represents the second step in the gossip protocol where the
/// receiver responds with events the sender is missing and requests
/// events they need.
class GossipDigestResponse {
  /// The ID of the node sending this response.
  final String senderId;

  /// Events that the digest sender is missing.
  final List<Event> events;

  /// Requests for events that this node is missing.
  /// Map of nodeId -> timestamp (send events after this timestamp).
  final Map<String, int> eventRequests;

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
      senderId: json['senderId'] as String,
      events: events,
      eventRequests: Map<String, int>.from(json['eventRequests'] as Map),
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    );
  }

  /// Converts this response to a JSON representation.
  Map<String, dynamic> toJson() {
    return {
      'senderId': senderId,
      'events': events.map((e) => e.toJson()).toList(),
      'eventRequests': eventRequests,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  @override
  String toString() {
    return 'GossipDigestResponse(senderId: $senderId, '
        'events: ${events.length}, requests: ${eventRequests.length})';
  }
}

/// Final message in the gossip exchange containing requested events.
///
/// This represents the third and final step where the original sender
/// responds with the events that were requested.
class GossipEventMessage {
  /// The ID of the node sending this message.
  final String senderId;

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
      senderId: json['senderId'] as String,
      events: events,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    );
  }

  /// Converts this message to a JSON representation.
  Map<String, dynamic> toJson() {
    return {
      'senderId': senderId,
      'events': events.map((e) => e.toJson()).toList(),
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  @override
  String toString() {
    return 'GossipEventMessage(senderId: $senderId, events: ${events.length})';
  }
}

/// Abstract interface for transport layer implementations.
///
/// This interface defines the methods needed to communicate with other
/// nodes in the gossip network. Implementations can use different
/// protocols (HTTP, TCP, UDP, etc.) while providing a consistent API
/// for the gossip protocol.
abstract class GossipTransport {
  /// Initializes the transport layer.
  ///
  /// This should set up any necessary resources (servers, connections, etc.)
  /// and prepare the transport to handle incoming and outgoing messages.
  ///
  /// Throws [TransportException] if initialization fails.
  Future<void> initialize();

  /// Shuts down the transport layer.
  ///
  /// This should cleanly close any resources and stop accepting new
  /// connections or messages. After calling this method, the transport
  /// should not be used.
  Future<void> shutdown();

  /// Sends a gossip digest to a peer and waits for a response.
  ///
  /// This initiates the first step of the gossip protocol by sending
  /// a digest of the local node's knowledge to the specified peer.
  ///
  /// Parameters:
  /// - [peer]: The peer to send the digest to
  /// - [digest]: The digest to send
  /// - [timeout]: Maximum time to wait for a response
  ///
  /// Returns the peer's response digest, or throws [TransportException]
  /// if the operation fails or times out.
  Future<GossipDigestResponse> sendDigest(
    GossipPeer peer,
    GossipDigest digest, {
    Duration? timeout,
  });

  /// Sends events to a peer in response to their digest.
  ///
  /// This is the final step of the gossip protocol where the original
  /// sender provides the events that the peer requested.
  ///
  /// Parameters:
  /// - [peer]: The peer to send events to
  /// - [message]: The events to send
  /// - [timeout]: Maximum time to wait for confirmation
  ///
  /// Throws [TransportException] if the operation fails or times out.
  Future<void> sendEvents(
    GossipPeer peer,
    GossipEventMessage message, {
    Duration? timeout,
  });

  /// Stream of incoming gossip digests from other nodes.
  ///
  /// The transport implementation should emit digest requests as they
  /// arrive from other nodes. The gossip node will handle these by
  /// generating appropriate responses.
  Stream<IncomingDigest> get incomingDigests;

  /// Stream of incoming event messages from other nodes.
  ///
  /// This stream emits the final event messages in the gossip protocol
  /// where peers send the events that were requested.
  Stream<IncomingEvents> get incomingEvents;

  /// Discovers and returns available peers in the network.
  ///
  /// This method is used for peer discovery and maintenance. The exact
  /// mechanism depends on the transport implementation (could be multicast,
  /// centralized discovery service, etc.).
  ///
  /// Returns a list of discovered peers. May return an empty list if
  /// no peers are currently available.
  Future<List<GossipPeer>> discoverPeers();

  /// Checks if a peer is currently reachable.
  ///
  /// This can be used for peer health checking and maintenance.
  /// The implementation should be lightweight and fast.
  Future<bool> isPeerReachable(GossipPeer peer);
}

/// Represents an incoming gossip digest from another node.
class IncomingDigest {
  /// The peer that sent this digest.
  final GossipPeer fromPeer;

  /// The digest that was received.
  final GossipDigest digest;

  /// Callback to send a response back to the peer.
  final Future<void> Function(GossipDigestResponse response) respond;

  const IncomingDigest({
    required this.fromPeer,
    required this.digest,
    required this.respond,
  });
}

/// Represents incoming events from another node.
class IncomingEvents {
  /// The peer that sent these events.
  final GossipPeer fromPeer;

  /// The events that were received.
  final GossipEventMessage message;

  const IncomingEvents({required this.fromPeer, required this.message});
}

/// Configuration for transport behavior.
class TransportConfig {
  /// Default timeout for transport operations.
  final Duration defaultTimeout;

  /// Maximum message size in bytes.
  final int maxMessageSize;

  /// Whether to enable compression for messages.
  final bool enableCompression;

  /// Additional transport-specific configuration.
  final Map<String, dynamic> additionalConfig;

  const TransportConfig({
    this.defaultTimeout = const Duration(seconds: 10),
    this.maxMessageSize = 1024 * 1024, // 1MB
    this.enableCompression = true,
    this.additionalConfig = const {},
  });

  @override
  String toString() {
    return 'TransportConfig('
        'defaultTimeout: $defaultTimeout, '
        'maxMessageSize: $maxMessageSize, '
        'enableCompression: $enableCompression'
        ')';
  }
}
