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
    // Build typed summaries for the pure domain reconciler
    final ours = ClockSummary.fromStringMap(
      vectorClockService.currentClock.summary,
    );
    final peers = ClockSummary.fromStringMap(incoming.vectorClock);

    // Compute a domain-pure reconciliation plan
    final plan = GossipReconciler.plan(
      ours: ours,
      peers: peers,
      perNodeSendLimit: maxEventsPerMessage,
    );

    // Fulfill SendSpecs by fetching concrete events to send (respect total cap)
    final eventsToSend = <Event>[];
    for (final spec in plan.toSendSpecs) {
      final remaining = maxEventsPerMessage - eventsToSend.length;
      if (remaining <= 0) break;

      final limit = remaining < spec.limit ? remaining : spec.limit;

      final batch = await eventStore.getEventsSince(
        spec.nodeId,
        spec.afterTimestampExclusive,
        limit: limit,
      );
      if (batch.isNotEmpty) {
        // Defensive trim in case store returns more than requested
        final needed = maxEventsPerMessage - eventsToSend.length;
        if (batch.length > needed) {
          eventsToSend.addAll(batch.take(needed));
        } else {
          eventsToSend.addAll(batch);
        }
      }
    }

    // Advance our local clock to the merged summary (element-wise max)
    final merged = VectorClock.fromMap(plan.mergedSummary.toStringMap());
    vectorClockService.update(merged);
    await vectorClockService.save();

    // Build the response for the transport layer to send
    return GossipDigestResponse(
      senderId: GossipNodeID(vectorClockService.nodeId),
      events: eventsToSend,
      eventRequests: plan.requestsWeNeed,
      createdAt: now,
    );
  }
}
