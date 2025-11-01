/// Use case for executing a single gossip cycle.
///
/// This use case coordinates peer selection, gossip exchanges, and handles
/// incoming gossip messages. It represents the core business logic for
/// the gossip protocol operations.
library;

import 'dart:async';

import 'package:gossip/src/event.dart';
import 'package:gossip/src/gossip_config.dart';

import 'package:gossip/src/gossip_node.dart';
import 'package:gossip/src/gossip_node_id.dart';
import 'package:gossip/src/transport.dart';

import 'package:gossip/src/application/ports/peer_repository.dart';

import 'package:gossip/src/domain/services/peer_selection_service.dart';
import 'package:gossip/src/domain/entities/internal_gossip_peer.dart';
import 'package:gossip/src/gossip_peer.dart';
import 'package:gossip/src/application/use_cases/gossip_with_peer_use_case.dart';
import 'package:gossip/src/application/use_cases/handle_incoming_digest_use_case.dart';
import 'package:gossip/src/application/use_cases/handle_incoming_events_use_case.dart';

/// Use case for executing a single gossip cycle.
///
/// Orchestrates domain services and repositories to perform gossip exchanges.
@Deprecated('use ConnectedGossipCycleUseCase instead')
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
    final allPeers = await _loadAllPeers();
    if (allPeers.isEmpty) return [];

    final selectedPeers = _selectPeers(allPeers);
    final results = await _gossipWithSelectedPeers(selectedPeers);
    await _applyResultsToPeers(selectedPeers, results);

    return results;
  }

  /// Gossip with a specific peer by node ID.
  Future<GossipExchangeResult> gossipWithSpecificPeer(
    GossipNodeID peerId,
  ) async {
    final peer = await _loadPeerOrThrow(peerId);
    final result = await _gossipWithSinglePeer(peer);
    await _applyResultToPeer(peer, result);
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
      await _createAndSendDigestResponse(incomingDigest);
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
      return await _processIncomingEvents(incomingEvents);
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

  // --- Private helpers to make the use case read like prose ---

  Future<List<InternalGossipPeer>> _loadAllPeers() {
    return peerRepository.getAllPeers();
  }

  List<InternalGossipPeer> _selectPeers(List<InternalGossipPeer> allPeers) {
    return peerSelectionService.selectPeersForGossip(
      allPeers,
      config.fanout,
      config.peerSelectionStrategy,
    );
  }

  Future<List<GossipExchangeResult>> _gossipWithSelectedPeers(
    List<InternalGossipPeer> selectedPeers,
  ) {
    final futures = selectedPeers.map(
      (peer) => gossipWithPeerUseCase.execute(peer: peer, now: DateTime.now()),
    );
    return Future.wait(futures, eagerError: false);
  }

  Future<void> _applyResultsToPeers(
    List<InternalGossipPeer> selectedPeers,
    List<GossipExchangeResult> results,
  ) async {
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
  }

  Future<InternalGossipPeer> _loadPeerOrThrow(GossipNodeID peerId) async {
    final peer = await peerRepository.getPeerById(peerId);
    if (peer == null) {
      throw ArgumentError('Peer not found: $peerId');
    }
    return peer;
  }

  Future<GossipExchangeResult> _gossipWithSinglePeer(InternalGossipPeer peer) {
    return gossipWithPeerUseCase.execute(peer: peer, now: DateTime.now());
  }

  Future<void> _applyResultToPeer(
    InternalGossipPeer peer,
    GossipExchangeResult result,
  ) async {
    if (result.success) {
      peer.recordSuccessfulContact();
    } else {
      peer.recordFailedContact();
    }
    await peerRepository.savePeer(peer);
  }

  Future<void> _createAndSendDigestResponse(
    IncomingDigest incomingDigest,
  ) async {
    final response = await handleIncomingDigestUseCase.createResponse(
      incoming: incomingDigest.digest,
      now: DateTime.now(),
    );
    await incomingDigest.respond(response);
  }

  Future<List<ReceivedEvent>> _processIncomingEvents(
    IncomingEvents incomingEvents,
  ) {
    final fromPeer = _createGossipPeerFromTransport(
      incomingEvents.fromTransportPeer,
    );
    return handleIncomingEventsUseCase.execute(
      message: incomingEvents.message,
      fromPeer: fromPeer,
      now: DateTime.now(),
    );
  }
}
