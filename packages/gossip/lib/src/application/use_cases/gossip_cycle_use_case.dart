/// Use case for executing a single gossip cycle.
///
/// This use case coordinates peer selection, gossip exchanges, and handles
/// incoming gossip messages. It represents the core business logic for
/// the gossip protocol operations.
library;

import 'dart:async';

import '../../event.dart';
import '../../gossip_config.dart';

import '../../gossip_node.dart';
import '../../gossip_node_id.dart';
import '../../transport.dart';

import '../ports/peer_repository.dart';

import '../../domain/services/peer_selection_service.dart';
import '../../gossip_peer.dart';
import './gossip_with_peer_use_case.dart';
import './handle_incoming_digest_use_case.dart';
import './handle_incoming_events_use_case.dart';

/// Use case for executing a single gossip cycle.
///
/// Orchestrates domain services and repositories to perform gossip exchanges.
class GossipCycleUseCase {
  final PeerRepository peerRepository;
  final PeerSelectionService peerSelectionService;
  final GossipConfig config;
  final GossipWithPeerUseCase gossipWithPeerUseCase;
  final HandleIncomingDigestUseCase handleIncomingDigestUseCase;
  final HandleIncomingEventsUseCase handleIncomingEventsUseCase;

  GossipCycleUseCase({
    required this.peerRepository,
    required this.peerSelectionService,
    required this.config,
    required this.gossipWithPeerUseCase,
    required this.handleIncomingDigestUseCase,
    required this.handleIncomingEventsUseCase,
  });

  /// Execute a complete gossip cycle.
  ///
  /// This method:
  /// 1. Gets all available peers
  /// 2. Selects peers for gossip based on strategy
  /// 3. Performs gossip exchanges with selected peers
  /// 4. Updates peer reliability scores based on results
  Future<List<GossipExchangeResult>> execute() async {
    // Get all available peers
    final allPeers = await peerRepository.getAllPeers();
    if (allPeers.isEmpty) return [];

    // Select peers for this gossip cycle
    final selectedPeers = peerSelectionService.selectPeersForGossip(
      allPeers,
      config.fanout,
      config.peerSelectionStrategy,
    );

    // Perform gossip with selected peers concurrently
    final futures = selectedPeers.map(
      (peer) => gossipWithPeerUseCase.execute(peer: peer, now: DateTime.now()),
    );
    final results = await Future.wait(futures, eagerError: false);

    // Update peer states based on results
    for (int i = 0; i < results.length; i++) {
      final result = results[i];
      final peer = selectedPeers[i];

      if (result.success) {
        peer.recordSuccessfulContact();
      } else {
        peer.recordFailedContact();
      }

      await peerRepository.savePeer(peer);
    }

    return results;
  }

  /// Gossip with a specific peer by node ID.
  Future<GossipExchangeResult> gossipWithSpecificPeer(
    GossipNodeID peerId,
  ) async {
    final peer = await peerRepository.getPeerById(peerId);
    if (peer == null) {
      throw ArgumentError('Peer not found: $peerId');
    }

    final result = await gossipWithPeerUseCase.execute(
      peer: peer,
      now: DateTime.now(),
    );

    // Update peer state based on result
    if (result.success) {
      peer.recordSuccessfulContact();
    } else {
      peer.recordFailedContact();
    }

    await peerRepository.savePeer(peer);
    return result;
  }

  /// Perform anti-entropy operations.
  ///
  /// Anti-entropy ensures eventual consistency by periodically exchanging
  /// full state information with peers.
  Future<void> performAntiEntropy() async {
    // For now, anti-entropy is implemented as a regular gossip cycle
    // In the future, this could be enhanced to exchange more comprehensive
    // state information or use different peer selection strategies
    await execute();
  }

  /// Handle incoming digest message from another node.
  ///
  /// Processes the digest and sends back requested events.
  Future<void> handleIncomingDigest(IncomingDigest incomingDigest) async {
    try {
      final response = await handleIncomingDigestUseCase.createResponse(
        incoming: incomingDigest.digest,
        now: DateTime.now(),
      );
      await incomingDigest.respond(response);
    } catch (e) {
      // Log error but don't throw - we don't want one bad digest to crash the node
    }
  }

  /// Handle incoming events from another node.
  ///
  /// Processes received events and returns a list of newly received events.
  Future<List<ReceivedEvent>> handleIncomingEvents(
    IncomingEvents incomingEvents,
  ) async {
    try {
      final fromPeer = _createGossipPeerFromTransport(
        incomingEvents.fromTransportPeer,
      );
      return await handleIncomingEventsUseCase.execute(
        message: incomingEvents.message,
        fromPeer: fromPeer,
        now: DateTime.now(),
      );
    } catch (e) {
      // Log error but don't throw - partial processing is better than none
      return <ReceivedEvent>[];
    }
  }

  /// Create a GossipPeer from a TransportPeer for compatibility.
  GossipPeer _createGossipPeerFromTransport(TransportPeer transportPeer) {
    return GossipPeer(
      id: GossipNodeID(
        'unknown',
      ), // We don't have the gossip node ID from transport
      address: transportPeer.address,
      metadata: transportPeer.metadata,
      lastContactTime: transportPeer.connectedAt,
      isActive: transportPeer.isActive,
    );
  }
}
