library;

import '../../gossip_node_id.dart';
import '../../gossip_transport.dart';

/// IdentifiedNode represents a gossip node with a known GossipNodeID,
/// optionally associated with one or more transport addresses that can
/// be used to reach it.
///
/// This entity carries identity-level metadata and a record of known
/// transport entry points. Liveness and reliability are intentionally
/// kept in transport-facing entities (e.g., ConnectedPeer), which can
/// be linked to this identified node when the node identity becomes known.
///
/// Typical lifecycle:
/// 1) A peer is discovered at the transport layer as a ConnectedPeer
/// 2) During a digest/event exchange, we learn the real GossipNodeID
/// 3) We create or link an IdentifiedNode for that ID and associate
///    the discovered transport address(es)
class IdentifiedNode {
  /// Unique gossip-layer identity for this node.
  final GossipNodeID id;

  /// Known transport addresses for this node.
  ///
  /// A node may be reachable via multiple addresses or interfaces.
  /// This list is deduplicated by address value.
  final List<TransportPeerAddress> _addresses = [];

  /// Arbitrary metadata about the node (application-defined).
  final Map<String, dynamic> metadata;

  IdentifiedNode({
    required this.id,
    List<TransportPeerAddress>? addresses,
    Map<String, dynamic> metadata = const {},
  }) : metadata = Map<String, dynamic>.from(metadata) {
    if (addresses != null) {
      for (final a in addresses) {
        addAddress(a);
      }
    }
  }

  /// Returns a copy of the known addresses (read-only).
  List<TransportPeerAddress> get addresses =>
      List<TransportPeerAddress>.unmodifiable(_addresses);

  /// Adds a transport address if not already present.
  ///
  /// Returns true if the address was added, false if it was already present.
  bool addAddress(TransportPeerAddress address) {
    if (_addresses.any((a) => a == address)) return false;
    _addresses.add(address);
    return true;
  }

  /// Removes a transport address if present.
  ///
  /// Returns true if the address was removed.
  bool removeAddress(TransportPeerAddress address) {
    return _addresses.remove(address);
  }

  /// Merges metadata into this node's metadata map.
  ///
  /// Source values take precedence (overwrite existing keys).
  void mergeMetadata(Map<String, dynamic> source) {
    metadata.addAll(source);
  }

  /// Produces a copy of this IdentifiedNode with optionally updated fields.
  ///
  /// Addresses and metadata are deep-copied to preserve immutability for
  /// the returned instance.
  IdentifiedNode copyWith({
    List<TransportPeerAddress>? addresses,
    Map<String, dynamic>? metadata,
  }) {
    return IdentifiedNode(
      id: id,
      addresses: addresses ?? List<TransportPeerAddress>.from(_addresses),
      metadata: metadata ?? Map<String, dynamic>.from(this.metadata),
    );
  }

  @override
  String toString() {
    final addrStr = _addresses.map((a) => a.value).join(', ');
    return 'IdentifiedNode(id: ${id.value}, addresses: [$addrStr], metadata: $metadata)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! IdentifiedNode) return false;
    if (id != other.id) return false;
    if (_addresses.length != other._addresses.length) return false;
    for (final a in _addresses) {
      if (!other._addresses.contains(a)) return false;
    }
    // Metadata equality is best-effort (shallow compare).
    if (metadata.length != other.metadata.length) return false;
    for (final e in metadata.entries) {
      if (!other.metadata.containsKey(e.key)) return false;
      if (other.metadata[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var h = id.hashCode;
    for (final a in _addresses) {
      h = Object.hash(h, a);
    }
    for (final e in metadata.entries) {
      h = Object.hash(h, e.key, e.value);
    }
    return h;
  }
}
