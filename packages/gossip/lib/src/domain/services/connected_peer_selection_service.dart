library;

import 'dart:math' as math;

import '../../gossip_config.dart';
import '../entities/connected_peer.dart';

/// Domain service for selecting transport-level connected peers for gossip.
///
/// This service mirrors the selection strategies available for identified
/// peers, but operates on [ConnectedPeer] which does not require a known
/// gossip identity. This allows the system to discover and select peers
/// immediately (by address) while identity can be learned and linked later.
class ConnectedPeerSelectionService {
  final math.Random _random;
  int _lastRoundRobinIndex = 0;

  ConnectedPeerSelectionService({math.Random? random})
    : _random = random ?? math.Random();

  /// Selects peers for gossip from [availablePeers] using the provided [strategy].
  ///
  /// - Filters only active peers
  /// - Caps selection at [maxPeers]
  /// - Supports random, round-robin, least-recently-contacted, most-reliable
  List<ConnectedPeer> selectPeersForGossip(
    List<ConnectedPeer> availablePeers,
    int maxPeers,
    PeerSelectionStrategy strategy,
  ) {
    final activePeers = availablePeers.where((p) => p.isActive).toList();
    if (activePeers.isEmpty) return [];

    final peersToSelect = math.min(math.max(0, maxPeers), activePeers.length);
    if (peersToSelect <= 0) return [];

    switch (strategy) {
      case PeerSelectionStrategy.random:
        return _selectRandomPeers(activePeers, peersToSelect);
      case PeerSelectionStrategy.roundRobin:
        return _selectRoundRobinPeers(activePeers, peersToSelect);
      case PeerSelectionStrategy.leastRecentlyContacted:
        return _selectLeastRecentlyContactedPeers(activePeers, peersToSelect);
      case PeerSelectionStrategy.mostReliable:
        return _selectMostReliablePeers(activePeers, peersToSelect);
    }
  }

  /// Select peers randomly (uniform).
  List<ConnectedPeer> _selectRandomPeers(List<ConnectedPeer> peers, int count) {
    final shuffled = List<ConnectedPeer>.from(peers)..shuffle(_random);
    return shuffled.take(count).toList();
  }

  /// Select peers in round-robin fashion.
  List<ConnectedPeer> _selectRoundRobinPeers(
    List<ConnectedPeer> peers,
    int count,
  ) {
    final selected = <ConnectedPeer>[];
    for (int i = 0; i < count; i++) {
      selected.add(peers[(_lastRoundRobinIndex + i) % peers.length]);
    }
    _lastRoundRobinIndex = (_lastRoundRobinIndex + count) % peers.length;
    return selected;
  }

  /// Select peers that were contacted least recently.
  List<ConnectedPeer> _selectLeastRecentlyContactedPeers(
    List<ConnectedPeer> peers,
    int count,
  ) {
    final sorted = List<ConnectedPeer>.from(peers);
    sorted.sort((a, b) {
      final aTime = a.lastContactTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.lastContactTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aTime.compareTo(bTime);
    });
    return sorted.take(count).toList();
  }

  /// Select peers with the highest reliability scores.
  List<ConnectedPeer> _selectMostReliablePeers(
    List<ConnectedPeer> peers,
    int count,
  ) {
    final sorted = List<ConnectedPeer>.from(peers)
      ..sort((a, b) => b.reliabilityScore.compareTo(a.reliabilityScore));
    return sorted.take(count).toList();
  }
}
