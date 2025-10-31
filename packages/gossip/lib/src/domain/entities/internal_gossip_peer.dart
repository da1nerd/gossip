/// Internal domain model for peer management within the gossip protocol.
///
/// This is separate from GossipPeer which is the external API interface.
/// Contains rich domain behavior for reliability scoring, contact tracking, etc.
library;

import 'dart:math' as math;

import '../../gossip_node_id.dart';
import '../../gossip_peer.dart';
import '../../transport.dart';

/// Internal domain model for peer management.
///
/// Contains business logic for reliability scoring and contact tracking.
/// Separate from the external GossipPeer API interface.
class InternalGossipPeer {
  final GossipNodeID nodeId;
  final TransportPeerAddress address;
  final Map<String, dynamic> metadata;

  // Domain state for peer reliability
  DateTime? _lastContactTime;
  DateTime? _lastSuccessfulContact;
  double _reliabilityScore;
  int _totalAttempts;
  int _successfulAttempts;
  int _consecutiveFailures;
  bool _isActive;

  InternalGossipPeer({
    required this.nodeId,
    required this.address,
    this.metadata = const {},
    DateTime? lastContactTime,
    double initialReliabilityScore = 1.0,
    bool isActive = true,
  }) : _lastContactTime = lastContactTime,
       _lastSuccessfulContact = lastContactTime,
       _reliabilityScore = initialReliabilityScore,
       _totalAttempts = 0,
       _successfulAttempts = 0,
       _consecutiveFailures = 0,
       _isActive = isActive;

  /// Record successful contact with this peer
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

  /// Record failed contact attempt with this peer
  void recordFailedContact() {
    _lastContactTime = DateTime.now();
    _totalAttempts++;
    _consecutiveFailures++;
    _updateReliabilityScore();

    // Mark as inactive after 3 consecutive failures
    if (_consecutiveFailures >= 3) {
      _isActive = false;
    }
  }

  /// Update reliability score based on success/failure history
  void _updateReliabilityScore() {
    if (_totalAttempts == 0) return;

    final successRate = _successfulAttempts / _totalAttempts;
    final consecutiveFailurePenalty = math.min(_consecutiveFailures * 0.1, 0.5);

    _reliabilityScore = (successRate - consecutiveFailurePenalty).clamp(
      0.0,
      1.0,
    );
  }

  // Getters
  DateTime? get lastContactTime => _lastContactTime;
  DateTime? get lastSuccessfulContact => _lastSuccessfulContact;
  double get reliabilityScore => _reliabilityScore;
  bool get isActive => _isActive;
  int get consecutiveFailures => _consecutiveFailures;
  double get successRate =>
      _totalAttempts > 0 ? _successfulAttempts / _totalAttempts : 0.0;

  /// Convert to external API model (GossipPeer)
  GossipPeer toGossipPeer() {
    return GossipPeer(
      id: nodeId,
      address: address,
      metadata: metadata,
      lastContactTime: _lastContactTime,
      isActive: _isActive,
    );
  }

  @override
  String toString() =>
      'InternalGossipPeer('
      'nodeId: $nodeId, '
      'reliability: ${_reliabilityScore.toStringAsFixed(3)}, '
      'active: $_isActive'
      ')';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! InternalGossipPeer) return false;
    return nodeId == other.nodeId && address == other.address;
  }

  @override
  int get hashCode => Object.hash(nodeId, address);
}
