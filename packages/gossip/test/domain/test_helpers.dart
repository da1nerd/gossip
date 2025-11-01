/// Test helper utilities for domain layer tests.
///
/// This module provides common utilities, fixtures, and helpers
/// used across domain layer tests to reduce code duplication
/// and improve test maintainability.
library;

import 'dart:math' as math;
import 'package:gossip/src/domain/entities/connected_peer.dart';
import 'package:gossip/src/transport.dart';

/// Test helper class providing utilities for domain tests.
class DomainTestHelpers {
  static final math.Random _random = math.Random(
    12345,
  ); // Seeded for reproducibility

  /// Creates a single test peer with optional parameters.
  static ConnectedPeer createTestPeer({
    String? addressSuffix,
    Map<String, dynamic>? metadata,
    DateTime? lastContactTime,
    double? initialReliabilityScore,
    bool? isActive,
  }) {
    final suffix = addressSuffix ?? _random.nextInt(100000).toString();
    return ConnectedPeer(
      address: TransportPeerAddress('test://peer$suffix'),
      metadata: metadata ?? {'created': 'test', 'suffix': suffix},
      lastContactTime: lastContactTime,
      initialReliabilityScore: initialReliabilityScore ?? 1.0,
      isActive: isActive ?? true,
    );
  }

  /// Creates a list of test peers with default configurations.
  static List<ConnectedPeer> createTestPeers(int count) {
    return List.generate(count, (index) {
      return createTestPeer(
        addressSuffix: index.toString(),
        metadata: {
          'index': index,
          'created': 'batch',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
    });
  }

  /// Creates a peer with specific reliability characteristics.
  static ConnectedPeer createPeerWithReliability({
    required String addressSuffix,
    required int successfulContacts,
    required int failedContacts,
    bool shouldBeActive = true,
  }) {
    final peer = createTestPeer(
      addressSuffix: addressSuffix,
      isActive: shouldBeActive,
    );

    // Record the exact number of contacts requested
    for (int i = 0; i < successfulContacts; i++) {
      peer.recordSuccessfulContact();
    }

    for (int i = 0; i < failedContacts; i++) {
      peer.recordFailedContact();
    }

    // Ensure desired active state
    peer.markActive(shouldBeActive);

    return peer;
  }

  /// Creates a mixed scenario with various peer types.
  static List<ConnectedPeer> createMixedScenarioPeers() {
    return [
      // Perfect peer
      createPeerWithReliability(
        addressSuffix: 'perfect',
        successfulContacts: 20,
        failedContacts: 0,
      ),

      // Very reliable peer
      createPeerWithReliability(
        addressSuffix: 'very-reliable',
        successfulContacts: 18,
        failedContacts: 2,
      ),

      // Moderately reliable peer
      createPeerWithReliability(
        addressSuffix: 'moderate',
        successfulContacts: 12,
        failedContacts: 8,
      ),

      // Unreliable but active peer
      createPeerWithReliability(
        addressSuffix: 'unreliable-active',
        successfulContacts: 5,
        failedContacts: 10,
        shouldBeActive: true,
      ),

      // Inactive peer
      createPeerWithReliability(
        addressSuffix: 'inactive',
        successfulContacts: 2,
        failedContacts: 15,
        shouldBeActive: false,
      ),

      // Fresh peer (no history)
      createTestPeer(addressSuffix: 'fresh'),
    ];
  }

  /// Simulates network activity on a peer over multiple rounds.
  static void simulateNetworkActivity(
    ConnectedPeer peer, {
    required int rounds,
    required double successProbability,
    math.Random? random,
  }) {
    final rng = random ?? _random;

    for (int i = 0; i < rounds; i++) {
      if (rng.nextDouble() < successProbability) {
        peer.recordSuccessfulContact();
      } else {
        peer.recordFailedContact();
      }
    }
  }

  /// Validates that a peer's internal state is consistent.
  static bool validatePeerConsistency(ConnectedPeer peer) {
    // Check reliability score bounds
    if (peer.reliabilityScore < 0.0 || peer.reliabilityScore > 1.0) {
      return false;
    }

    // Check success rate bounds
    if (peer.successRate < 0.0 || peer.successRate > 1.0) {
      return false;
    }

    // Check consecutive failures is non-negative
    if (peer.consecutiveFailures < 0) {
      return false;
    }

    // Check contact time consistency
    if (peer.lastSuccessfulContact != null && peer.lastContactTime != null) {
      if (peer.lastSuccessfulContact!.isAfter(peer.lastContactTime!)) {
        return false;
      }
    }

    return true;
  }

  /// Calculates expected success rate for a peer after a series of operations.
  static double calculateExpectedSuccessRate(
    int initialSuccesses,
    int initialFailures,
    int additionalSuccesses,
    int additionalFailures,
  ) {
    final totalSuccesses = initialSuccesses + additionalSuccesses;
    final totalAttempts =
        initialSuccesses +
        initialFailures +
        additionalSuccesses +
        additionalFailures;

    return totalAttempts > 0 ? totalSuccesses / totalAttempts : 0.0;
  }

  /// Creates a deterministic random number generator for reproducible tests.
  static math.Random createSeededRandom(int seed) {
    return math.Random(seed);
  }

  /// Measures the execution time of a function.
  static Duration measureExecutionTime(void Function() function) {
    final stopwatch = Stopwatch()..start();
    function();
    stopwatch.stop();
    return stopwatch.elapsed;
  }

  /// Creates test data for performance benchmarking using ConnectedPeer.
  static List<ConnectedPeer> createBenchmarkPeers(int count) {
    final peers = <ConnectedPeer>[];
    final random = createSeededRandom(42);

    for (int i = 0; i < count; i++) {
      final peer = createTestPeer(
        addressSuffix: 'benchmark-$i',
        metadata: {
          'benchmark': true,
          'index': i,
          'category': i % 10, // Create some categories for variety
        },
      );

      // Give each peer some random history
      final totalContacts = random.nextInt(100) + 10;
      final successRate = 0.3 + (random.nextDouble() * 0.6); // 30-90% success
      final successes = (totalContacts * successRate).round();

      for (int j = 0; j < successes; j++) {
        peer.recordSuccessfulContact();
      }

      for (int j = 0; j < totalContacts - successes; j++) {
        peer.recordFailedContact();
      }

      peers.add(peer);
    }

    return peers;
  }
}
