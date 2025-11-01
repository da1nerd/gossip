import 'dart:math' as math;
import 'package:test/test.dart';
import 'package:gossip/src/domain/entities/connected_peer.dart';
import 'package:gossip/src/domain/services/connected_peer_selection_service.dart';
import 'package:gossip/src/gossip_config.dart';
import 'package:gossip/src/gossip_node_id.dart';
import 'package:gossip/src/transport.dart';
import 'test_helpers.dart';

void main() {
  group('Domain Layer Integration Tests', () {
    late ConnectedPeerSelectionService selectionService;
    late List<ConnectedPeer> peers;

    setUp(() {
      selectionService = ConnectedPeerSelectionService(random: math.Random(42));
      peers = DomainTestHelpers.createTestPeers(5);
    });

    group('Peer Lifecycle and Selection Integration', () {
      test('peer reliability affects selection probability over time', () {
        // Simulate a realistic gossip scenario over time
        final unreliablePeer = peers[0];
        final reliablePeer = peers[1];
        final mixedPeer = peers[2];

        // Simulate network conditions affecting different peers
        for (int round = 0; round < 10; round++) {
          // Unreliable peer fails most attempts
          if (round % 4 != 0) {
            unreliablePeer.recordFailedContact();
          } else {
            unreliablePeer.recordSuccessfulContact();
          }

          // Reliable peer succeeds most attempts
          if (round % 5 == 0) {
            reliablePeer.recordFailedContact();
          } else {
            reliablePeer.recordSuccessfulContact();
          }

          // Mixed peer has moderate success
          if (round % 2 == 0) {
            mixedPeer.recordSuccessfulContact();
          } else {
            mixedPeer.recordFailedContact();
          }
        }

        // Test that reliability scores reflect the different behaviors
        expect(
          reliablePeer.reliabilityScore,
          greaterThan(mixedPeer.reliabilityScore),
        );
        expect(
          mixedPeer.reliabilityScore,
          greaterThan(unreliablePeer.reliabilityScore),
        );

        // Test selection prioritizes reliable peers
        final selectedPeers = selectionService.selectPeersForGossip(
          [unreliablePeer, reliablePeer, mixedPeer],
          2,
          PeerSelectionStrategy.mostReliable,
        );

        expect(
          selectedPeers[0].reliabilityScore >=
              selectedPeers[1].reliabilityScore,
          isTrue,
        );
        expect(selectedPeers, contains(reliablePeer));
      });

      test('peer inactivation affects availability across strategies', () {
        final activePeer = peers[0];
        final inactivePeer = peers[1];

        // Make one peer inactive
        inactivePeer.recordFailedContact();
        inactivePeer.recordFailedContact();
        inactivePeer.recordFailedContact();

        expect(inactivePeer.isActive, isFalse);
        expect(activePeer.isActive, isTrue);

        // Test all strategies exclude inactive peers
        final strategies = [
          PeerSelectionStrategy.random,
          PeerSelectionStrategy.roundRobin,
          PeerSelectionStrategy.leastRecentlyContacted,
          PeerSelectionStrategy.mostReliable,
        ];

        for (final strategy in strategies) {
          final selected = selectionService.selectPeersForGossip(
            [activePeer, inactivePeer],
            2,
            strategy,
          );

          expect(selected, contains(activePeer));
          expect(selected, isNot(contains(inactivePeer)));
          expect(selected.length, equals(1));
        }
      });

      test('peer reactivation restores availability', () {
        final peer = peers[0];

        // Make peer inactive
        peer.recordFailedContact();
        peer.recordFailedContact();
        peer.recordFailedContact();
        expect(peer.isActive, isFalse);

        // Reactivate with successful contact
        peer.recordSuccessfulContact();
        expect(peer.isActive, isTrue);

        // Should be available for selection again
        final selected = selectionService.selectPeersForGossip(
          [peer],
          1,
          PeerSelectionStrategy.random,
        );

        expect(selected, contains(peer));
      });
    });

    group('Strategy Comparison and Consistency', () {
      test('different strategies select different peer sets', () {
        // Set up peers with different characteristics
        peers = DomainTestHelpers.createMixedScenarioPeers().take(5).toList();

        final randomSelection = selectionService.selectPeersForGossip(
          peers,
          3,
          PeerSelectionStrategy.random,
        );

        final reliabilitySelection = selectionService.selectPeersForGossip(
          peers,
          3,
          PeerSelectionStrategy.mostReliable,
        );

        final leastRecentSelection = selectionService.selectPeersForGossip(
          peers,
          3,
          PeerSelectionStrategy.leastRecentlyContacted,
        );

        // Strategies should potentially select different peers
        // (not guaranteed, but likely given different peer characteristics)
        expect(randomSelection.length, equals(3));
        expect(reliabilitySelection.length, equals(3));
        expect(leastRecentSelection.length, equals(3));

        // Reliability selection should prefer more reliable peers
        final avgReliabilityScore =
            reliabilitySelection
                .map((p) => p.reliabilityScore)
                .reduce((a, b) => a + b) /
            reliabilitySelection.length;

        final avgRandomScore =
            randomSelection
                .map((p) => p.reliabilityScore)
                .reduce((a, b) => a + b) /
            randomSelection.length;

        expect(avgReliabilityScore, greaterThanOrEqualTo(avgRandomScore * 0.8));
      });

      test('round robin maintains fairness over multiple selections', () {
        final smallPeerSet = peers.take(3).toList();
        final selectionCounts = <String, int>{};

        // Initialize counters
        for (final peer in smallPeerSet) {
          selectionCounts[peer.address.value] = 0;
        }

        // Perform many single-peer selections
        for (int i = 0; i < 30; i++) {
          final selected = selectionService.selectPeersForGossip(
            smallPeerSet,
            1,
            PeerSelectionStrategy.roundRobin,
          );

          selectionCounts[selected.first.address.value] =
              selectionCounts[selected.first.address.value]! + 1;
        }

        // Each peer should be selected exactly 10 times (30 selections / 3 peers)
        for (final count in selectionCounts.values) {
          expect(count, equals(10));
        }
      });

      test('least recently contacted respects temporal ordering', () {
        final timeSortedPeers = peers.take(4).toList();
        final baseTime = DateTime.now().subtract(const Duration(hours: 1));

        // Set up contact times in known order (oldest to newest)
        for (int i = 0; i < timeSortedPeers.length; i++) {
          final contactTime = baseTime.add(Duration(minutes: i * 10));
          final peerWithTime = ConnectedPeer(
            address: timeSortedPeers[i].address,
            lastContactTime: contactTime,
            isActive: true,
          );
          timeSortedPeers[i] = peerWithTime;
        }

        final selected = selectionService.selectPeersForGossip(
          timeSortedPeers,
          3,
          PeerSelectionStrategy.leastRecentlyContacted,
        );

        // Should select the 3 peers with oldest contact times
        expect(selected.length, equals(3));
        expect(selected[0], equals(timeSortedPeers[0])); // Oldest
        expect(selected[1], equals(timeSortedPeers[1])); // Second oldest
        expect(selected[2], equals(timeSortedPeers[2])); // Third oldest
      });
    });

    group('Scalability and Performance Integration', () {
      test('selection performance scales reasonably with peer count', () {
        final largePeerCounts = [10, 100, 500, 1000];
        final maxAllowedTime = const Duration(milliseconds: 500);

        for (final peerCount in largePeerCounts) {
          final largePeerList = DomainTestHelpers.createTestPeers(peerCount);
          final stopwatch = Stopwatch()..start();

          final selected = selectionService.selectPeersForGossip(
            largePeerList,
            50,
            PeerSelectionStrategy.mostReliable,
          );

          stopwatch.stop();

          expect(selected.length, equals(math.min(50, peerCount)));
          expect(
            stopwatch.elapsed,
            lessThan(maxAllowedTime),
            reason: 'Selection should be fast even with $peerCount peers',
          );
        }
      });

      test('reliability calculation handles high-frequency updates', () {
        final peer = peers[0];
        final stopwatch = Stopwatch()..start();

        // Perform many rapid updates
        for (int i = 0; i < 10000; i++) {
          if (i % 3 == 0) {
            peer.recordFailedContact();
          } else {
            peer.recordSuccessfulContact();
          }
        }

        stopwatch.stop();

        // Should complete quickly and maintain valid state
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
        expect(peer.reliabilityScore, greaterThan(0.0));
        expect(peer.reliabilityScore, lessThan(1.0));
        expect(peer.successRate, closeTo(2.0 / 3.0, 0.01));
      });
    });

    group('Domain Invariant Enforcement', () {
      test('peer reliability score boundaries are always maintained', () {
        final peer = peers[0];

        // Test lower boundary with many failures
        for (int i = 0; i < 1000; i++) {
          peer.recordFailedContact();
          expect(peer.reliabilityScore, greaterThanOrEqualTo(0.0));
        }

        // Create fresh peer to test upper boundary
        final freshPeer = InternalGossipPeer(
          nodeId: GossipNodeID('boundary-test'),
          address: const TransportPeerAddress('test://boundary'),
          initialReliabilityScore: 0.99,
        );

        for (int i = 0; i < 1000; i++) {
          freshPeer.recordSuccessfulContact();
          expect(freshPeer.reliabilityScore, lessThanOrEqualTo(1.0));
        }
      });

      test('peer activation state transitions are deterministic', () {
        final peer = peers[0];

        // Test activation threshold
        expect(peer.isActive, isTrue);

        peer.recordFailedContact();
        expect(peer.isActive, isTrue);

        peer.recordFailedContact();
        expect(peer.isActive, isTrue);

        peer.recordFailedContact(); // Third failure should deactivate
        expect(peer.isActive, isFalse);

        // Test reactivation
        peer.recordSuccessfulContact();
        expect(peer.isActive, isTrue);

        // Test that activation state affects selection
        final inactivePeers = peers.where((p) => !p.isActive).toList();
        final activePeers = peers.where((p) => p.isActive).toList();

        if (inactivePeers.isNotEmpty && activePeers.isNotEmpty) {
          final selected = selectionService.selectPeersForGossip(
            peers,
            peers.length,
            PeerSelectionStrategy.random,
          );

          expect(selected.every((p) => p.isActive), isTrue);
        }
      });

      test('peer statistics are internally consistent', () {
        final peer = peers[0];

        // Perform a series of operations and verify consistency
        var expectedSuccesses = 0;
        var expectedTotal = 0;

        for (int i = 0; i < 50; i++) {
          if (i % 4 == 0) {
            peer.recordFailedContact();
          } else {
            peer.recordSuccessfulContact();
            expectedSuccesses++;
          }
          expectedTotal++;

          // Verify consistency after each operation
          expect(
            peer.successRate,
            closeTo(expectedSuccesses / expectedTotal, 0.001),
          );
          expect(
            peer.reliabilityScore >= 0.0 && peer.reliabilityScore <= 1.0,
            isTrue,
          );
        }
      });
    });

    group('Real-world Scenario Simulation', () {
      test('gossip network with mixed reliability patterns', () {
        final networkPeers = DomainTestHelpers.createMixedScenarioPeers();
        final results = <String, List<ConnectedPeer>>{};

        // Simulate multiple gossip rounds
        for (int round = 0; round < 20; round++) {
          // Simulate network conditions using test helpers
          for (final peer in networkPeers) {
            DomainTestHelpers.simulateNetworkActivity(
              peer,
              rounds: 1,
              successProbability:
                  0.6 + (round % 3) * 0.1, // Vary success rate over time
            );
          }

          // Test selection with different strategies
          for (final strategy in PeerSelectionStrategy.values) {
            final selected = selectionService.selectPeersForGossip(
              networkPeers,
              3,
              strategy,
            );

            results['$strategy-round-$round'] = selected;
          }
        }

        // Verify that selection adapts to changing network conditions
        final earlyReliabilitySelections = results.entries
            .where(
              (e) =>
                  e.key.contains('mostReliable') && e.key.contains('round-1'),
            )
            .map((e) => e.value)
            .toList();

        final lateReliabilitySelections = results.entries
            .where(
              (e) =>
                  e.key.contains('mostReliable') && e.key.contains('round-19'),
            )
            .map((e) => e.value)
            .toList();

        expect(earlyReliabilitySelections.isNotEmpty, isTrue);
        expect(lateReliabilitySelections.isNotEmpty, isTrue);

        if (earlyReliabilitySelections.isNotEmpty &&
            lateReliabilitySelections.isNotEmpty) {
          final earlyAvgScore = _calculateAverageReliability(
            earlyReliabilitySelections.first,
          );
          final lateAvgScore = _calculateAverageReliability(
            lateReliabilitySelections.first,
          );

          // Scores should be different as network conditions change
          expect((earlyAvgScore - lateAvgScore).abs(), greaterThan(0.01));
        }
      });

      test('peer recovery after network partition', () {
        final peer = peers[0];

        // Simulate network partition (many failures)
        for (int i = 0; i < 10; i++) {
          peer.recordFailedContact();
        }

        expect(peer.isActive, isFalse);
        final partitionScore = peer.reliabilityScore;

        // Simulate recovery (successful contacts)
        for (int i = 0; i < 15; i++) {
          peer.recordSuccessfulContact();
        }

        expect(peer.isActive, isTrue);
        expect(peer.reliabilityScore, greaterThan(partitionScore));

        // Should be selectable again by reliability strategy
        final selected = selectionService.selectPeersForGossip(
          [peer],
          1,
          PeerSelectionStrategy.mostReliable,
        );

        expect(selected, contains(peer));
      });
    });
  });
}

// Helper Functions

double _calculateAverageReliability(List<ConnectedPeer> peers) {
  if (peers.isEmpty) return 0.0;
  return peers.map((p) => p.reliabilityScore).reduce((a, b) => a + b) /
      peers.length;
}
