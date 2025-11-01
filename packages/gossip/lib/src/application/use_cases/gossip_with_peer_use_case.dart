import '../../event.dart';
import '../../event_store.dart';
import '../../gossip_digest.dart';

import '../../gossip_event_message.dart';
import '../../gossip_node.dart';
import '../../gossip_node_id.dart';

import '../../transport.dart';
import '../services/vector_clock_service.dart';
import '../../domain/entities/internal_gossip_peer.dart';

/// Use case for performing a single gossip exchange with a specific peer.
///
/// This use case isolates the single-peer orchestration away from the cycle
/// coordinator. It:
/// - Resolves the transport peer for the given internal peer
/// - Builds and sends a digest
/// - Accepts any events returned in the digest response
/// - Fulfills any event requests by sending events the peer is missing
class GossipWithPeerUseCase {
  final GossipTransport transport;
  final EventStore eventStore;
  final VectorClockService vectorClockService;

  /// Maximum number of events to include in a single message (total cap).
  final int maxEventsPerMessage;

  GossipWithPeerUseCase({
    required this.transport,
    required this.eventStore,
    required this.vectorClockService,
    this.maxEventsPerMessage = 50,
  });

  /// Execute a single gossip exchange with [peer], returning the result metrics.
  ///
  /// [now] is provided by the caller (e.g., for testability).
  Future<GossipExchangeResult> execute({
    required InternalGossipPeer peer,
    required DateTime now,
  }) async {
    final started = now;
    var eventsExchanged = 0;
    String? error;
    var success = false;

    try {
      // Resolve the corresponding transport peer (by address).
      final transportPeer = await _findTransportPeerByAddress(peer.address);
      if (transportPeer == null) {
        throw StateError('Transport peer not found for ${peer.nodeId}');
      }

      // Build and send our digest using the current vector clock.
      final digest = GossipDigest(
        senderId: GossipNodeID(vectorClockService.nodeId),
        vectorClock: vectorClockService.currentClock.summary,
        createdAt: now,
      );

      final response = await transport.sendDigest(transportPeer, digest);

      // Accept any events they sent us in response to our digest.
      if (response.events.isNotEmpty) {
        for (final event in response.events) {
          final exists = await eventStore.hasEvent(event.id);
          if (!exists) {
            await eventStore.saveEvent(event);
            eventsExchanged++;
          }
        }
      }

      // Fulfill any event requests they made by sending them the events they need.
      if (response.eventRequests.isNotEmpty) {
        final toSend = <Event>[];
        for (final entry in response.eventRequests.entries) {
          final remaining = maxEventsPerMessage - toSend.length;
          if (remaining <= 0) break;

          final nodeId = entry.key;
          final afterTs = entry.value;
          final batch = await eventStore.getEventsSince(
            nodeId,
            afterTs,
            limit: remaining,
          );
          if (batch.isNotEmpty) {
            final needed = maxEventsPerMessage - toSend.length;
            if (batch.length > needed) {
              toSend.addAll(batch.take(needed));
            } else {
              toSend.addAll(batch);
            }
          }
        }

        if (toSend.isNotEmpty) {
          final message = GossipEventMessage(
            senderId: GossipNodeID(vectorClockService.nodeId),
            events: toSend,
            createdAt: now,
          );
          await transport.sendEvents(transportPeer, message);
        }
      }

      success = true;
    } catch (e) {
      error = e.toString();
    }

    return GossipExchangeResult(
      peer: peer.toGossipPeer(),
      success: success,
      eventsExchanged: eventsExchanged,
      duration: DateTime.now().difference(started),
      error: error,
    );
    // Note: Reliability updates and persistence are handled by the cycle use case.
  }

  /// Finds a [TransportPeer] by matching the address to the provided [peerAddress].
  Future<TransportPeer?> _findTransportPeerByAddress(
    TransportPeerAddress peerAddress,
  ) async {
    try {
      final peers = await transport.discoverPeers();
      for (final p in peers) {
        if (p.address == peerAddress) return p;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
