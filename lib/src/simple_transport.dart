/// Simplified transport interface for basic event broadcasting.
///
/// This provides a much simpler alternative to the full GossipTransport interface
/// for use cases where you just need basic event broadcasting without the full
/// 3-phase gossip protocol complexity.
library;

import 'dart:async';

import 'event.dart';
import 'transport.dart';

/// Simplified transport interface for basic event broadcasting.
///
/// This is much easier to implement than the full GossipTransport interface
/// and is suitable for many real-world use cases where you just need events
/// to be synchronized across peers without complex gossip mechanics.
abstract class SimpleGossipTransport {
  /// Initialize the transport (connect, start listening, etc.)
  Future<void> initialize();

  /// Broadcast an event to all connected peers
  Future<void> broadcastEvent(Event event);

  /// Send an event to a specific peer
  Future<void> sendEventToPeer(String peerId, Event event);

  /// Stream of incoming events from other peers
  Stream<Event> get incomingEvents;

  /// Get list of connected peer IDs
  List<String> get connectedPeerIds;

  /// Dispose resources and close connections
  Future<void> dispose();
}

/// Adapter to use SimpleGossipTransport with existing GossipNode.
///
/// This allows you to use a simple transport implementation with the existing
/// gossip library infrastructure by adapting the simple interface to the
/// full GossipTransport interface.
class SimpleTransportAdapter implements GossipTransport {
  final SimpleGossipTransport _simpleTransport;
  final StreamController<IncomingDigest> _digestController =
      StreamController.broadcast();
  final StreamController<IncomingEvents> _eventsController =
      StreamController.broadcast();
  final StreamController<GossipPeer> _peerDisconnectionsController =
      StreamController.broadcast();

  SimpleTransportAdapter(this._simpleTransport) {
    // Listen to incoming events and convert them to the format expected by GossipNode
    _simpleTransport.incomingEvents.listen((event) {
      final eventMessage = GossipEventMessage(
        senderId: event.nodeId,
        events: [event],
        createdAt: DateTime.now(),
      );

      _eventsController.add(IncomingEvents(
        fromPeer: GossipPeer(id: event.nodeId, address: event.nodeId),
        message: eventMessage,
      ));
    });
  }

  @override
  Future<void> initialize() => _simpleTransport.initialize();

  @override
  Future<GossipDigestResponse> sendDigest(
    GossipPeer peer,
    GossipDigest digest, {
    Duration? timeout,
  }) async {
    // For simple use cases, we skip the digest phase and just return empty response
    // The actual event synchronization happens through direct broadcasting
    return GossipDigestResponse(
      senderId: digest.senderId,
      events: [],
      eventRequests: {},
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> sendEvents(
    GossipPeer peer,
    GossipEventMessage eventMessage, {
    Duration? timeout,
  }) async {
    // Send each event to the specific peer using the simple transport
    for (final event in eventMessage.events) {
      await _simpleTransport.sendEventToPeer(peer.id, event);
    }
  }

  @override
  Stream<IncomingDigest> get incomingDigests => _digestController.stream;

  @override
  Stream<IncomingEvents> get incomingEvents => _eventsController.stream;

  @override
  Future<List<GossipPeer>> discoverPeers() async {
    return _simpleTransport.connectedPeerIds
        .map((id) => GossipPeer(id: id, address: id))
        .toList();
  }

  @override
  Future<bool> isPeerReachable(GossipPeer peer) async {
    return _simpleTransport.connectedPeerIds.contains(peer.id);
  }

  @override
  Future<void> shutdown() async {
    await _simpleTransport.dispose();
    await _digestController.close();
    await _eventsController.close();
    await _peerDisconnectionsController.close();
  }
}
