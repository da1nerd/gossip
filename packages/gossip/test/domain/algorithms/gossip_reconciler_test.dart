import 'package:test/test.dart';
import 'package:gossip/src/domain/algorithms/gossip_reconciler.dart';
import 'package:gossip/src/domain/value_objects/clock_summary.dart';
import 'package:gossip/src/gossip_node_id.dart';

void main() {
  GossipNodeID nid(String v) => GossipNodeID(v);

  SendSpec? specForNode(List<SendSpec> specs, GossipNodeID nodeId) {
    return specs.where((s) => s.nodeId == nodeId).cast<SendSpec?>().firstOrNull;
  }

  group('GossipReconciler.plan', () {
    test(
      'creates SendSpecs for nodes where we are ahead, requests where peer is ahead, and merges clocks',
      () {
        final ours = ClockSummary.fromStringMap({'A': 5, 'B': 1});
        final peers = ClockSummary.fromStringMap({'A': 3, 'C': 2});

        final plan = GossipReconciler.plan(
          ours: ours,
          peers: peers,
          perNodeSendLimit: 50,
        );

        // We have A:5 vs peer A:3 => send after 3; limit propagated
        final aSpec = specForNode(plan.toSendSpecs, nid('A'));
        expect(aSpec, isNotNull);
        expect(aSpec!.afterTimestampExclusive, 3);
        expect(aSpec.limit, 50);

        // We have B:1 vs peer B:0 (missing) => send after 0; limit propagated
        final bSpec = specForNode(plan.toSendSpecs, nid('B'));
        expect(bSpec, isNotNull);
        expect(bSpec!.afterTimestampExclusive, 0);
        expect(bSpec.limit, 50);

        // Peer has C:2 vs our C:0 (missing) => request after 0
        expect(plan.requestsWeNeed.length, 1);
        expect(plan.requestsWeNeed[nid('C')], 0);

        // Merged is max per node
        expect(
          plan.mergedSummary.toStringMap(),
          equals({'A': 5, 'B': 1, 'C': 2}),
        );
      },
    );

    test('perNodeSendLimit propagates to every SendSpec', () {
      final ours = ClockSummary.fromStringMap({'N1': 10, 'N2': 1});
      final peers = ClockSummary.fromStringMap({'N1': 5}); // N2 missing -> 0

      final plan = GossipReconciler.plan(
        ours: ours,
        peers: peers,
        perNodeSendLimit: 2,
      );

      // We expect specs for N1 and N2 with limit=2
      expect(plan.toSendSpecs.length, 2);
      for (final s in plan.toSendSpecs) {
        expect(s.limit, 2);
      }
    });

    test('no send specs or requests when clocks are equal', () {
      final ours = ClockSummary.fromStringMap({'X': 7});
      final peers = ClockSummary.fromStringMap({'X': 7});

      final plan = GossipReconciler.plan(
        ours: ours,
        peers: peers,
        perNodeSendLimit: 10,
      );

      expect(plan.toSendSpecs, isEmpty);
      expect(plan.requestsWeNeed, isEmpty);
      expect(plan.mergedSummary.toStringMap(), equals({'X': 7}));
    });

    test('disjoint ahead states produce both send and request specs', () {
      final ours = ClockSummary.fromStringMap({'X': 1}); // ahead on X
      final peers = ClockSummary.fromStringMap({'Y': 2}); // ahead on Y

      final plan = GossipReconciler.plan(
        ours: ours,
        peers: peers,
        perNodeSendLimit: 5,
      );

      // Send X after 0
      final xSpec = specForNode(plan.toSendSpecs, nid('X'));
      expect(xSpec, isNotNull);
      expect(xSpec!.afterTimestampExclusive, 0);
      expect(xSpec.limit, 5);

      // Request Y after ourTs (0)
      expect(plan.requestsWeNeed[nid('Y')], 0);

      // Merged summary max per node
      expect(plan.mergedSummary.toStringMap(), equals({'X': 1, 'Y': 2}));
    });

    test(
      'requestsWeNeed keys are typed GossipNodeID and values reflect our current timestamps',
      () {
        final ours = ClockSummary.fromStringMap({'A': 1});
        final peers = ClockSummary.fromStringMap({'A': 5, 'B': 3});

        final plan = GossipReconciler.plan(
          ours: ours,
          peers: peers,
          perNodeSendLimit: 100,
        );

        // For A: peer 5 > our 1 -> request after 1
        expect(plan.requestsWeNeed[nid('A')], 1);
        // For B: peer 3 > our 0 -> request after 0
        expect(plan.requestsWeNeed[nid('B')], 0);

        // Keys are GossipNodeID instances
        for (final k in plan.requestsWeNeed.keys) {
          expect(k, isA<GossipNodeID>());
        }
      },
    );

    test('no specs are produced when we are never strictly ahead', () {
      final ours = ClockSummary.fromStringMap({'A': 1, 'B': 2});
      final peers = ClockSummary.fromStringMap({'A': 2, 'B': 2, 'C': 10});

      final plan = GossipReconciler.plan(
        ours: ours,
        peers: peers,
        perNodeSendLimit: 100,
      );

      // We are not strictly ahead for any node -> no toSendSpecs
      expect(plan.toSendSpecs, isEmpty);

      // Requests for nodes where peer is ahead
      expect(plan.requestsWeNeed[nid('A')], 1); // after our A
      expect(plan.requestsWeNeed[nid('C')], 0); // we don't have C
      expect(
        plan.requestsWeNeed.containsKey(nid('B')),
        isFalse,
      ); // equal -> no request

      // Merged summary max per node
      expect(
        plan.mergedSummary.toStringMap(),
        equals({'A': 2, 'B': 2, 'C': 10}),
      );
    });
  });
}
