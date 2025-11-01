/// Domain service for peer selection strategies.
///
/// Contains the core business logic for how peers are selected for gossip.
/// This encapsulates the different selection algorithms and their logic.
library;

import 'dart:math' as math;

import '../../gossip_config.dart';

/// Domain service for peer selection strategies (legacy).
///
/// Deprecated: Use ConnectedPeerSelectionService instead.
/// Kept as an empty shim to avoid breaking imports while tests are migrated.
@Deprecated('Use ConnectedPeerSelectionService instead')
class PeerSelectionService {
  final math.Random _random;
  int _lastRoundRobinIndex = 0;

  PeerSelectionService({math.Random? random})
    : _random = random ?? math.Random();

  /// Deprecated: no-op. Migrate to ConnectedPeerSelectionService.
  Never selectPeersForGossip(
    covariant List<dynamic> availablePeers,
    int maxPeers,
    PeerSelectionStrategy strategy,
  ) {
    throw UnsupportedError(
      'PeerSelectionService is deprecated. Use ConnectedPeerSelectionService instead.',
    );
  }
}
