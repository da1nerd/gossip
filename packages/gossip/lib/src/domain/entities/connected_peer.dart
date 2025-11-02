library;

/// Transport-level peer representation used for selection and gossip,
/// without requiring a known gossip node identity (`GossipNodeID`).
///
/// This entity encapsulates liveness and reliability behavior for a peer
/// discovered via the transport, keyed by its `TransportPeerAddress`.
/// It enables the system to discover, select, and gossip with peers
/// immediately, even before learning their gossip identity (which can be
/// promoted/linked later when a digest or events reveal the real node ID).
///
/// Key points:
/// - No dependency on `GossipNodeID`
/// - Holds reliability state (success/failure history) and liveness
/// - Safe to persist independently of identity and can be promoted later
///
/// Typical flow:
/// 1) Transport discovers a peer -> create/upsert ConnectedPeer (by address)
/// 2) Gossip cycle selects ConnectedPeers for exchange
/// 3) On digest/events received containing a real node ID -> separate promotion
///    step links this address to an identified node (outside of this entity)
import 'dart:math' as math;

import '../../gossip_transport.dart';

class ConnectedPeer {
  /// Transport-level address used as the unique key for this peer.
  final TransportPeerAddress address;

  /// Arbitrary metadata from transport or higher layers (display names, tags, etc).
  final Map<String, dynamic> metadata;

  // Reliability and liveness
  DateTime? _lastContactTime;
  DateTime? _lastSuccessfulContact;
  double _reliabilityScore;
  int _totalAttempts;
  int _successfulAttempts;
  int _consecutiveFailures;
  bool _isActive;

  ConnectedPeer({
    required this.address,
    Map<String, dynamic> metadata = const {},
    DateTime? lastContactTime,
    double initialReliabilityScore = 1.0,
    bool isActive = true,
  }) : metadata = Map<String, dynamic>.from(metadata),
       _lastContactTime = lastContactTime,
       _lastSuccessfulContact = lastContactTime,
       _reliabilityScore = initialReliabilityScore,
       _totalAttempts = 0,
       _successfulAttempts = 0,
       _consecutiveFailures = 0,
       _isActive = isActive;

  /// Records a successful contact attempt, updating reliability and liveness.
  void recordSuccessfulContact() {
    final now = DateTime.now();
    _lastContactTime = now;
    _lastSuccessfulContact = now;
    _totalAttempts++;
    _successfulAttempts++;
    _consecutiveFailures = 0;
    _updateReliabilityScore();
    _isActive = true;
  }

  /// Records a failed contact attempt, updating reliability and liveness.
  ///
  /// Note: Do not flip isActive here. Let transport discovery drive liveness.
  /// This avoids starving selection under lossy networks while still reducing
  /// selection probability via reliability score.
  void recordFailedContact() {
    _lastContactTime = DateTime.now();
    _totalAttempts++;
    _consecutiveFailures++;
    _updateReliabilityScore();
  }

  /// Updates in-memory transport-derived properties for this peer.
  ///
  /// Safe to call on each discovery or status update tick.
  void updateFromTransport(TransportPeer transportPeer) {
    // Merge metadata (transport-provided fields may override)
    metadata.addAll(transportPeer.metadata);
    metadata['displayName'] = transportPeer.displayName;
    metadata['transportId'] = transportPeer.address.value;

    _isActive = transportPeer.isActive;
    // Do not modify reliability counters here; those are driven by contact results.
  }

  /// Manually marks this peer as active/inactive (e.g., external signal).
  void markActive(bool active) {
    _isActive = active;
  }

  /// Recomputes reliability score based on history.
  ///
  /// A simple heuristic:
  /// score = successRate - min(0.1 * consecutiveFailures, 0.5)
  /// clamped to [0.0, 1.0]
  void _updateReliabilityScore() {
    if (_totalAttempts == 0) return;

    final successRate = _successfulAttempts / _totalAttempts;
    final consecutiveFailurePenalty = math.min(_consecutiveFailures * 0.1, 0.5);

    _reliabilityScore = (successRate - consecutiveFailurePenalty).clamp(
      0.0,
      1.0,
    );
  }

  // --- Getters ---

  DateTime? get lastContactTime => _lastContactTime;

  DateTime? get lastSuccessfulContact => _lastSuccessfulContact;

  double get reliabilityScore => _reliabilityScore;

  bool get isActive => _isActive;

  int get consecutiveFailures => _consecutiveFailures;

  double get successRate =>
      _totalAttempts > 0 ? _successfulAttempts / _totalAttempts : 0.0;

  int get totalAttempts => _totalAttempts;

  int get successfulAttempts => _successfulAttempts;

  @override
  String toString() =>
      'ConnectedPeer('
      'address: $address, '
      'reliability: ${_reliabilityScore.toStringAsFixed(3)}, '
      'active: $_isActive'
      ')';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ConnectedPeer) return false;
    return address == other.address;
  }

  @override
  int get hashCode => address.hashCode;
}
