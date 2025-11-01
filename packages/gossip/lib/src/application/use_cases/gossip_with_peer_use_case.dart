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
@Deprecated('use GossipWithConnectedPeerUseCase instead')
class GossipWithPeerUseCase {
  final GossipTransport transport;
  final EventStore eventStore;
  final VectorClockService vectorClockService;

  /// Maximum number of events to include in a single message (total cap).
  final int maxEventsPerMessage;

  /// Timeout to use for transport operations (digest and events).
  final Duration operationTimeout;

  GossipWithPeerUseCase({
    required this.transport,
    required this.eventStore,
    required this.vectorClockService,
    this.maxEventsPerMessage = 50,
    this.operationTimeout = const Duration(seconds: 3),
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
      final transportPeer = await _resolveTransportPeerOrThrow(peer);
      final digest = _buildDigest(now);
      final response = await _sendDigest(transportPeer, digest);

      eventsExchanged += await _acceptIncomingEvents(response);
      await _fulfillEventRequests(response, transportPeer, now);

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

  Future<TransportPeer> _resolveTransportPeerOrThrow(
    InternalGossipPeer peer,
  ) async {
    final transportPeer = await _findTransportPeerByAddress(peer.address);
    if (transportPeer == null) {
      throw StateError('Transport peer not found for ${peer.nodeId}');
    }
    return transportPeer;
  }

  GossipDigest _buildDigest(DateTime now) {
    return GossipDigest(
      senderId: GossipNodeID(vectorClockService.nodeId),
      vectorClock: vectorClockService.currentClock.summary,
      createdAt: now,
    );
  }

  Future<dynamic> _sendDigest(TransportPeer to, GossipDigest digest) {
    return transport.sendDigest(to, digest, timeout: operationTimeout);
  }

  Future<int> _acceptIncomingEvents(dynamic response) async {
    var exchanged = 0;
    if (response.events.isNotEmpty) {
      for (final event in response.events) {
        final exists = await eventStore.hasEvent(event.id);
        if (!exists) {
          await eventStore.saveEvent(event);
          exchanged++;
        }
      }
    }
    return exchanged;
  }

  Future<void> _fulfillEventRequests(
    dynamic response,
    TransportPeer transportPeer,
    DateTime now,
  ) async {
    if (response.eventRequests.isEmpty) return;

    final toSend = <Event>[];

    // Cursor per node to avoid re-reading the same window in multiple rounds.
    final cursorTs = <GossipNodeID, int>{
      for (final e in response.eventRequests.entries) e.key: e.value,
    };
    final pending = response.eventRequests.keys.toList();

    var remaining = maxEventsPerMessage;
    while (remaining > 0 && pending.isNotEmpty) {
      var anyProgress = false;

      // Compute a small fair chunk per pending node this round.
      final perNodeChunk = remaining ~/ pending.length;
      final chunkSize = perNodeChunk > 0 ? perNodeChunk : 1;

      // Round-robin fetch across pending nodes.
      for (final nodeId in List<GossipNodeID>.from(pending)) {
        final afterTs = cursorTs[nodeId]!;
        final limit = chunkSize < remaining ? chunkSize : remaining;

        final batch = await eventStore.getEventsSince(
          nodeId,
          afterTs,
          limit: limit,
        );

        if (batch.isEmpty) {
          // No more events for this node; remove from pending.
          pending.remove(nodeId);
          continue;
        }

        // Append up to remaining capacity and advance cursor to last timestamp.
        final takeCount = batch.length > remaining ? remaining : batch.length;
        toSend.addAll(batch.take(takeCount));
        remaining -= takeCount;
        cursorTs[nodeId] = batch.last.timestamp;
        anyProgress = true;

        if (remaining <= 0) break;
      }

      if (!anyProgress) {
        // No node produced events in this round; stop.
        break;
      }
    }

    if (toSend.isNotEmpty) {
      final message = GossipEventMessage(
        senderId: GossipNodeID(vectorClockService.nodeId),
        events: toSend,
        createdAt: now,
      );
      await transport.sendEvents(
        transportPeer,
        message,
        timeout: operationTimeout,
      );
    }
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
