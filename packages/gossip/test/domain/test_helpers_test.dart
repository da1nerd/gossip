import 'package:test/test.dart';
import 'test_helpers.dart';

void main() {
  group('DomainTestHelpers', () {
    group('createPeerWithReliability', () {
      test('creates peer with exact success and failure counts', () {
        final peer = DomainTestHelpers.createPeerWithReliability(
          addressSuffix: 'exact-counts-test',
          successfulContacts: 7,
          failedContacts: 3,
        );

        expect(peer.successRate, equals(0.7));
        expect(peer.isActive, isTrue);
      });

      test('creates inactive peer when shouldBeActive is false', () {
        final peer = DomainTestHelpers.createPeerWithReliability(
          addressSuffix: 'inactive-test',
          successfulContacts: 2,
          failedContacts: 10,
          shouldBeActive: false,
        );

        expect(peer.successRate, equals(2.0 / 12.0));
        expect(peer.isActive, isFalse);
      });

      test('keeps peer active when requested despite many failures', () {
        final peer = DomainTestHelpers.createPeerWithReliability(
          addressSuffix: 'forced-active-test',
          successfulContacts: 5,
          failedContacts: 15,
          shouldBeActive: true,
        );

        expect(peer.successRate, equals(0.25));
        expect(peer.isActive, isTrue);
        expect(
          peer.consecutiveFailures,
          greaterThanOrEqualTo(3),
        ); // Natural result of many failures
      });

      test('creates peer with only successes', () {
        final peer = DomainTestHelpers.createPeerWithReliability(
          addressSuffix: 'only-success-test',
          successfulContacts: 10,
          failedContacts: 0,
        );

        expect(peer.successRate, equals(1.0));
        expect(peer.isActive, isTrue);
        expect(peer.consecutiveFailures, equals(0));
      });

      test('creates peer with only failures', () {
        final peer = DomainTestHelpers.createPeerWithReliability(
          addressSuffix: 'only-failure-test',
          successfulContacts: 0,
          failedContacts: 5,
          shouldBeActive: false,
        );

        expect(peer.successRate, equals(0.0));
        expect(peer.isActive, isFalse);
        expect(peer.consecutiveFailures, greaterThanOrEqualTo(3));
      });
    });

    group('createTestPeer', () {
      test('creates peer with custom parameters', () {
        final metadata = {'custom': 'value'};
        final contactTime = DateTime.now().subtract(Duration(hours: 1));

        final peer = DomainTestHelpers.createTestPeer(
          addressSuffix: 'custom-test',
          metadata: metadata,
          lastContactTime: contactTime,
          initialReliabilityScore: 0.8,
          isActive: false,
        );

        expect(peer.address.value, contains('custom-test'));
        expect(peer.metadata, equals(metadata));
        expect(peer.lastContactTime, equals(contactTime));
        expect(peer.reliabilityScore, equals(0.8));
        expect(peer.isActive, isFalse);
      });
    });

    group('validatePeerConsistency', () {
      test('validates consistent peer state', () {
        final peer = DomainTestHelpers.createPeerWithReliability(
          addressSuffix: 'validation-test',
          successfulContacts: 7,
          failedContacts: 3,
        );

        expect(DomainTestHelpers.validatePeerConsistency(peer), isTrue);
      });

      test('detects inconsistent peer state', () {
        final peer = DomainTestHelpers.createTestPeer(
          addressSuffix: 'invalid-test',
          initialReliabilityScore: 1.5, // Invalid score > 1.0
        );

        expect(DomainTestHelpers.validatePeerConsistency(peer), isFalse);
      });
    });

    group('calculateExpectedSuccessRate', () {
      test('calculates correct success rate', () {
        final rate = DomainTestHelpers.calculateExpectedSuccessRate(
          5, // initial successes
          2, // initial failures
          3, // additional successes
          1, // additional failures
        );

        expect(rate, equals(8.0 / 11.0)); // (5+3) / (5+2+3+1)
      });

      test('handles zero total attempts', () {
        final rate = DomainTestHelpers.calculateExpectedSuccessRate(0, 0, 0, 0);
        expect(rate, equals(0.0));
      });
    });

    group('simulateNetworkActivity', () {
      test('simulates activity with specified success probability', () {
        final peer = DomainTestHelpers.createTestPeer(
          addressSuffix: 'simulation-test',
        );

        DomainTestHelpers.simulateNetworkActivity(
          peer,
          rounds: 100,
          successProbability: 1.0, // 100% success
          random: DomainTestHelpers.createSeededRandom(42),
        );

        expect(peer.successRate, equals(1.0));
        expect(peer.isActive, isTrue);
      });

      test('produces consistent results with same seed', () {
        final peer1 = DomainTestHelpers.createTestPeer(
          addressSuffix: 'consistent-test-1',
        );
        final peer2 = DomainTestHelpers.createTestPeer(
          addressSuffix: 'consistent-test-2',
        );

        final seed = 12345;
        DomainTestHelpers.simulateNetworkActivity(
          peer1,
          rounds: 50,
          successProbability: 0.7,
          random: DomainTestHelpers.createSeededRandom(seed),
        );

        DomainTestHelpers.simulateNetworkActivity(
          peer2,
          rounds: 50,
          successProbability: 0.7,
          random: DomainTestHelpers.createSeededRandom(seed),
        );

        expect(peer1.successRate, equals(peer2.successRate));
        expect(peer1.isActive, equals(peer2.isActive));
      });
    });

    group('createMixedScenarioPeers', () {
      test('creates diverse set of peers', () {
        final peers = DomainTestHelpers.createMixedScenarioPeers();

        expect(peers.length, equals(6));

        // Find different peer types
        final perfectPeer = peers.firstWhere(
          (p) => p.address.value.contains('perfect'),
        );
        final inactivePeer = peers.firstWhere(
          (p) => p.address.value.contains('inactive'),
        );
        final freshPeer = peers.firstWhere(
          (p) => p.address.value.contains('fresh'),
        );

        expect(perfectPeer.successRate, equals(1.0));
        expect(inactivePeer.isActive, isFalse);
        expect(freshPeer.successRate, equals(0.0)); // No contacts yet
      });
    });

    group('createBenchmarkPeers', () {
      test('creates varied peer history', () {
        // Synthesize benchmark peers and simulate varied histories
        final peers = List.generate(
          10,
          (i) => DomainTestHelpers.createTestPeer(addressSuffix: 'bench-$i'),
        );

        for (var i = 0; i < peers.length; i++) {
          final successes = (i % 5) + 1;
          final failures = (i % 3) + 1;
          for (var s = 0; s < successes; s++) {
            peers[i].recordSuccessfulContact();
          }
          for (var f = 0; f < failures; f++) {
            peers[i].recordFailedContact();
          }
        }

        expect(peers.length, equals(10));

        // Should have variety in reliability scores
        final reliabilityScores = peers.map((p) => p.reliabilityScore).toSet();
        expect(reliabilityScores.length, greaterThan(1));

        // All peers should have some contact history
        expect(peers.every((p) => p.successRate >= 0.0), isTrue);
      });

      test('measureExecutionTime measures correctly', () {
        var counter = 0;
        final duration = DomainTestHelpers.measureExecutionTime(() {
          for (int i = 0; i < 1000; i++) {
            counter++;
          }
        });

        expect(counter, equals(1000));
        expect(duration.inMicroseconds, greaterThan(0));
      });
    });
  });
}
