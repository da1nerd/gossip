/// Use case for executing a single gossip cycle.
///
/// This use case coordinates peer selection, gossip exchanges, and handles
/// incoming gossip messages. It represents the core business logic for
/// the gossip protocol operations.
library;

import 'dart:async';

import '../../event.dart';
import '../../event_store.dart';
import '../../gossip_config.dart';
import '../../gossip_digest.dart';
import '../../gossip_digest_response.dart';
import '../../gossip_event_message.dart';
import '../../gossip_node.dart';
import '../../gossip_node_id.dart';
import '../../transport.dart';
import '../../vector_clock.dart';
import '../../domain/repositories/peer_repository.dart';
import '../services/vector_clock_service.dart';
import '../../domain/entities/internal_gossip_peer.dart';
import '../../domain/services/peer_selection_service.dart';
import '../../gossip_peer.dart';

/// Use case for executing a single gossip cycle.
///
/// Orchestrates domain services and repositories to perform gossip exchanges.
class GossipCycleUseCase {
  final PeerRepository peerRepository;
  final PeerSelectionService peerSelectionService;
  final GossipTransport transport;
  final EventStore eventStore;
  final VectorClockService vectorClockService;
  final GossipConfig config;

  GossipCycleUseCase({
    required this.peerRepository,
    required this.peerSelectionService,
    required this.transport,
    required this.eventStore,
    required this.vectorClockService,
    required this.config,
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
    final futures = selectedPeers.map((peer) => _gossipWithPeer(peer));
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

    final result = await _gossipWithPeer(peer);

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
      // Get our current vector clock
      final ourClock = vectorClockService.currentClock;
      final digest = incomingDigest.digest;

      // Determine what events the peer is missing
      final eventsToSend = await _getEventsMissingFromPeer(digest, ourClock);

      // Create response with events the peer needs
      final response = GossipDigestResponse(
        senderId: GossipNodeID(vectorClockService.nodeId),
        events: eventsToSend,
        eventRequests: {}, // We'll implement event requests if needed
        createdAt: DateTime.now(),
      );

      // Send the response back to the peer
      await incomingDigest.respond(response);

      // Update our vector clock with the peer's clock
      vectorClockService.update(VectorClock.fromMap(digest.vectorClock));
      await vectorClockService.save();
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
    final receivedEvents = <ReceivedEvent>[];

    try {
      for (final event in incomingEvents.message.events) {
        // Check if we already have this event
        final existingEvent = await eventStore.hasEvent(event.id);
        if (!existingEvent) {
          // Store the new event
          await eventStore.saveEvent(event);

          // Update our vector clock - create a VectorClock from the event's timestamp
          final eventClock = VectorClock();
          eventClock.setTimestampFor(event.nodeId.value, event.timestamp);
          vectorClockService.update(eventClock);

          // Create received event record
          receivedEvents.add(
            ReceivedEvent(
              event: event,
              fromPeer: _createGossipPeerFromTransport(
                incomingEvents.fromTransportPeer,
              ),
              receivedAt: DateTime.now(),
            ),
          );
        }
      }

      // Save vector clock state
      await vectorClockService.save();
    } catch (e) {
      // Log error but don't throw - partial processing is better than none
    }

    return receivedEvents;
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

  /// Perform gossip exchange with a single peer.
  Future<GossipExchangeResult> _gossipWithPeer(InternalGossipPeer peer) async {
    final startTime = DateTime.now();
    var eventsExchanged = 0;
    var success = false;
    String? error;

    try {
      // Find the corresponding transport peer
      final transportPeer = await _findTransportPeer(peer);
      if (transportPeer == null) {
        throw Exception('Transport peer not found for ${peer.nodeId}');
      }

      // Create and send digest
      final digest = await _createDigest();
      final digestResponse = await transport.sendDigest(transportPeer, digest);

      // Process digest response and send any events they need
      eventsExchanged = await _processDigestResponse(
        digestResponse,
        transportPeer,
      );

      success = true;
    } catch (e) {
      error = e.toString();
    }

    final duration = DateTime.now().difference(startTime);

    return GossipExchangeResult(
      peer: peer.toGossipPeer(),
      success: success,
      eventsExchanged: eventsExchanged,
      duration: duration,
      error: error,
    );
  }

  /// Find the transport peer corresponding to an internal gossip peer.
  Future<TransportPeer?> _findTransportPeer(InternalGossipPeer peer) async {
    try {
      final availablePeers = await transport.discoverPeers();
      return availablePeers
          .where((tp) => tp.address == peer.address)
          .firstOrNull;
    } catch (e) {
      return null;
    }
  }

  /// Create a gossip digest from our current state.
  Future<GossipDigest> _createDigest() async {
    final vectorClock = vectorClockService.currentClock;

    return GossipDigest(
      senderId: GossipNodeID(vectorClockService.nodeId),
      vectorClock: vectorClock.summary,
      createdAt: DateTime.now(),
    );
  }

  /// Process a digest response and send events if needed.
  Future<int> _processDigestResponse(
    GossipDigestResponse response,
    TransportPeer transportPeer,
  ) async {
    var eventsExchanged = 0;

    try {
      // If the response contains events they're sending to us
      if (response.events.isNotEmpty) {
        for (final event in response.events) {
          final hasEvent = await eventStore.hasEvent(event.id);
          if (!hasEvent) {
            await eventStore.saveEvent(event);
            eventsExchanged++;
          }
        }
      }

      // If they have event requests, send them the events they need
      if (response.eventRequests.isNotEmpty) {
        final eventsToSend = <Event>[];
        for (final entry in response.eventRequests.entries) {
          final nodeId = entry.key;
          final afterTimestamp = entry.value;

          final events = await eventStore.getEventsSince(
            nodeId,
            afterTimestamp,
            limit: 50, // Reasonable limit
          );
          eventsToSend.addAll(events);
        }

        if (eventsToSend.isNotEmpty) {
          final eventMessage = GossipEventMessage(
            senderId: GossipNodeID(vectorClockService.nodeId),
            events: eventsToSend,
            createdAt: DateTime.now(),
          );
          await transport.sendEvents(transportPeer, eventMessage);
        }
      }
    } catch (e) {
      // Log error but continue
    }

    return eventsExchanged;
  }

  /// Get events that a peer is missing based on their digest.
  Future<List<Event>> _getEventsMissingFromPeer(
    GossipDigest peerDigest,
    VectorClock ourClock,
  ) async {
    final eventsToSend = <Event>[];

    try {
      // Compare vector clocks to find events the peer is missing
      for (final entry in ourClock.summary.entries) {
        final nodeId = entry.key;
        final ourTimestamp = entry.value;
        final peerTimestamp = peerDigest.vectorClock[nodeId] ?? 0;

        if (ourTimestamp > peerTimestamp) {
          // We have newer events from this node
          final events = await eventStore.getEventsSince(
            GossipNodeID(nodeId),
            peerTimestamp,
            limit: 50,
          );
          eventsToSend.addAll(events);
        }
      }
    } catch (e) {
      // If we can't determine missing events, send nothing
      // This is safer than crashing
    }

    return eventsToSend;
  }
}
