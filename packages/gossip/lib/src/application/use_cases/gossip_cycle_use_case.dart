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
  final HandleIncomingDigestUseCase handleIncomingDigestUseCase;
  final HandleIncomingEventsUseCase handleIncomingEventsUseCase;

  GossipCycleUseCase({
    required PeerRepository peerRepository,
    required PeerSelectionService peerSelectionService,
    required GossipConfig config,
    required GossipWithPeerUseCase gossipWithPeerUseCase,
    required this.handleIncomingDigestUseCase,
    required this.handleIncomingEventsUseCase,
  });

  /// Execute a complete gossip cycle.
  ///
  /// Deprecated: selection and exchanges have moved to ConnectedGossipCycleUseCase.
  Future<List<GossipExchangeResult>> execute() async {
    return const <GossipExchangeResult>[];
  }

  /// Gossip with a specific peer by node ID.
  /// Deprecated: targeted exchanges should operate on ConnectedPeer addresses.
  Future<GossipExchangeResult> gossipWithSpecificPeer(
    GossipNodeID peerId,
  ) async {
    throw UnsupportedError(
      'GossipCycleUseCase is deprecated. Use ConnectedGossipCycleUseCase and address-based exchanges.',
    );
  }

  /// Perform anti-entropy operations.
  ///
  /// Deprecated: anti-entropy cycles are managed by ConnectedGossipCycleUseCase.
  Future<void> performAntiEntropy() async {
    return;
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

  // Legacy peer-selection and ID-based exchange helpers removed.

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
