import 'package:test/test.dart';
import 'package:gossip/src/domain/policies/event_admission_policy.dart';
import 'package:gossip/src/event.dart';
import 'package:gossip/src/gossip_node_id.dart';

void main() {
  Event ev(String id, String node, int ts, {int? createdMs}) => Event(
    id: id,
    nodeId: GossipNodeID(node),
    timestamp: ts,
    creationTimestamp: createdMs ?? (1000000 + ts),
    payload: const {},
  );

  group('EventAdmissionPolicy', () {
    test(
      'rejects known events and de-duplicates within the incoming batch',
      () {
        final incoming = <Event>[
          ev('e1', 'A', 5), // unknown
          ev('e2', 'A', 6), // known -> reject
          ev('e3', 'B', 7), // unknown
          ev('e3', 'B', 8), // duplicate id in same batch -> reject
        ];

        final known = <String>{'e2'};

        final result = EventAdmissionPolicy.admit(
          incoming: incoming,
          knownEventIds: known,
        );

        // Expect only unknown and first occurrences to be persisted
        expect(
          result.toPersist.map((e) => e.id).toList(),
          equals(['e1', 'e3']),
        );

        // Delta should include per-node max from accepted events only
        // e1 -> A:5, e3 (first instance only) -> B:7
        expect(result.delta.toStringMap(), equals({'A': 5, 'B': 7}));
      },
    );

    test('computes per-node max across multiple admitted events', () {
      final incoming = <Event>[
        ev('c1', 'C', 1),
        ev('c2', 'C', 9), // higher for C
        ev('d1', 'D', 3),
      ];

      final result = EventAdmissionPolicy.admit(
        incoming: incoming,
        knownEventIds: const {},
      );

      expect(
        result.toPersist.map((e) => e.id).toList(),
        equals(['c1', 'c2', 'd1']),
      );
      expect(result.delta.toStringMap(), equals({'C': 9, 'D': 3}));
    });

    test('returns empty result when incoming list is empty', () {
      final result = EventAdmissionPolicy.admit(
        incoming: const <Event>[],
        knownEventIds: const {},
      );

      expect(result.toPersist, isEmpty);
      expect(result.delta.byNode, isEmpty);
    });

    test('ignores known events when computing delta', () {
      final incoming = <Event>[
        ev('k1', 'N', 100), // known, should be ignored
        ev('u1', 'N', 50), // unknown, should be considered
      ];

      final result = EventAdmissionPolicy.admit(
        incoming: incoming,
        knownEventIds: const {'k1'},
      );

      expect(result.toPersist.map((e) => e.id).toList(), equals(['u1']));
      // Only 'u1' contributes to delta since 'k1' is known
      expect(result.delta.toStringMap(), equals({'N': 50}));
    });

    test('interleaved duplicate IDs admit only the first occurrence', () {
      final incoming = <Event>[
        ev('dup', 'X', 1),
        ev('dup', 'X', 10), // later duplicate with higher ts should be ignored
        ev('ok', 'Y', 3),
      ];

      final result = EventAdmissionPolicy.admit(
        incoming: incoming,
        knownEventIds: const {},
      );

      expect(result.toPersist.map((e) => e.id).toList(), equals(['dup', 'ok']));
      // Delta must reflect only admitted events, so X uses timestamp 1, not 10
      expect(result.delta.toStringMap(), equals({'X': 1, 'Y': 3}));
    });
  });
}
