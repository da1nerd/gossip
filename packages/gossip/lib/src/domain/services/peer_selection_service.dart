/// Domain service for peer selection strategies.
///
/// Contains the core business logic for how peers are selected for gossip.
/// This encapsulates the different selection algorithms and their logic.
library;

import 'dart:math' as math;

import '../../gossip_config.dart';
import '../entities/internal_gossip_peer.dart';

/// Domain service for peer selection strategies.
///
/// Contains the core business logic for how peers are selected for gossip.
class PeerSelectionService {
  final math.Random _random;
  int _lastRoundRobinIndex = 0;

  PeerSelectionService({math.Random? random})
    : _random = random ?? math.Random();

  /// Select peers for gossip based on the configured strategy.
  List<InternalGossipPeer> selectPeersForGossip(
    List<InternalGossipPeer> availablePeers,
    int maxPeers,
    PeerSelectionStrategy strategy,
  ) {
    final activePeers = availablePeers.where((p) => p.isActive).toList();
    if (activePeers.isEmpty) return [];

    final peersToSelect = math.min(maxPeers, activePeers.length);

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

  /// Select peers randomly.
  List<InternalGossipPeer> _selectRandomPeers(
    List<InternalGossipPeer> peers,
    int count,
  ) {
    final shuffled = List<InternalGossipPeer>.from(peers)..shuffle(_random);
    return shuffled.take(count).toList();
  }

  /// Select peers in round-robin fashion.
  List<InternalGossipPeer> _selectRoundRobinPeers(
    List<InternalGossipPeer> peers,
    int count,
  ) {
    final selected = <InternalGossipPeer>[];
    for (int i = 0; i < count; i++) {
      selected.add(peers[(_lastRoundRobinIndex + i) % peers.length]);
    }
    _lastRoundRobinIndex = (_lastRoundRobinIndex + count) % peers.length;
    return selected;
  }

  /// Select peers that were contacted least recently.
  List<InternalGossipPeer> _selectLeastRecentlyContactedPeers(
    List<InternalGossipPeer> peers,
    int count,
  ) {
    final sorted = List<InternalGossipPeer>.from(peers);
    sorted.sort((a, b) {
      final aTime = a.lastContactTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.lastContactTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aTime.compareTo(bTime);
    });
    return sorted.take(count).toList();
  }

  /// Select peers with the highest reliability scores.
  List<InternalGossipPeer> _selectMostReliablePeers(
    List<InternalGossipPeer> peers,
    int count,
  ) {
    final sorted = List<InternalGossipPeer>.from(peers);
    sorted.sort((a, b) => b.reliabilityScore.compareTo(a.reliabilityScore));
    return sorted.take(count).toList();
  }
}
