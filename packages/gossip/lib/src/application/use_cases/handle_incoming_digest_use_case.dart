import 'package:gossip/src/event.dart';
import 'package:gossip/src/event_store.dart';
import 'package:gossip/src/gossip_digest.dart';
import 'package:gossip/src/gossip_digest_response.dart';
import 'package:gossip/src/gossip_node_id.dart';
import 'package:gossip/src/vector_clock.dart';
import 'package:gossip/src/application/services/vector_clock_service.dart';
import 'package:gossip/src/domain/value_objects/clock_summary.dart';
import 'package:gossip/src/domain/algorithms/gossip_reconciler.dart';

/// Use case for handling an incoming gossip digest (anti-entropy step).
///
/// This orchestrates the pure domain reconciler with the infrastructure:
/// - Computes a reconciliation plan using the domain (pure)
/// - Fetches the concrete events to send based on the plan (I/O)
/// - Advances our local vector clock to the merged summary (I/O)
/// - Returns the `GossipDigestResponse` for the caller to send over transport
class HandleIncomingDigestUseCase {
  final EventStore eventStore;
  final VectorClockService vectorClockService;

  /// Maximum number of events to include in a single response (total cap).
  /// Kept in the application layer to avoid coupling the domain to configuration.
  final int maxEventsPerMessage;

  HandleIncomingDigestUseCase({
    required this.eventStore,
    required this.vectorClockService,
    this.maxEventsPerMessage = 50,
  });

  /// Builds a response to an incoming digest.
  ///
  /// The caller is responsible for sending the returned response over the transport.
  Future<GossipDigestResponse> createResponse({
    required GossipDigest incoming,
    required DateTime now,
  }) async {
    final ours = _ourSummary();
    final peers = _peerSummary(incoming);
    final plan = _computePlan(ours, peers);
    final eventsToSend = await _collectEventsFairShare(plan);
    await _advanceClock(plan);
    return _buildResponse(eventsToSend, plan, now);
  }

  // Build our current summary from the vector clock service.
  ClockSummary _ourSummary() {
    return ClockSummary.fromStringMap(vectorClockService.currentClock.summary);
  }

  // Build the peer's summary from the incoming digest.
  ClockSummary _peerSummary(GossipDigest incoming) {
    return ClockSummary.fromStringMap(incoming.vectorClock);
  }

  // Compute a reconciliation plan describing what to send/request and the merged clock.
  GossipPlan _computePlan(ClockSummary ours, ClockSummary peers) {
    return GossipReconciler.plan(
      ours: ours,
      peers: peers,
      perNodeSendLimit: maxEventsPerMessage,
    );
  }

  // Collect events to send using a fair-share allocator across nodes,
  // respecting the total message cap.
  Future<List<Event>> _collectEventsFairShare(GossipPlan plan) async {
    final eventsToSend = <Event>[];
    var remaining = maxEventsPerMessage;

    // Initialize per-node cursors from send specs
    final Map<GossipNodeID, int> cursorTs = {
      for (final spec in plan.toSendSpecs)
        spec.nodeId: spec.afterTimestampExclusive,
    };
    final pending = cursorTs.keys.toList();

    while (remaining > 0 && pending.isNotEmpty) {
      var anyProgress = false;

      // Distribute capacity fairly across nodes this round
      final perNodeChunk = remaining ~/ pending.length;
      final chunkSize = perNodeChunk > 0 ? perNodeChunk : 1;

      // Round-robin across pending nodes
      for (final nodeId in List<GossipNodeID>.from(pending)) {
        final afterTs = cursorTs[nodeId]!;
        final limit = chunkSize < remaining ? chunkSize : remaining;

        final batch = await eventStore.getEventsSince(
          nodeId,
          afterTs,
          limit: limit,
        );

        if (batch.isEmpty) {
          // No more for this node
          pending.remove(nodeId);
          continue;
        }

        // Append up to remaining capacity and advance cursor to last timestamp
        final takeCount = batch.length > remaining ? remaining : batch.length;
        eventsToSend.addAll(batch.take(takeCount));
        remaining -= takeCount;
        cursorTs[nodeId] = batch.last.timestamp;
        anyProgress = true;

        if (remaining <= 0) break;
      }

      if (!anyProgress) {
        // No node produced events; stop
        break;
      }
    }

    return eventsToSend;
  }

  // Advance our local vector clock to the merged summary from the plan.
  Future<void> _advanceClock(GossipPlan plan) async {
    final merged = VectorClock.fromMap(plan.mergedSummary.toStringMap());
    vectorClockService.update(merged);
    await vectorClockService.save();
  }

  // Build the final response to return to the transport layer.
  GossipDigestResponse _buildResponse(
    List<Event> eventsToSend,
    GossipPlan plan,
    DateTime now,
  ) {
    return GossipDigestResponse(
      senderId: GossipNodeID(vectorClockService.nodeId),
      events: eventsToSend,
      eventRequests: plan.requestsWeNeed,
      createdAt: now,
    );
  }
}
