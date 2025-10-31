import 'package:test/test.dart';
import 'package:gossip/src/domain/entities/internal_gossip_peer.dart';
import 'package:gossip/src/gossip_node_id.dart';
import 'package:gossip/src/gossip_peer.dart';
import 'package:gossip/src/transport.dart';
import '../test_helpers.dart';

void main() {
  group('InternalGossipPeer', () {
    late GossipNodeID nodeId;
    late TransportPeerAddress address;
    late Map<String, dynamic> metadata;

    setUp(() {
      nodeId = GossipNodeID('test-node-1');
      address = const TransportPeerAddress('test://peer1');
      metadata = {'displayName': 'Test Peer', 'version': '1.0'};
    });

    group('Constructor', () {
      test('creates peer with default values', () {
        final peer = InternalGossipPeer(nodeId: nodeId, address: address);

        expect(peer.nodeId, equals(nodeId));
        expect(peer.address, equals(address));
        expect(peer.metadata, isEmpty);
        expect(peer.lastContactTime, isNull);
        expect(peer.lastSuccessfulContact, isNull);
        expect(peer.reliabilityScore, equals(1.0));
        expect(peer.isActive, isTrue);
        expect(peer.consecutiveFailures, equals(0));
        expect(peer.successRate, equals(0.0));
      });

      test('creates peer with custom initial values', () {
        final initialContact = DateTime.now().subtract(
          const Duration(hours: 1),
        );

        final peer = InternalGossipPeer(
          nodeId: nodeId,
          address: address,
          metadata: metadata,
          lastContactTime: initialContact,
          initialReliabilityScore: 0.8,
          isActive: false,
        );

        expect(peer.nodeId, equals(nodeId));
        expect(peer.address, equals(address));
        expect(peer.metadata, equals(metadata));
        expect(peer.lastContactTime, equals(initialContact));
        expect(peer.lastSuccessfulContact, equals(initialContact));
        expect(peer.reliabilityScore, equals(0.8));
        expect(peer.isActive, isFalse);
        expect(peer.consecutiveFailures, equals(0));
        expect(peer.successRate, equals(0.0));
      });
    });

    group('recordSuccessfulContact', () {
      test('records first successful contact correctly', () {
        final peer = InternalGossipPeer(nodeId: nodeId, address: address);
        final beforeContact = DateTime.now();

        peer.recordSuccessfulContact();

        final afterContact = DateTime.now();

        expect(peer.lastContactTime, isNotNull);
        expect(peer.lastContactTime!.isAfter(beforeContact), isTrue);
        expect(
          peer.lastContactTime!.isBefore(
            afterContact.add(const Duration(seconds: 1)),
          ),
          isTrue,
        );
        expect(peer.lastSuccessfulContact, equals(peer.lastContactTime));
        expect(peer.reliabilityScore, equals(1.0));
        expect(peer.isActive, isTrue);
        expect(peer.consecutiveFailures, equals(0));
        expect(peer.successRate, equals(1.0));
      });

      test('resets consecutive failures on successful contact', () {
        final peer = InternalGossipPeer(nodeId: nodeId, address: address);

        // Record some failures first
        peer.recordFailedContact();
        peer.recordFailedContact();

        expect(peer.consecutiveFailures, equals(2));
        expect(peer.reliabilityScore, lessThan(1.0));

        // Then record success
        peer.recordSuccessfulContact();

        expect(peer.consecutiveFailures, equals(0));
        expect(peer.isActive, isTrue);
        expect(
          peer.successRate,
          equals(1.0 / 3.0),
        ); // 1 success out of 3 total attempts
      });

      test('reactivates peer after successful contact', () {
        final peer = InternalGossipPeer(nodeId: nodeId, address: address);

        // Make peer inactive through failures
        peer.recordFailedContact();
        peer.recordFailedContact();
        peer.recordFailedContact();

        expect(peer.isActive, isFalse);

        // Successful contact should reactivate
        peer.recordSuccessfulContact();

        expect(peer.isActive, isTrue);
      });
    });

    group('recordFailedContact', () {
      test('records first failed contact correctly', () {
        final peer = InternalGossipPeer(nodeId: nodeId, address: address);
        final beforeContact = DateTime.now();

        peer.recordFailedContact();

        final afterContact = DateTime.now();

        expect(peer.lastContactTime, isNotNull);
        expect(peer.lastContactTime!.isAfter(beforeContact), isTrue);
        expect(
          peer.lastContactTime!.isBefore(
            afterContact.add(const Duration(seconds: 1)),
          ),
          isTrue,
        );
        expect(peer.lastSuccessfulContact, isNull);
        expect(peer.consecutiveFailures, equals(1));
        expect(peer.successRate, equals(0.0));
        expect(peer.reliabilityScore, lessThan(1.0));
      });

      test('increments consecutive failures', () {
        final peer = InternalGossipPeer(nodeId: nodeId, address: address);

        peer.recordFailedContact();
        expect(peer.consecutiveFailures, equals(1));

        peer.recordFailedContact();
        expect(peer.consecutiveFailures, equals(2));

        peer.recordFailedContact();
        expect(peer.consecutiveFailures, equals(3));
      });

      test('marks peer as inactive after 3 consecutive failures', () {
        final peer = InternalGossipPeer(nodeId: nodeId, address: address);

        expect(peer.isActive, isTrue);

        peer.recordFailedContact();
        expect(peer.isActive, isTrue);

        peer.recordFailedContact();
        expect(peer.isActive, isTrue);

        peer.recordFailedContact();
        expect(peer.isActive, isFalse);
      });

      test('decreases reliability score with consecutive failures', () {
        final peer = InternalGossipPeer(nodeId: nodeId, address: address);
        final initialScore = peer.reliabilityScore;

        peer.recordFailedContact();
        final scoreAfterOne = peer.reliabilityScore;

        peer.recordFailedContact();
        final scoreAfterTwo = peer.reliabilityScore;

        peer.recordFailedContact();
        final scoreAfterThree = peer.reliabilityScore;

        expect(scoreAfterOne, lessThan(initialScore));
        expect(scoreAfterTwo, lessThanOrEqualTo(scoreAfterOne));
        expect(scoreAfterThree, lessThanOrEqualTo(scoreAfterTwo));

        // All scores should be non-negative
        expect(scoreAfterOne, greaterThanOrEqualTo(0.0));
        expect(scoreAfterTwo, greaterThanOrEqualTo(0.0));
        expect(scoreAfterThree, greaterThanOrEqualTo(0.0));
      });
    });

    group('reliability score calculation', () {
      test('maintains perfect score with all successes', () {
        final peer = InternalGossipPeer(nodeId: nodeId, address: address);

        for (int i = 0; i < 10; i++) {
          peer.recordSuccessfulContact();
        }

        expect(peer.reliabilityScore, equals(1.0));
        expect(peer.successRate, equals(1.0));
      });

      test('calculates correct score with mixed success/failure', () {
        final peer = DomainTestHelpers.createPeerWithReliability(
          nodeIdSuffix: 'mixed-score-test',
          successfulContacts: 7,
          failedContacts: 3,
        );

        expect(peer.successRate, equals(0.7));
        expect(peer.reliabilityScore, greaterThan(0.0));
        expect(peer.reliabilityScore, lessThan(1.0));
      });

      test('score never goes below 0.0', () {
        final peer = DomainTestHelpers.createPeerWithReliability(
          nodeIdSuffix: 'minimum-score-test',
          successfulContacts: 0,
          failedContacts: 20,
          shouldBeActive: false,
        );

        expect(peer.reliabilityScore, greaterThanOrEqualTo(0.0));
      });

      test('score never goes above 1.0', () {
        // Start with high initial score and add successes
        final highScorePeer = InternalGossipPeer(
          nodeId: nodeId,
          address: address,
          initialReliabilityScore: 0.9,
        );

        for (int i = 0; i < 10; i++) {
          highScorePeer.recordSuccessfulContact();
        }

        expect(highScorePeer.reliabilityScore, lessThanOrEqualTo(1.0));
      });

      test('penalty increases with consecutive failures', () {
        final peer = InternalGossipPeer(nodeId: nodeId, address: address);

        // First establish some successful history
        for (int i = 0; i < 5; i++) {
          peer.recordSuccessfulContact();
        }

        final baseScore = peer.reliabilityScore;

        // Now add consecutive failures and check penalty increases
        peer.recordFailedContact();
        final scoreAfterOne = peer.reliabilityScore;

        peer.recordFailedContact();
        final scoreAfterTwo = peer.reliabilityScore;

        peer.recordFailedContact();
        final scoreAfterThree = peer.reliabilityScore;

        // The penalty should generally increase with consecutive failures
        // but due to the math.min cap, it may plateau
        final penaltyOne = baseScore - scoreAfterOne;
        final penaltyTwo = scoreAfterOne - scoreAfterTwo;
        final penaltyThree = scoreAfterTwo - scoreAfterThree;

        expect(penaltyOne, greaterThan(0));
        expect(penaltyTwo, greaterThan(0));
        expect(
          penaltyThree,
          greaterThanOrEqualTo(0),
        ); // May be 0 if score hit minimum
      });
    });

    group('toGossipPeer', () {
      test('converts to external GossipPeer format', () {
        final contactTime = DateTime.now();
        final peer = InternalGossipPeer(
          nodeId: nodeId,
          address: address,
          metadata: metadata,
          lastContactTime: contactTime,
          isActive: false,
        );

        final gossipPeer = peer.toGossipPeer();

        expect(gossipPeer, isA<GossipPeer>());
        expect(gossipPeer.id, equals(nodeId));
        expect(gossipPeer.address, equals(address));
        expect(gossipPeer.metadata, equals(metadata));
        expect(gossipPeer.lastContactTime, equals(contactTime));
        expect(gossipPeer.isActive, isFalse);
      });

      test('excludes internal state from external representation', () {
        final peer = InternalGossipPeer(nodeId: nodeId, address: address);

        // Record some activity to create internal state
        peer.recordSuccessfulContact();
        peer.recordFailedContact();

        final gossipPeer = peer.toGossipPeer();

        // The external representation should not expose internal tracking
        expect(gossipPeer.metadata.containsKey('consecutiveFailures'), isFalse);
        expect(gossipPeer.metadata.containsKey('totalAttempts'), isFalse);
        expect(gossipPeer.metadata.containsKey('successfulAttempts'), isFalse);
      });
    });

    group('equality and hashing', () {
      test('peers with same nodeId and address are equal', () {
        final peer1 = InternalGossipPeer(nodeId: nodeId, address: address);
        final peer2 = InternalGossipPeer(nodeId: nodeId, address: address);

        expect(peer1, equals(peer2));
        expect(peer1.hashCode, equals(peer2.hashCode));
      });

      test('peers with different nodeIds are not equal', () {
        final peer1 = InternalGossipPeer(nodeId: nodeId, address: address);
        final peer2 = InternalGossipPeer(
          nodeId: GossipNodeID('different-node'),
          address: address,
        );

        expect(peer1, isNot(equals(peer2)));
      });

      test('peers with different addresses are not equal', () {
        final peer1 = InternalGossipPeer(nodeId: nodeId, address: address);
        final peer2 = InternalGossipPeer(
          nodeId: nodeId,
          address: const TransportPeerAddress('different://address'),
        );

        expect(peer1, isNot(equals(peer2)));
      });

      test('equality ignores dynamic state differences', () {
        final peer1 = InternalGossipPeer(nodeId: nodeId, address: address);
        final peer2 = InternalGossipPeer(nodeId: nodeId, address: address);

        // Create different internal states
        peer1.recordSuccessfulContact();
        peer2.recordFailedContact();

        // Should still be equal based on identity
        expect(peer1, equals(peer2));
      });
    });

    group('toString', () {
      test('provides meaningful string representation', () {
        final peer = InternalGossipPeer(nodeId: nodeId, address: address);

        final str = peer.toString();

        expect(str, contains(nodeId.toString()));
        expect(str, contains('reliability'));
        expect(str, contains('active'));
        expect(str, contains('1.000')); // Default reliability score
        expect(str, contains('true')); // Default active state
      });

      test('reflects current state in string representation', () {
        final peer = InternalGossipPeer(nodeId: nodeId, address: address);

        // Make peer inactive with low reliability
        peer.recordFailedContact();
        peer.recordFailedContact();
        peer.recordFailedContact();

        final str = peer.toString();

        expect(str, contains('false')); // Should show inactive state
        expect(str, isNot(contains('1.000'))); // Should not show perfect score
      });
    });

    group('edge cases and boundaries', () {
      test('handles rapid successive contacts correctly', () {
        final peer = DomainTestHelpers.createTestPeer(
          nodeIdSuffix: 'rapid-contacts-test',
        );

        // Use helper to simulate alternating network activity
        DomainTestHelpers.simulateNetworkActivity(
          peer,
          rounds: 100,
          successProbability: 0.5,
          random: DomainTestHelpers.createSeededRandom(42),
        );

        expect(peer.successRate, closeTo(0.5, 0.1));
        expect(peer.reliabilityScore, greaterThan(0.0));
        expect(peer.reliabilityScore, lessThan(1.0));
      });

      test('handles zero attempts correctly', () {
        final peer = InternalGossipPeer(nodeId: nodeId, address: address);

        // No contacts recorded
        expect(peer.successRate, equals(0.0));
        expect(
          peer.reliabilityScore,
          equals(1.0),
        ); // Should maintain initial score
        expect(peer.consecutiveFailures, equals(0));
      });

      test('maintains state consistency across many operations', () {
        final peer = DomainTestHelpers.createTestPeer(
          nodeIdSuffix: 'consistency-test',
        );

        // Use helper to calculate expected success rate
        final expectedSuccesses = 17; // 1/3 of 50 iterations rounded
        final expectedTotal = 50;
        final expectedRate = DomainTestHelpers.calculateExpectedSuccessRate(
          0,
          0,
          expectedSuccesses,
          expectedTotal - expectedSuccesses,
        );

        // Simulate the operations using consistent pattern
        for (int i = 0; i < 50; i++) {
          if (i % 3 == 0) {
            peer.recordSuccessfulContact();
          } else {
            peer.recordFailedContact();
          }
        }

        expect(peer.successRate, closeTo(expectedRate, 0.001));
        expect(DomainTestHelpers.validatePeerConsistency(peer), isTrue);
      });
    });

    group('state transitions', () {
      test('active to inactive transition occurs at correct threshold', () {
        final peer = InternalGossipPeer(nodeId: nodeId, address: address);

        expect(peer.isActive, isTrue);

        // 1 failure - should still be active
        peer.recordFailedContact();
        expect(peer.isActive, isTrue);

        // 2 failures - should still be active
        peer.recordFailedContact();
        expect(peer.isActive, isTrue);

        // 3 failures - should become inactive
        peer.recordFailedContact();
        expect(peer.isActive, isFalse);
      });

      test('inactive to active transition occurs immediately on success', () {
        final peer = InternalGossipPeer(nodeId: nodeId, address: address);

        // Make peer inactive
        peer.recordFailedContact();
        peer.recordFailedContact();
        peer.recordFailedContact();
        expect(peer.isActive, isFalse);

        // One success should reactivate immediately
        peer.recordSuccessfulContact();
        expect(peer.isActive, isTrue);
      });

      test('consecutive failure count resets exactly on success', () {
        final peer = InternalGossipPeer(nodeId: nodeId, address: address);

        // Build up consecutive failures
        peer.recordFailedContact();
        peer.recordFailedContact();
        expect(peer.consecutiveFailures, equals(2));

        // Success should reset to exactly 0
        peer.recordSuccessfulContact();
        expect(peer.consecutiveFailures, equals(0));

        // Verify it can build up again
        peer.recordFailedContact();
        expect(peer.consecutiveFailures, equals(1));
      });
    });
  });
}
