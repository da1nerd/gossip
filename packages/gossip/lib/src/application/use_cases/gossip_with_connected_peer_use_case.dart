import 'package:gossip/src/event.dart';
import 'package:gossip/src/event_store.dart';
import 'package:gossip/src/gossip_digest.dart';
import 'package:gossip/src/gossip_event_message.dart';
import 'package:gossip/src/gossip_node.dart' show GossipExchangeResult;
import 'package:gossip/src/gossip_node_id.dart';
import 'package:gossip/src/gossip_peer.dart';
import 'package:gossip/src/transport.dart';
import 'package:gossip/src/application/services/vector_clock_service.dart';
import 'package:gossip/src/domain/entities/connected_peer.dart';
import 'package:gossip/src/application/ports/connected_peer_repository.dart';

/// Use case for performing a single gossip exchange with a specific connected peer.
///
/// This use case operates on transport-level peers (ConnectedPeer), avoiding any
/// requirement for a known GossipNodeID at selection time. It:
/// - Resolves the transport peer by address
/// - Builds and sends a digest
/// - Accepts any events in the response
/// - Fulfills event requests (fair-share across nodes, respecting a total cap)
/// - Updates reliability on the ConnectedPeer and persists it
class GossipWithConnectedPeerUseCase {
  final GossipTransport transport;
  final EventStore eventStore;
  final VectorClockService vectorClockService;
  final ConnectedPeerRepository connectedPeerRepository;

  /// Maximum total number of events to include when fulfilling requests.
  final int maxEventsPerMessage;

  /// Timeout to apply to transport operations.
  final Duration operationTimeout;

  GossipWithConnectedPeerUseCase({
    required this.transport,
    required this.eventStore,
    required this.vectorClockService,
    required this.connectedPeerRepository,
    this.maxEventsPerMessage = 100,
    this.operationTimeout = const Duration(seconds: 5),
  });

  /// Execute a single gossip exchange with [peer], returning the result metrics.
  Future<GossipExchangeResult> execute({
    required ConnectedPeer peer,
    required DateTime now,
  }) async {
    final started = now;
    var eventsExchanged = 0;
    String? error;
    var success = false;

    try {
      final transportPeer = await _findTransportPeerByAddress(peer.address);
      if (transportPeer == null) {
        throw StateError('Transport peer not found for ${peer.address}');
      }

      final digest = _buildDigest(now);
      final response = await transport.sendDigest(
        transportPeer,
        digest,
        timeout: operationTimeout,
      );

      eventsExchanged += await _acceptIncomingEvents(response);
      await _fulfillEventRequests(response, transportPeer, now);

      // Mark reliability success
      peer.recordSuccessfulContact();
      await connectedPeerRepository.save(peer);

      success = true;
    } catch (e) {
      error = e.toString();

      // Mark reliability failure
      peer.recordFailedContact();
      await connectedPeerRepository.save(peer);
    }

    return GossipExchangeResult(
      peer: _toGossipPeer(peer),
      success: success,
      eventsExchanged: eventsExchanged,
      duration: DateTime.now().difference(started),
      error: error,
    );
  }

  // --- Helpers ---

  Future<TransportPeer?> _findTransportPeerByAddress(
    TransportPeerAddress address,
  ) async {
    try {
      final peers = await transport.discoverPeers();
      for (final p in peers) {
        if (p.address == address) return p;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  GossipDigest _buildDigest(DateTime now) {
    return GossipDigest(
      senderId: GossipNodeID(vectorClockService.nodeId),
      vectorClock: vectorClockService.currentClock.summary,
      createdAt: now,
    );
  }

  Future<int> _acceptIncomingEvents(dynamic response) async {
    var exchanged = 0;
    final events = response.events as List<Event>? ?? const <Event>[];
    if (events.isEmpty) return 0;

    for (final event in events) {
      final exists = await eventStore.hasEvent(event.id);
      if (!exists) {
        await eventStore.saveEvent(event);
        exchanged++;
      }
    }
    return exchanged;
  }

  Future<void> _fulfillEventRequests(
    dynamic response,
    TransportPeer transportPeer,
    DateTime now,
  ) async {
    // Map<GossipNodeID, int> of requested events after a timestamp
    final requests =
        response.eventRequests as Map<GossipNodeID, int>? ?? const {};
    if (requests.isEmpty) return;

    final toSend = <Event>[];

    // Initialize cursors per node; we will fetch in fair-share rounds.
    final cursorTs = <GossipNodeID, int>{
      for (final e in requests.entries) e.key: e.value,
    };
    final pending = requests.keys.toList();

    var remaining = maxEventsPerMessage;
    while (remaining > 0 && pending.isNotEmpty) {
      var anyProgress = false;

      // Distribute remaining capacity fairly across nodes in this round.
      final perNodeChunk = remaining ~/ pending.length;
      final chunkSize = perNodeChunk > 0 ? perNodeChunk : 1;

      for (final nodeId in List<GossipNodeID>.from(pending)) {
        final afterTs = cursorTs[nodeId]!;
        final limit = chunkSize < remaining ? chunkSize : remaining;

        final batch = await eventStore.getEventsSince(
          nodeId,
          afterTs,
          limit: limit,
        );

        if (batch.isEmpty) {
          pending.remove(nodeId);
          continue;
        }

        final takeCount = batch.length > remaining ? remaining : batch.length;
        toSend.addAll(batch.take(takeCount));
        remaining -= takeCount;
        cursorTs[nodeId] = batch.last.timestamp;
        anyProgress = true;

        if (remaining <= 0) break;
      }

      if (!anyProgress) break;
    }

    if (toSend.isEmpty) return;

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

  GossipPeer _toGossipPeer(ConnectedPeer connected) {
    return GossipPeer(
      id: GossipNodeID('unknown'), // Unknown at transport-only stage
      address: connected.address,
      metadata: connected.metadata,
      lastContactTime: connected.lastContactTime,
      isActive: connected.isActive,
    );
  }
}
