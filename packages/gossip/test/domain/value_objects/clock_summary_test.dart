import 'package:test/test.dart';
import 'package:gossip/src/domain/value_objects/clock_summary.dart';
import 'package:gossip/src/gossip_node_id.dart';

void main() {
  GossipNodeID nid(String v) => GossipNodeID(v);

  group('ClockSummary', () {
    test('constructor copies input and exposes an unmodifiable map', () {
      final input = {nid('a'): 1, nid('b'): 2};
      final summary = ClockSummary(input);

      // Mutate the original map after constructing the summary
      input[nid('a')] = 42;
      input[nid('c')] = 3;

      // The summary should not be affected (defensive copy)
      expect(summary.getTimestamp(nid('a')), 1);
      expect(summary.getTimestamp(nid('b')), 2);
      expect(summary.getTimestamp(nid('c')), 0);

      // Attempting to mutate the exposed map should throw
      expect(() => summary.byNode[nid('d')] = 5, throwsUnsupportedError);
    });

    test('fromStringMap and toStringMap roundtrip', () {
      final stringMap = <String, int>{'n1': 10, 'n2': 20, 'n3': 0};
      final typed = ClockSummary.fromStringMap(stringMap);

      expect(typed.getTimestamp(nid('n1')), 10);
      expect(typed.getTimestamp(nid('n2')), 20);
      expect(typed.getTimestamp(nid('n3')), 0);
      expect(typed.getTimestamp(nid('absent')), 0);

      // Should convert back to the original map
      expect(typed.toStringMap(), equals(stringMap));
    });

    test(
      'withTimestamp returns a new instance and does not mutate original',
      () {
        final original = ClockSummary.fromStringMap({'x': 1});
        final updated = original.withTimestamp(nid('y'), 5);

        // Original remains unchanged
        expect(original.getTimestamp(nid('x')), 1);
        expect(original.getTimestamp(nid('y')), 0);

        // Updated has the new timestamp
        expect(updated.getTimestamp(nid('x')), 1);
        expect(updated.getTimestamp(nid('y')), 5);

        // Instances must be different
        expect(identical(original, updated), isFalse);
        expect(original == updated, isFalse);
      },
    );

    test('mergedMax takes element-wise maximum across all node IDs', () {
      final a = ClockSummary.fromStringMap({'a': 1, 'b': 5});
      final b = ClockSummary.fromStringMap({'a': 3, 'c': 2});

      final merged = a.mergedMax(b);

      // Expect max per node: a: max(1,3)=3, b:5, c:2
      expect(merged.toStringMap(), equals({'a': 3, 'b': 5, 'c': 2}));

      // Commutative property for merge max
      final merged2 = b.mergedMax(a);
      expect(merged2, equals(merged));
    });

    test('dominates returns true when lhs >= rhs for all nodes', () {
      final lhs = ClockSummary.fromStringMap({'x': 5, 'y': 2});
      final rhs = ClockSummary.fromStringMap({'x': 5, 'y': 1});
      final other = ClockSummary.fromStringMap({'x': 6, 'y': 3});

      // lhs dominates rhs
      expect(lhs.dominates(rhs), isTrue);
      // rhs does not dominate lhs
      expect(rhs.dominates(lhs), isFalse);
      // other dominates lhs
      expect(other.dominates(lhs), isTrue);
      // Missing keys are treated as 0, so these should dominate each other
      final a = ClockSummary.fromStringMap({'z': 1});
      final b = ClockSummary.fromStringMap({'z': 1, 'w': 0});
      expect(a.dominates(b), isTrue);
      expect(b.dominates(a), isTrue);
    });

    test('equality and hashCode consider per-node timestamps', () {
      final s1 = ClockSummary.fromStringMap({'a': 1, 'b': 2});
      final s2 = ClockSummary({nid('a'): 1, nid('b'): 2});
      final s3 = ClockSummary.fromStringMap({'a': 1, 'b': 3});

      expect(s1, equals(s2));
      expect(s1.hashCode, equals(s2.hashCode));

      expect(s1 == s3, isFalse);
      expect(s1.hashCode == s3.hashCode, isFalse);
    });

    test('getTimestamp returns 0 for unknown node IDs', () {
      final s = ClockSummary.fromStringMap({'known': 7});
      expect(s.getTimestamp(nid('known')), 7);
      expect(s.getTimestamp(nid('unknown')), 0);
    });

    test('toString contains the underlying map for quick debugging', () {
      final s = ClockSummary.fromStringMap({'dbg': 9});
      final t = s.toString();
      // Not asserting the entire format, just that it includes the key and value
      expect(t.contains('dbg'), isTrue);
      expect(t.contains('9'), isTrue);
    });
  });
}
