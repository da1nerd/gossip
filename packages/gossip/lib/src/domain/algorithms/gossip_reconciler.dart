import 'package:gossip/src/domain/value_objects/clock_summary.dart';

import '../../gossip_node_id.dart';

/// Domain-pure reconciliation logic for gossip vector clocks.
/// This contains no I/O and depends only on typed inputs/outputs.
///
/// Given our clock summary and the peer's clock summary, it decides:
/// - Which events we should send to the peer (as SendSpec plans)
/// - Which events we should request from the peer (as a map of node -> timestamp)
/// - The merged clock summary (element-wise max) we should advance to
///
/// All node identifiers are strongly typed as GossipNodeID for safety.
class SendSpec {
  /// The node whose events should be sent.
  final GossipNodeID nodeId;

  /// We should send events strictly after this timestamp (exclusive).
  final int afterTimestampExclusive;

  /// Maximum number of events to send for this node in this plan.
  final int limit;

  SendSpec({
    required this.nodeId,
    required this.afterTimestampExclusive,
    required this.limit,
  });

  @override
  String toString() =>
      'SendSpec(nodeId: ${nodeId.value}, afterExclusive: $afterTimestampExclusive, limit: $limit)';

  @override
  bool operator ==(Object other) {
    return other is SendSpec &&
        other.nodeId == nodeId &&
        other.afterTimestampExclusive == afterTimestampExclusive &&
        other.limit == limit;
  }

  @override
  int get hashCode => Object.hash(nodeId, afterTimestampExclusive, limit);
}

class GossipPlan {
  /// Plans for what to send to the peer (determined purely from clock summaries).
  final List<SendSpec> toSendSpecs;

  /// For nodes where the peer is ahead, we request events strictly after
  /// the timestamp we have (value).
  final Map<GossipNodeID, int> requestsWeNeed;

  /// The merged clock summary (element-wise max) representing the join
  /// of our summary and the peer's summary.
  final ClockSummary mergedSummary;

  GossipPlan({
    required this.toSendSpecs,
    required this.requestsWeNeed,
    required this.mergedSummary,
  });

  @override
  String toString() =>
      'GossipPlan(sendSpecs: $toSendSpecs, requests: ${_reqToString()}, merged: $mergedSummary)';

  String _reqToString() =>
      '{${requestsWeNeed.entries.map((e) => '${e.key.value}: ${e.value}').join(', ')}}';
}

class GossipReconciler {
  /// Compute a reconciliation plan using only the per-node timestamps
  /// from each side's vector clock summaries.
  ///
  /// - For any node where [ours] is ahead of [peers], we add a [SendSpec] to
  ///   send events strictly after the peer's timestamp (exclusive).
  ///
  /// - For any node where [peers] is ahead of [ours], we add an entry to
  ///   [GossipPlan.requestsWeNeed] with our current timestamp (indicating we
  ///   want events strictly after that point).
  ///
  /// - The [mergedSummary] is the element-wise max (standard vector clock join).
  static GossipPlan plan({
    required ClockSummary ours,
    required ClockSummary peers,
    required int perNodeSendLimit,
  }) {
    final toSend = <SendSpec>[];
    final toRequest = <GossipNodeID, int>{};

    // Events we have that the peer likely lacks.
    for (final entry in ours.byNode.entries) {
      final nodeId = entry.key;
      final ourTs = entry.value;
      final peerTs = peers.byNode[nodeId] ?? 0;
      if (ourTs > peerTs) {
        toSend.add(
          SendSpec(
            nodeId: nodeId,
            afterTimestampExclusive: peerTs,
            limit: perNodeSendLimit,
          ),
        );
      }
    }

    // Events the peer likely has that we lack.
    for (final entry in peers.byNode.entries) {
      final nodeId = entry.key;
      final peerTs = entry.value;
      final ourTs = ours.byNode[nodeId] ?? 0;
      if (peerTs > ourTs) {
        toRequest[nodeId] = ourTs;
      }
    }

    // Merged summary is the element-wise max across both summaries.
    final merged = ours.mergedMax(peers);

    return GossipPlan(
      toSendSpecs: toSend,
      requestsWeNeed: toRequest,
      mergedSummary: merged,
    );
  }
}
