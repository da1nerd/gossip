import 'package:gossip/src/domain/value_objects/clock_summary.dart';

import 'package:gossip/src/event.dart';
import 'package:gossip/src/gossip_node_id.dart';

/// Result of applying the admission policy to a batch of incoming events.
///
/// - [toPersist]: events that are newly accepted (i.e., not already known).
/// - [delta]: per-node clock summary representing the maximum timestamps
///   observed from the accepted events. This can be merged into the local
///   vector clock by taking the element-wise max.
class AdmissionResult {
  final List<Event> toPersist;
  final ClockSummary delta;

  const AdmissionResult({required this.toPersist, required this.delta});
}

/// Pure domain policy for deciding which incoming events to accept.
///
/// This policy requires the application layer to supply:
/// - The [incoming] events received from a peer.
/// - The set of [knownEventIds], representing events already stored locally.
///
/// The policy:
/// - Accepts events whose IDs are not already known (and not duplicated within
///   the incoming batch).
/// - Produces a [ClockSummary] delta where, for each node, the value is the
///   maximum timestamp among the accepted events from that node.
/// - Performs no I/O and has no side effects.
class EventAdmissionPolicy {
  static AdmissionResult admit({
    required Iterable<Event> incoming,
    required Set<String> knownEventIds,
  }) {
    final toPersist = <Event>[];
    final seenInBatch = <String>{}; // Prevent accepting duplicates within batch
    final perNodeMax = <GossipNodeID, int>{};

    for (final e in incoming) {
      final id = e.id;
      if (knownEventIds.contains(id)) continue; // Already persisted locally
      if (seenInBatch.contains(id)) continue; // Duplicate within this batch

      // Accept event
      toPersist.add(e);
      seenInBatch.add(id);

      // Track max timestamp per node to form the vector-clock delta
      final nodeId = e.nodeId;
      final prev = perNodeMax[nodeId] ?? 0;
      if (e.timestamp > prev) {
        perNodeMax[nodeId] = e.timestamp;
      }
    }

    return AdmissionResult(
      toPersist: toPersist,
      delta: ClockSummary(perNodeMax),
    );
  }
}
