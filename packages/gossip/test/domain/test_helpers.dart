/// Test helper utilities for domain layer tests.
///
/// This module provides common utilities, fixtures, and helpers
/// used across domain layer tests to reduce code duplication
/// and improve test maintainability.
library;

import 'dart:math' as math;
import 'package:gossip/src/domain/entities/internal_gossip_peer.dart';
import 'package:gossip/src/gossip_node_id.dart';
import 'package:gossip/src/transport.dart';

/// Test helper class providing utilities for domain tests.
class DomainTestHelpers {
  static final math.Random _random = math.Random(
    12345,
  ); // Seeded for reproducibility

  /// Creates a single test peer with optional parameters.
  static InternalGossipPeer createTestPeer({
    String? nodeIdSuffix,
    String? addressSuffix,
    Map<String, dynamic>? metadata,
    DateTime? lastContactTime,
    double? initialReliabilityScore,
    bool? isActive,
  }) {
    final suffix = nodeIdSuffix ?? _random.nextInt(100000).toString();
    return InternalGossipPeer(
      nodeId: GossipNodeID('test-node-$suffix'),
      address: TransportPeerAddress('test://peer$suffix'),
      metadata: metadata ?? {'created': 'test', 'suffix': suffix},
      lastContactTime: lastContactTime,
      initialReliabilityScore: initialReliabilityScore ?? 1.0,
      isActive: isActive ?? true,
    );
  }

