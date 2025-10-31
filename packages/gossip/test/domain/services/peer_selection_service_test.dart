import 'dart:math' as math;
import 'package:test/test.dart';
import 'package:gossip/src/domain/services/peer_selection_service.dart';
import 'package:gossip/src/domain/entities/internal_gossip_peer.dart';
import 'package:gossip/src/gossip_config.dart';
import 'package:gossip/src/gossip_node_id.dart';
import 'package:gossip/src/transport.dart';
import '../../test_config.dart';
import '../test_helpers.dart';

void main() {
  group('PeerSelectionService', () {
    late PeerSelectionService service;
    late List<InternalGossipPeer> testPeers;

    setUp(() {
      service = PeerSelectionService();
      testPeers = DomainTestHelpers.createTestPeers(5);
    });

    group('Constructor', () {
      test('creates service with default random generator', () {
        final service = PeerSelectionService();
        expect(service, isNotNull);
      });

      test('creates service with custom random generator', () {
        final customRandom = math.Random(12345); // Seeded for predictability
        final service = PeerSelectionService(random: customRandom);
        expect(service, isNotNull);
      });
    });

    group('selectPeersForGossip', () {
      test('returns empty list when no peers available', () {
        final result = service.selectPeersForGossip(
          [],
          5,
          PeerSelectionStrategy.random,
        );
        expect(result, isEmpty);
      });

      test('returns empty list when no active peers available', () {
        final inactivePeers = testPeers.map((peer) {
          // Make all peers inactive
          for (int i = 0; i < 3; i++) {
            peer.recordFailedContact();
          }
          return peer;
        }).toList();

        final result = service.selectPeersForGossip(
          inactivePeers,
          5,
          PeerSelectionStrategy.random,
        );
        expect(result, isEmpty);
      });

      test('filters out inactive peers', () {
        // Make first peer inactive
        testPeers[0].recordFailedContact();
        testPeers[0].recordFailedContact();
        testPeers[0].recordFailedContact();

        final result = service.selectPeersForGossip(
          testPeers,
          10,
          PeerSelectionStrategy.random,
        );

        expect(result, isNot(contains(testPeers[0])));
        expect(result.length, equals(testPeers.length - 1));
      });

      test('respects maxPeers limit', () {
        final result = service.selectPeersForGossip(
          testPeers,
          2,
          PeerSelectionStrategy.random,
        );
        expect(result.length, equals(2));
      });

      test('returns all peers when maxPeers exceeds available peers', () {
        final result = service.selectPeersForGossip(
          testPeers.take(2).toList(),
          10,
          PeerSelectionStrategy.random,
        );
        expect(result.length, equals(2));
      });
    });

    group('Random Selection Strategy', () {
      test('selects peers randomly', () {
        // Use seeded random for reproducible results
        final seededService = PeerSelectionService(random: math.Random(42));

        final result1 = seededService.selectPeersForGossip(
          testPeers,
          3,
          PeerSelectionStrategy.random,
        );

        // Reset to same seed for second call
        final seededService2 = PeerSelectionService(random: math.Random(42));
        final result2 = seededService2.selectPeersForGossip(
          testPeers,
          3,
          PeerSelectionStrategy.random,
        );

        // Should get same results with same seed
        expect(result1.length, equals(result2.length));
        for (int i = 0; i < result1.length; i++) {
          expect(result1[i].nodeId, equals(result2[i].nodeId));
        }
      });

      test('returns different selections with different random seeds', () {
        final service1 = PeerSelectionService(random: math.Random(1));
        final service2 = PeerSelectionService(random: math.Random(2));

        final result1 = service1.selectPeersForGossip(
          testPeers,
          testPeers.length,
          PeerSelectionStrategy.random,
        );

        final result2 = service2.selectPeersForGossip(
          testPeers,
          testPeers.length,
          PeerSelectionStrategy.random,
        );

        // With different seeds, order should likely be different
        bool orderDiffers = false;
        for (int i = 0; i < result1.length; i++) {
          if (result1[i].nodeId != result2[i].nodeId) {
            orderDiffers = true;
            break;
          }
        }
        expect(orderDiffers, isTrue);
      });

      statisticalTest(
        'selects each peer with roughly equal probability over many iterations',
        (iteration) {
          final selected = service.selectPeersForGossip(
            testPeers,
            2,
            PeerSelectionStrategy.random,
          );

          return {
            'selectedPeers': selected.map((p) => p.nodeId.value).toList(),
          };
        },
        validator: (results) {
          // Count selections for each peer
          final selectionCounts = <String, int>{};
          for (final peer in testPeers) {
            selectionCounts[peer.nodeId.value] = 0;
          }

          final allSelections = results['selectedPeers']!;
          for (final selectionList in allSelections) {
            for (final peerId in selectionList as List<String>) {
              selectionCounts[peerId] = selectionCounts[peerId]! + 1;
            }
          }

          // Validate distribution fairness
          final totalSelections = selectionCounts.values.reduce(
            (a, b) => a + b,
          );
          final expectedPerPeer = totalSelections / testPeers.length;
          final tolerance = expectedPerPeer * 0.3; // 30% tolerance

          for (final entry in selectionCounts.entries) {
            expect(
              entry.value.toDouble(),
              closeTo(expectedPerPeer, tolerance),
              reason: 'Peer ${entry.key} selection should be roughly uniform',
            );
          }
        },
        iterations: 1000,
      );
    });

    group('Round Robin Selection Strategy', () {
      test('selects peers in round-robin order', () {
        final result1 = service.selectPeersForGossip(
          testPeers,
          2,
          PeerSelectionStrategy.roundRobin,
        );

        final result2 = service.selectPeersForGossip(
          testPeers,
          2,
          PeerSelectionStrategy.roundRobin,
        );

        // First selection should start from index 0
        expect(result1[0], equals(testPeers[0]));
        expect(result1[1], equals(testPeers[1]));

        // Second selection should continue from where first left off
        expect(result2[0], equals(testPeers[2]));
        expect(result2[1], equals(testPeers[3]));
      });

      test('wraps around when reaching end of peer list', () {
        final smallPeerList = testPeers.take(3).toList();

        final result1 = service.selectPeersForGossip(
          smallPeerList,
          2,
          PeerSelectionStrategy.roundRobin,
        );

        final result2 = service.selectPeersForGossip(
          smallPeerList,
          2,
          PeerSelectionStrategy.roundRobin,
        );

        // First call: peers 0, 1
        expect(result1[0], equals(smallPeerList[0]));
        expect(result1[1], equals(smallPeerList[1]));

        // Second call should wrap: peer 2, then wrap to 0
        expect(result2[0], equals(smallPeerList[2]));
        expect(result2[1], equals(smallPeerList[0]));
      });

      test('handles case where selection count equals peer count', () {
        final result = service.selectPeersForGossip(
          testPeers,
          testPeers.length,
          PeerSelectionStrategy.roundRobin,
        );

        expect(result.length, equals(testPeers.length));

        // Should maintain order
        for (int i = 0; i < result.length; i++) {
          expect(result[i], equals(testPeers[i]));
        }
      });

      test('maintains state between calls', () {
        // Select 1 peer
        final result1 = service.selectPeersForGossip(
          testPeers,
          1,
          PeerSelectionStrategy.roundRobin,
        );

        // Select 1 more peer
        final result2 = service.selectPeersForGossip(
          testPeers,
          1,
          PeerSelectionStrategy.roundRobin,
        );

        expect(result1[0], equals(testPeers[0]));
        expect(result2[0], equals(testPeers[1]));
      });
    });

    group('Least Recently Contacted Selection Strategy', () {
      test('selects peers with no contact time first', () {
        // Give some peers contact times
        testPeers[0].recordSuccessfulContact();
        testPeers[1].recordSuccessfulContact();

        final result = service.selectPeersForGossip(
          testPeers,
          3,
          PeerSelectionStrategy.leastRecentlyContacted,
        );

        // Should prefer peers with no contact time over those with contact time
        // The exact peers selected may vary, but should prioritize uncontacted peers
        expect(result.length, equals(3));

        // At least one of the uncontacted peers should be selected
        final uncontactedPeers = [testPeers[2], testPeers[3], testPeers[4]];
        final selectedUncontacted = result
            .where(
              (peer) => uncontactedPeers.any((up) => up.nodeId == peer.nodeId),
            )
            .length;
        expect(selectedUncontacted, greaterThan(0));
      });

      test('selects peers in order of least recent contact', () {
        final baseTime = DateTime.now().subtract(const Duration(hours: 1));

        // Set up different contact times
        testPeers[0].recordSuccessfulContact(); // Most recent (now)

        // Simulate older contact times by directly setting them
        final peer1 = InternalGossipPeer(
          nodeId: testPeers[1].nodeId,
          address: testPeers[1].address,
          lastContactTime: baseTime.subtract(const Duration(minutes: 30)),
        );

        final peer2 = InternalGossipPeer(
          nodeId: testPeers[2].nodeId,
          address: testPeers[2].address,
          lastContactTime: baseTime.subtract(const Duration(minutes: 10)),
        );

        final peer3 = InternalGossipPeer(
          nodeId: testPeers[3].nodeId,
          address: testPeers[3].address,
          lastContactTime: baseTime.subtract(const Duration(minutes: 45)),
        );

        final peersWithTimes = [testPeers[0], peer1, peer2, peer3];

        final result = service.selectPeersForGossip(
          peersWithTimes,
          3,
          PeerSelectionStrategy.leastRecentlyContacted,
        );

        // Should select in order: peer3 (45 min ago), peer1 (30 min ago), peer2 (10 min ago)
        // testPeers[0] contacted most recently should not be selected
        expect(result[0].nodeId, equals(peer3.nodeId));
        expect(result[1].nodeId, equals(peer1.nodeId));
        expect(result[2].nodeId, equals(peer2.nodeId));
      });

      test('treats peers with no contact time as least recently contacted', () {
        // Give one peer a recent contact time
        testPeers[0].recordSuccessfulContact();

        final result = service.selectPeersForGossip(
          testPeers,
          3,
          PeerSelectionStrategy.leastRecentlyContacted,
        );

        // Should prefer the 3 peers with no contact time over the one with recent contact
        expect(result, isNot(contains(testPeers[0])));
        expect(result.length, equals(3));
      });
    });

    group('Most Reliable Selection Strategy', () {
      test('selects peers with highest reliability scores', () {
        // Set up different reliability scores
        // testPeers[0] - perfect score (no contacts)
        testPeers[1].recordSuccessfulContact(); // Still perfect after success
        testPeers[2].recordFailedContact(); // Reduced score
        testPeers[3].recordFailedContact(); // Even more reduced
        testPeers[3].recordFailedContact();

        final result = service.selectPeersForGossip(
          testPeers,
          2,
          PeerSelectionStrategy.mostReliable,
        );

        // Should select the two most reliable peers
        expect(result, contains(testPeers[0])); // Perfect initial score
        expect(result, contains(testPeers[1])); // Perfect after success
        expect(result, isNot(contains(testPeers[2]))); // Reduced score
        expect(result, isNot(contains(testPeers[3]))); // Lowest score
      });

      test('orders peers by descending reliability score', () {
        // Create graduated reliability scores
        // testPeers[0] - default perfect (1.0)
        testPeers[1].recordSuccessfulContact(); // Still 1.0

        testPeers[2].recordFailedContact(); // Reduced

        testPeers[3].recordFailedContact(); // More reduced
        testPeers[3].recordFailedContact();

        final result = service.selectPeersForGossip(
          testPeers,
          testPeers.length,
          PeerSelectionStrategy.mostReliable,
        );

        // Should be ordered by reliability (highest first)
        double previousScore = double.infinity;
        for (final peer in result) {
          expect(peer.reliabilityScore, lessThanOrEqualTo(previousScore));
          previousScore = peer.reliabilityScore;
        }
      });

      test('handles peers with equal reliability scores', () {
        // All peers have same default reliability
        final result = service.selectPeersForGossip(
          testPeers,
          2,
          PeerSelectionStrategy.mostReliable,
        );

        expect(result.length, equals(2));
        // Should select some peers (exact selection may vary but should be deterministic)
        expect(result.every((peer) => peer.reliabilityScore == 1.0), isTrue);
      });

      test('handles peers with zero reliability', () {
        // Create a peer with very low reliability through many failures
        for (int i = 0; i < 20; i++) {
          testPeers[0].recordFailedContact();
        }

        // Note: testPeers[0] is now inactive due to consecutive failures
        expect(testPeers[0].isActive, isFalse);

        final result = service.selectPeersForGossip(
          testPeers,
          testPeers.length,
          PeerSelectionStrategy.mostReliable,
        );

        // Should exclude inactive peers, even if they have history
        expect(result, isNot(contains(testPeers[0])));
        expect(result.length, equals(testPeers.length - 1)); // All active peers
      });
    });

    group('Strategy Enum Coverage', () {
      test('handles all defined peer selection strategies', () {
        // Verify all enum values are handled
        for (final strategy in PeerSelectionStrategy.values) {
          expect(
            () => service.selectPeersForGossip(testPeers, 2, strategy),
            returnsNormally,
            reason: 'Strategy $strategy should be supported',
          );
        }
      });
    });

    group('Edge Cases', () {
      test('handles single peer selection', () {
        final result = service.selectPeersForGossip(
          testPeers,
          1,
          PeerSelectionStrategy.random,
        );

        expect(result.length, equals(1));
        expect(testPeers, contains(result[0]));
      });

      test('handles zero peer selection request', () {
        final result = service.selectPeersForGossip(
          testPeers,
          0,
          PeerSelectionStrategy.random,
        );

        expect(result, isEmpty);
      });

      test('handles negative peer selection request gracefully', () {
        final result = service.selectPeersForGossip(
          testPeers,
          -1,
          PeerSelectionStrategy.random,
        );

        expect(result, isEmpty);
      });

      test('handles mixed active/inactive peers correctly', () {
        // Make every other peer inactive
        for (int i = 0; i < testPeers.length; i += 2) {
          testPeers[i].recordFailedContact();
          testPeers[i].recordFailedContact();
          testPeers[i].recordFailedContact();
        }

        final activePeerCount = testPeers.where((p) => p.isActive).length;

        final result = service.selectPeersForGossip(
          testPeers,
          10,
          PeerSelectionStrategy.random,
        );

        expect(result.length, equals(activePeerCount));
        expect(result.every((peer) => peer.isActive), isTrue);
      });
    });

    group('Performance and Consistency', () {
      test('maintains consistent selection with same input', () {
        final seededService = PeerSelectionService(random: math.Random(123));

        final result1 = seededService.selectPeersForGossip(
          testPeers,
          3,
          PeerSelectionStrategy.random,
        );

        final seededService2 = PeerSelectionService(random: math.Random(123));
        final result2 = seededService2.selectPeersForGossip(
          testPeers,
          3,
          PeerSelectionStrategy.random,
        );

        expect(result1.length, equals(result2.length));
        for (int i = 0; i < result1.length; i++) {
          expect(result1[i].nodeId, equals(result2[i].nodeId));
        }
      });

      test('handles large peer lists efficiently', () {
        final largePeerList = DomainTestHelpers.createTestPeers(1000);

        final stopwatch = Stopwatch()..start();

        final result = service.selectPeersForGossip(
          largePeerList,
          50,
          PeerSelectionStrategy.random,
        );

        stopwatch.stop();

        expect(result.length, equals(50));
        expect(stopwatch.elapsedMilliseconds, lessThan(100)); // Should be fast
      });
    });
  });
}
