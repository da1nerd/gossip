/// Transport abstraction for network communication in the gossip protocol.
///
/// This module defines the interface for network communication between gossip
/// nodes. Different implementations can provide various transport mechanisms
/// (HTTP, TCP, UDP, WebSocket, etc.) while keeping the gossip protocol
/// transport-agnostic.
library;

import 'dart:async';
import 'exceptions.dart';
import 'gossip_digest.dart';
import 'gossip_digest_response.dart';
import 'gossip_event_message.dart';

/// Type-safe address for transport peers (transport-specific addresses).
class TransportPeerAddress {
  /// The underlying string address.
  final String value;

  /// Creates a transport peer address.
  const TransportPeerAddress(this.value);

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TransportPeerAddress) return false;
    return value == other.value;
  }

  @override
  int get hashCode => value.hashCode;
}

/// Transport-level peer representation.
/// This represents a peer at the transport layer before we know their node ID.
class TransportPeer {
  final TransportPeerAddress address;

  /// Display name discovered during peer discovery.
  final String displayName;

  /// When this transport peer was connected.
  final DateTime connectedAt;

  /// Whether this transport peer is currently active.
  final bool isActive;

  /// Optional metadata about this transport peer.
  final Map<String, dynamic> metadata;

  const TransportPeer({
    required this.address,
    required this.displayName,
    required this.connectedAt,
    this.isActive = true,
    this.metadata = const {},
  });

  /// Creates a copy with modified values.
  TransportPeer copyWith({
    TransportPeerAddress? transportId,
    String? displayName,
    DateTime? connectedAt,
    bool? isActive,
    Map<String, dynamic>? metadata,
  }) {
    return TransportPeer(
      address: transportId ?? this.address,
      displayName: displayName ?? this.displayName,
      connectedAt: connectedAt ?? this.connectedAt,
      isActive: isActive ?? this.isActive,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'TransportPeer(transportId: $address, displayName: $displayName, isActive: $isActive)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TransportPeer) return false;
    return address == other.address;
  }

  @override
  int get hashCode => address.hashCode;
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

  /// Sends a gossip digest to a transport peer and waits for a response.
  ///
  /// This initiates the first step of the gossip protocol by sending
  /// a digest of the local node's knowledge to the specified transport peer.
  ///
  /// Parameters:
  /// - [transportPeer]: The transport peer to send the digest to
  /// - [digest]: The digest to send
  /// - [timeout]: Maximum time to wait for a response
  ///
  /// Returns the peer's response digest, or throws [TransportException]
  /// if the operation fails or times out.
  Future<GossipDigestResponse> sendDigest(
    TransportPeer transportPeer,
    GossipDigest digest, {
    Duration? timeout,
  });

  /// Sends events to a transport peer in response to their digest.
  ///
  /// This is the final step of the gossip protocol where the original
  /// sender provides the events that the peer requested.
  ///
  /// Parameters:
  /// - [transportPeer]: The transport peer to send events to
  /// - [message]: The events to send
  /// - [timeout]: Maximum time to wait for confirmation
  ///
  /// Throws [TransportException] if the operation fails or times out.
  Future<void> sendEvents(
    TransportPeer transportPeer,
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

  /// Discovers and returns available transport peers in the network.
  ///
  /// This method is used for peer discovery and maintenance. The exact
  /// mechanism depends on the transport implementation (could be multicast,
  /// centralized discovery service, etc.).
  ///
  /// Returns a list of discovered transport peers. May return an empty list if
  /// no peers are currently available.
  Future<List<TransportPeer>> discoverPeers();

  /// Checks if a transport peer is currently reachable.
  ///
  /// This can be used for peer health checking and maintenance.
  /// The implementation should be lightweight and fast.
  Future<bool> isPeerReachable(TransportPeer transportPeer);
}

/// Represents an incoming gossip digest from another node.
class IncomingDigest {
  /// The transport peer that sent this digest.
  final TransportPeer fromTransportPeer;

  /// The digest that was received.
  final GossipDigest digest;

  /// Callback to send a response back to the peer.
  final Future<void> Function(GossipDigestResponse response) respond;

  const IncomingDigest({
    required this.fromTransportPeer,
    required this.digest,
    required this.respond,
  });
}

/// Represents incoming events from another node.
class IncomingEvents {
  /// The transport peer that sent these events.
  final TransportPeer fromTransportPeer;

  /// The events that were received.
  final GossipEventMessage message;

  const IncomingEvents({
    required this.fromTransportPeer,
    required this.message,
  });
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
