/// Peer representation for the gossip network.
///
/// This module defines the GossipPeer class which represents a peer node
/// in the gossip network with both logical identity (node ID) and transport
/// information (address).
library;

import 'gossip_node_id.dart';
import 'transport.dart';

/// Represents a peer in the gossip network.
///
/// A peer contains the necessary information to communicate with another
/// node in the gossip network. The exact format of the address depends
/// on the transport implementation.
class GossipPeer {
  /// Unique identifier for this peer.
  final GossipNodeID id;

  /// Transport-specific address for this peer.
  ///
  /// This could be an HTTP URL, TCP socket address, etc.
  /// The format depends on the transport implementation.
  final TransportPeerAddress address;

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
    GossipNodeID? id,
    TransportPeerAddress? address,
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