  /// Creates a list of test peers with default configurations.
  static List<InternalGossipPeer> createTestPeers(int count) {
    return List.generate(count, (index) {
      return createTestPeer(
        nodeIdSuffix: index.toString(),
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
  static InternalGossipPeer createPeerWithReliability({
    required String nodeIdSuffix,
    required int successfulContacts,
    required int failedContacts,
    bool shouldBeActive = true,
  }) {
    final peer = createTestPeer(nodeIdSuffix: nodeIdSuffix);

    // Record the exact number of contacts requested
    for (int i = 0; i < successfulContacts; i++) {
      peer.recordSuccessfulContact();
    }

    for (int i = 0; i < failedContacts; i++) {
      peer.recordFailedContact();
    }

    // Use the test method to override active state if needed
    if (shouldBeActive && !peer.isActive) {
      peer.setActiveStateForTesting(true);
    } else if (!shouldBeActive && peer.isActive) {
      peer.setActiveStateForTesting(false);
    }

    return peer;
  }

  /// Creates a peer with a specific contact time.
  static InternalGossipPeer createPeerWithContactTime({
    required String nodeIdSuffix,
    required DateTime contactTime,
    bool wasSuccessful = true,
  }) {
    final peer = createTestPeer(
      nodeIdSuffix: nodeIdSuffix,
      lastContactTime: contactTime,
    );

    // Record a contact to set the time (this will update the time, but it's close enough for tests)
    if (wasSuccessful) {
      peer.recordSuccessfulContact();
    } else {
      peer.recordFailedContact();
    }

    return peer;
  }

  /// Creates peers with graduated reliability scores (highest to lowest).
  static List<InternalGossipPeer> createPeersWithGraduatedReliability(
    int count,
  ) {
    final peers = <InternalGossipPeer>[];

    for (int i = 0; i < count; i++) {
      final successRate = 1.0 - (i * 0.2); // Decreasing success rate
      final totalContacts = 10;
      final successes = (totalContacts * successRate).round();
      final failures = totalContacts - successes;

      peers.add(
        createPeerWithReliability(
          nodeIdSuffix: 'graduated-$i',
          successfulContacts: successes,
          failedContacts: failures,
          shouldBeActive:
              successRate > 0.3, // Keep reasonably reliable peers active
        ),
      );
    }

    return peers;
  }

  /// Creates peers with specific contact time patterns.
  static List<InternalGossipPeer> createPeersWithContactTimes({
    required int count,
    required Duration timeBetweenContacts,
    DateTime? baseTime,
  }) {
    final base = baseTime ?? DateTime.now().subtract(Duration(hours: count));
    final peers = <InternalGossipPeer>[];

    for (int i = 0; i < count; i++) {
      final contactTime = base.add(
        Duration(milliseconds: i * timeBetweenContacts.inMilliseconds),
      );

      peers.add(
        createPeerWithContactTime(
          nodeIdSuffix: 'timed-$i',
          contactTime: contactTime,
          wasSuccessful: i % 4 != 3, // Most contacts successful, some failed
        ),
      );
    }

    return peers;
  }

  /// Creates a mixed scenario with various peer types.
  static List<InternalGossipPeer> createMixedScenarioPeers() {
    return [
      // Perfect peer
      createPeerWithReliability(
        nodeIdSuffix: 'perfect',
        successfulContacts: 20,
        failedContacts: 0,
      ),

      // Very reliable peer
      createPeerWithReliability(
        nodeIdSuffix: 'very-reliable',
        successfulContacts: 18,
        failedContacts: 2,
      ),

      // Moderately reliable peer
      createPeerWithReliability(
        nodeIdSuffix: 'moderate',
        successfulContacts: 12,
        failedContacts: 8,
      ),

      // Unreliable but active peer
      createPeerWithReliability(
        nodeIdSuffix: 'unreliable-active',
        successfulContacts: 5,
        failedContacts: 10,
        shouldBeActive: true,
      ),

      // Inactive peer
      createPeerWithReliability(
        nodeIdSuffix: 'inactive',
        successfulContacts: 2,
        failedContacts: 15,
        shouldBeActive: false,
      ),

      // Fresh peer (no history)
      createTestPeer(nodeIdSuffix: 'fresh'),
    ];
  }

  /// Simulates network activity on a peer over multiple rounds.
  static void simulateNetworkActivity(
    InternalGossipPeer peer, {
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

  /// Simulates a realistic network partition scenario.
  static void simulateNetworkPartition(
    List<InternalGossipPeer> peers, {
    required int partitionRounds,
    required int recoveryRounds,
    required List<int> partitionedPeerIndices,
  }) {
    // Partition phase - some peers fail all contacts
    for (int round = 0; round < partitionRounds; round++) {
      for (int i = 0; i < peers.length; i++) {
        if (partitionedPeerIndices.contains(i)) {
          peers[i].recordFailedContact();
        } else {
          // Non-partitioned peers have normal success rate
          if (_random.nextDouble() < 0.8) {
            peers[i].recordSuccessfulContact();
          } else {
            peers[i].recordFailedContact();
          }
        }
      }
    }

    // Recovery phase - all peers gradually recover
    for (int round = 0; round < recoveryRounds; round++) {
      final recoveryProgress = round / recoveryRounds;

      for (int i = 0; i < peers.length; i++) {
        double successRate;
        if (partitionedPeerIndices.contains(i)) {
          // Partitioned peers gradually recover
          successRate = 0.3 + (0.5 * recoveryProgress);
        } else {
          // Non-partitioned peers maintain high success rate
          successRate = 0.8;
        }

        if (_random.nextDouble() < successRate) {
          peers[i].recordSuccessfulContact();
        } else {
          peers[i].recordFailedContact();
        }
      }
    }
  }

  /// Validates that a peer's internal state is consistent.
  static bool validatePeerConsistency(InternalGossipPeer peer) {
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

    // Check that inactive peers have at least 3 consecutive failures
    // (unless they have no contact history at all)
    if (!peer.isActive &&
        peer.lastContactTime != null &&
        peer.consecutiveFailures < 3) {
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

  /// Creates a peer list with specific active/inactive distribution.
  static List<InternalGossipPeer> createPeersWithActiveDistribution({
    required int totalPeers,
    required int activePeers,
  }) {
    if (activePeers > totalPeers) {
      throw ArgumentError('activePeers cannot exceed totalPeers');
    }

    final peers = createTestPeers(totalPeers);

    // Make some peers inactive
    final inactivePeerCount = totalPeers - activePeers;
    for (int i = 0; i < inactivePeerCount; i++) {
      final peer = peers[i];
      // Make inactive by recording 3+ failures
      for (int j = 0; j < 3; j++) {
        peer.recordFailedContact();
      }
    }

    return peers;
  }

  /// Asserts that two peer lists contain the same peers (order independent).
  static bool peerListsEqual(
    List<InternalGossipPeer> list1,
    List<InternalGossipPeer> list2,
  ) {
    if (list1.length != list2.length) return false;

    for (final peer in list1) {
      if (!list2.any(
        (p) => p.nodeId == peer.nodeId && p.address == peer.address,
      )) {
        return false;
      }
    }

    return true;
  }

  /// Creates test data for performance benchmarking.
  static List<InternalGossipPeer> createBenchmarkPeers(int count) {
    final peers = <InternalGossipPeer>[];
    final random = createSeededRandom(42);

    for (int i = 0; i < count; i++) {
      final peer = createTestPeer(
        nodeIdSuffix: 'benchmark-$i',
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

/// Extension methods for test assertions and utilities.
extension InternalGossipPeerTestExtensions on InternalGossipPeer {
  /// Creates a copy of this peer for testing purposes.
  InternalGossipPeer copyForTest() {
    return InternalGossipPeer(
      nodeId: nodeId,
      address: address,
      metadata: Map<String, dynamic>.from(metadata),
      lastContactTime: lastContactTime,
      initialReliabilityScore: reliabilityScore,
      isActive: isActive,
    );
  }

  /// Returns a human-readable summary of the peer's state for debugging.
  String debugSummary() {
    return 'Peer ${nodeId.value}: '
        'reliability=${reliabilityScore.toStringAsFixed(3)}, '
        'successRate=${successRate.toStringAsFixed(3)}, '
        'consecutiveFailures=$consecutiveFailures, '
        'active=$isActive, '
        'lastContact=$lastContactTime';
  }

  /// Checks if this peer would be considered "similar" to another for testing.
  bool isSimilarTo(InternalGossipPeer other, {double tolerance = 0.1}) {
    return (reliabilityScore - other.reliabilityScore).abs() < tolerance &&
        isActive == other.isActive &&
        nodeId == other.nodeId &&
        address == other.address;
  }
}
