/// Main gossip node implementation that coordinates the gossip protocol.
///
/// This module contains the core GossipNode class that orchestrates event
/// creation, storage, and synchronization using the gossip protocol. It ties
/// together all the other components (events, vector clocks, storage, transport)
/// to provide a complete gossip protocol implementation.
library;

import 'dart:async';
import 'dart:math' as math;

import 'event.dart';
import 'event_store.dart';
import 'exceptions.dart';
import 'gossip_config.dart';

import 'transport.dart';
import 'vector_clock.dart';
import 'vector_clock_store.dart';

/// Main class implementing a gossip protocol node.
///
/// This class coordinates all aspects of the gossip protocol including:
/// - Creating and managing local events
/// - Synchronizing with peers through gossip exchanges
/// - Managing vector clocks for causality tracking
/// - Handling peer discovery and management
/// - Providing hooks for application-layer integration
///
/// The node operates asynchronously and can handle multiple concurrent
/// gossip exchanges. It's designed to be resilient to network failures
/// and peer unavailability.
class GossipNode {
  final GossipConfig config;
  final EventStore eventStore;
  final GossipTransport transport;
  final VectorClockStore? vectorClockStore;
  final VectorClock _vectorClock = VectorClock();
  final List<GossipPeer> _peers = [];
  final Map<TransportPeerAddress, GossipPeerID> _transportToNodeIdMap =
      {}; // transport address -> gossip peer ID
  final Map<GossipPeerID, GossipPeer> _nodeIdToGossipPeerMap =
      {}; // gossip peer ID -> GossipPeer
  final Map<GossipPeerID, TransportPeer> _nodeIdToTransportPeerMap =
      {}; // gossip peer ID -> TransportPeer
  final math.Random _random = math.Random();

  Timer? _gossipTimer;
  Timer? _antiEntropyTimer;
  Timer? _peerDiscoveryTimer;

  bool _isStarted = false;
  bool _isStopped = false;

  // Stream controllers for event notifications
  final StreamController<Event> _eventCreatedController =
      StreamController<Event>.broadcast();
  final StreamController<ReceivedEvent> _eventReceivedController =
      StreamController<ReceivedEvent>.broadcast();
  final StreamController<GossipPeer> _peerAddedController =
      StreamController<GossipPeer>.broadcast();
  final StreamController<GossipPeer> _peerRemovedController =
      StreamController<GossipPeer>.broadcast();
  final StreamController<GossipExchangeResult> _gossipExchangeController =
      StreamController<GossipExchangeResult>.broadcast();

  // Peer selection state for round-robin strategy
  int _lastPeerIndex = 0;
  final Map<GossipPeerID, DateTime> _lastContactTimes = {};
  final Map<GossipPeerID, double> _peerReliabilityScores = {};

  /// Creates a new gossip node with the specified configuration.
  ///
  /// Parameters:
  /// - [config]: Configuration for gossip behavior
  /// - [eventStore]: Storage backend for events
  /// - [transport]: Network transport implementation
  GossipNode({
    required this.config,
    required this.eventStore,
    required this.transport,
    this.vectorClockStore,
  });

  /// Initializes and starts the gossip node.
  ///
  /// This method:
  /// - Initializes the transport layer
  /// - Sets up incoming message handlers
  /// - Starts periodic gossip and maintenance timers
  /// - Begins peer discovery
  ///
  /// Must be called before the node can participate in gossip exchanges.
  /// Throws [NodeNotInitializedException] if initialization fails.
  Future<void> start() async {
    if (_isStarted) return;
    if (_isStopped) {
      throw const NodeNotInitializedException('Cannot restart a stopped node');
    }

    try {
      // Initialize transport
      await transport.initialize();

      // Load persisted vector clock state
      await _loadVectorClockState();

      // Set up message handlers
      _setupIncomingMessageHandlers();

      // Start periodic gossip
      _startGossipTimer();

      // Start anti-entropy if enabled
      if (config.enableAntiEntropy) {
        _startAntiEntropyTimer();
      }

      // Start peer discovery
      _startPeerDiscoveryTimer();

      _isStarted = true;
    } catch (e, stackTrace) {
      throw NodeNotInitializedException(
        'Failed to start gossip node: $e',
        cause: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Stops the gossip node and cleans up resources.
  ///
  /// This method:
  /// - Stops all periodic timers
  /// - Shuts down the transport layer
  /// - Closes stream controllers
  /// - Marks the node as stopped
  Future<void> stop() async {
    if (_isStopped) return;

    _isStopped = true;
    _isStarted = false;

    // Stop timers
    _gossipTimer?.cancel();
    _antiEntropyTimer?.cancel();
    _peerDiscoveryTimer?.cancel();

    // Shutdown transport
    await transport.shutdown();

    // Close stream controllers
    await _eventCreatedController.close();
    await _eventReceivedController.close();
    await _peerAddedController.close();
    await _peerRemovedController.close();
    await _gossipExchangeController.close();

    // Close event store
    await eventStore.close();
  }

  /// Creates a new event with the given payload.
  ///
  /// The event will be assigned a unique ID, the current timestamp from
  /// the vector clock, and saved to the event store. The vector clock
  /// state will be persisted if a vector clock store is configured.
  /// Other nodes will learn about this event through gossip exchanges.
  ///
  /// Returns the created event.
  /// Throws [InvalidEventException] if the event cannot be created.
  Future<Event> createEvent(Map<String, dynamic> payload) async {
    _checkStarted();

    if (payload.isEmpty) {
      throw const InvalidEventException('Event payload cannot be empty');
    }

    // Increment our vector clock
    _vectorClock.increment(config.nodeId);

    // Create the event
    final event = Event(
      id: '${config.nodeId}_${_vectorClock.getTimestampFor(config.nodeId)}',
      nodeId: config.nodeId,
      timestamp: _vectorClock.getTimestampFor(config.nodeId),
      creationTimestamp: DateTime.now().millisecondsSinceEpoch,
      payload: Map<String, dynamic>.from(payload),
    );

    try {
      // Save to store
      await eventStore.saveEvent(event);

      // Persist vector clock state
      await _saveVectorClockState();

      // Notify listeners
      _eventCreatedController.add(event);

      return event;
    } catch (e, stackTrace) {
      throw InvalidEventException(
        'Failed to create event: $e',
        eventData: payload,
        cause: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Adds a peer to the gossip network.
  /// You shouldn't normally add peers manually,
  /// but this is helpful for testing.
  ///
  /// The peer will be included in future gossip exchanges and peer
  /// selection algorithms.
  void addPeer(GossipPeer peer) {
    if (peer.id == config.nodeId) {
      throw ArgumentError('Cannot add self as peer');
    }

    if (!_peers.any((p) => p.id == peer.id)) {
      _peers.add(peer);
      _peerReliabilityScores[peer.id] = 100; // Start with perfect score
      _peerAddedController.add(peer);
    }
  }

  /// Removes a peer from the gossip network.
  ///
  /// Returns true if the peer was found and removed, false otherwise.
  bool removePeer(GossipPeerID peerId) {
    final peerIndex = _peers.indexWhere((p) => p.id == peerId);
    if (peerIndex >= 0) {
      final removedPeer = _peers.removeAt(peerIndex);

      // Clean up all mappings for this node ID
      _lastContactTimes.remove(peerId);
      _peerReliabilityScores.remove(peerId);
      _nodeIdToGossipPeerMap.remove(peerId);
      _nodeIdToTransportPeerMap.remove(peerId);

      // Remove reverse mapping from transport address to gossip peer ID
      _transportToNodeIdMap.removeWhere(
        (transportAddress, gossipPeerID) => gossipPeerID == peerId,
      );

      _peerRemovedController.add(removedPeer);
      return true;
    }
    return false;
  }

  /// Returns a list of currently known peers.
  List<GossipPeer> get peers => List.unmodifiable(_peers);

  /// Returns the current vector clock state.
  VectorClock get vectorClock => _vectorClock.copy();

  /// Stream of events created by this node.
  Stream<Event> get onEventCreated => _eventCreatedController.stream;

  /// Stream of events received from other nodes.
  Stream<ReceivedEvent> get onEventReceived => _eventReceivedController.stream;

  /// Stream of peers added to this node.
  Stream<GossipPeer> get onPeerAdded => _peerAddedController.stream;

  /// Stream of peers removed from this node.
  Stream<GossipPeer> get onPeerRemoved => _peerRemovedController.stream;

  /// Stream of gossip exchange results.
  Stream<GossipExchangeResult> get onGossipExchange =>
      _gossipExchangeController.stream;

  /// Manually triggers a gossip exchange with a random peer.
  ///
  /// This can be called in addition to the automatic periodic gossip
  /// to increase synchronization frequency when needed.
  Future<void> gossip() async {
    _checkStarted();
    await _performGossipCycle();
  }

  /// Manually triggers a gossip exchange with a specific peer.
  ///
  /// Parameters:
  /// - [peer]: The peer to gossip with
  ///
  /// Throws [PeerException] if the gossip exchange fails.
  Future<GossipExchangeResult> gossipWith(GossipPeer peer) async {
    _checkStarted();
    return await _gossipWithPeer(peer);
  }

  /// Performs peer discovery to find new nodes in the network.
  /// TODO: this seems useless.
  Future<void> discoverPeers() async {
    await _discoverPeers();
  }

  /// Internal peer discovery that handles transport peers properly.
  Future<void> _discoverPeers() async {
    _checkStarted();

    try {
      final discoveredTransportPeers = await transport.discoverPeers();

      // Note: We can't create GossipPeers until we know node IDs from gossip handshake
      // The transport peers will be converted to GossipPeers in _getOrCreateGossipPeer
      // when we receive gossip messages from them

      // Remove peers whose transport connections were lost
      final activeTransportIds = discoveredTransportPeers
          .map((tp) => tp.transportId)
          .toSet();

      final peersToRemove = <GossipPeerID>[];
      for (final entry in _transportToNodeIdMap.entries) {
        if (!activeTransportIds.contains(entry.key)) {
          peersToRemove.add(entry.value); // Remove by gossip peer ID
        }
      }

      for (final gossipPeerID in peersToRemove) {
        removePeer(gossipPeerID);
      }
    } catch (e) {
      // Log discovery failure but don't throw - this is best effort
    }
  }

  /// Sets up handlers for incoming gossip messages.
  void _setupIncomingMessageHandlers() {
    // Handle incoming digests
    transport.incomingDigests.listen(_handleIncomingDigest);

    // Handle incoming events
    transport.incomingEvents.listen(_handleIncomingEvents);
  }

  /// Handles an incoming gossip digest from a peer.
  ///
  /// This method processes gossip digests to determine which events need to be
  /// exchanged between nodes based on their vector clock states.
  Future<void> _handleIncomingDigest(IncomingDigest incoming) async {
    try {
      final digest = incoming.digest;
      final theirClock = VectorClock.fromMap(digest.vectorClock);
      final senderNodeId = GossipPeerID(digest.senderId);

      // Create or update GossipPeer now that we know their node ID from digest
      _getOrCreateGossipPeer(incoming.fromTransportPeer, senderNodeId);

      // Find events they're missing
      final eventsToSend = <Event>[];
      for (final entry in _vectorClock.summary.entries) {
        final theirTimestamp = theirClock.getTimestampFor(entry.key);
        if (entry.value > theirTimestamp) {
          final missingEvents = await eventStore.getEventsSince(
            entry.key,
            theirTimestamp,
            limit: config.maxEventsPerMessage,
          );
          eventsToSend.addAll(missingEvents);
        }
      }

      // Find events we're missing
      final eventRequests = <String, int>{};
      for (final entry in digest.vectorClock.entries) {
        final ourTimestamp = _vectorClock.getTimestampFor(entry.key);
        if (entry.value > ourTimestamp) {
          eventRequests[entry.key] = ourTimestamp;
        }
      }

      // Send response
      final response = GossipDigestResponse(
        senderId: config.nodeId,
        events: eventsToSend,
        eventRequests: eventRequests,
        createdAt: DateTime.now(),
      );

      await incoming.respond(response);

      // Update our knowledge
      _vectorClock.merge(theirClock);

      // Persist the updated vector clock
      await _saveVectorClockState();

      // Update peer contact time
      _lastContactTimes[senderNodeId] = DateTime.now();

      // Note: eventsToSend are events we're sending to them, not events we received
      // So we don't need to process them as received events here
    } catch (e) {
      // Log error but don't propagate - gossip should be resilient
    }
  }

  /// Handles incoming events from another node.
  Future<void> _handleIncomingEvents(IncomingEvents incoming) async {
    try {
      final receivedAt = DateTime.now();

      // Check if we have a GossipPeer established for this transport peer
      // before processing any events to avoid updating vector clock unnecessarily
      final senderNodeId = incoming.message.events.isNotEmpty
          ? GossipPeerID(incoming.message.events.first.nodeId)
          : null;

      final existingGossipPeer = senderNodeId != null
          ? _nodeIdToGossipPeerMap[senderNodeId]
          : null;

      // Only process events if we have established a GossipPeer relationship
      // through digest exchange. Don't process events from unknown peers.
      if (existingGossipPeer != null && senderNodeId != null) {
        for (final event in incoming.message.events) {
          await eventStore.saveEvent(event);

          // Update vector clock
          _vectorClock.merge(
            VectorClock()..setTimestampFor(event.nodeId, event.timestamp),
          );

          final receivedEvent = ReceivedEvent(
            event: event,
            fromPeer: existingGossipPeer,
            receivedAt: receivedAt,
          );
          _eventReceivedController.add(receivedEvent);
        }

        // Update peer contact time
        _lastContactTimes[senderNodeId] = DateTime.now();

        // Persist the updated vector clock after processing events
        await _saveVectorClockState();
      }
      // If we don't have a GossipPeer yet, ignore the events completely
      // The peer relationship will be established when we do digest exchange
    } catch (e) {
      // Log error but continue - we want to be resilient
    }
  }

  /// Starts the periodic gossip timer.
  void _startGossipTimer() {
    _gossipTimer = Timer.periodic(config.gossipInterval, (_) {
      _performGossipCycle();
    });
  }

  /// Starts the anti-entropy timer if enabled.
  void _startAntiEntropyTimer() {
    _antiEntropyTimer = Timer.periodic(config.antiEntropyInterval, (_) {
      _performAntiEntropy();
    });
  }

  /// Gets or creates a GossipPeer from transport peer and gossip peer ID.
  GossipPeer _getOrCreateGossipPeer(
    TransportPeer transportPeer,
    GossipPeerID gossipPeerID,
  ) {
    // Check if we already have a GossipPeer for this gossip peer ID
    if (_nodeIdToGossipPeerMap.containsKey(gossipPeerID)) {
      return _nodeIdToGossipPeerMap[gossipPeerID]!;
    }

    // Create new GossipPeer with proper gossip peer ID and transport address
    final gossipPeer = GossipPeer(
      id: gossipPeerID, // Use stable gossip peer ID
      address: transportPeer.transportId, // Use transport address
      lastContactTime: transportPeer.connectedAt,
      isActive: transportPeer.isActive,
      metadata: {
        'displayName': transportPeer.displayName,
        'transportId': transportPeer.transportId.value,
        ...transportPeer.metadata,
      },
    );

    // Store the mappings
    _transportToNodeIdMap[transportPeer.transportId] = gossipPeerID;
    _nodeIdToGossipPeerMap[gossipPeerID] = gossipPeer;
    _nodeIdToTransportPeerMap[gossipPeerID] = transportPeer;

    // Add to peers list if not already present
    if (!_peers.any((p) => p.id == gossipPeerID)) {
      _peers.add(gossipPeer);
      _peerAddedController.add(gossipPeer);
    }

    return gossipPeer;
  }

  /// Starts the peer discovery timer.
  void _startPeerDiscoveryTimer() {
    _peerDiscoveryTimer = Timer.periodic(
      config.peerDiscoveryInterval,
      (_) => _discoverPeers(),
    );
  }

  /// Performs a single gossip cycle with selected peers.
  Future<void> _performGossipCycle() async {
    if (_peers.isEmpty) return;

    // Select a subset of peers for gossip (fanout)
    final selectedPeers = _selectPeersForGossip();

    // Perform gossip with selected peers concurrently
    final futures = selectedPeers.map((peer) => _gossipWithPeer(peer));
    await Future.wait(futures, eagerError: false);
  }

  /// Selects peers for gossip based on the configured strategy.
  List<GossipPeer> _selectPeersForGossip() {
    final peersToSelect = math.min(config.fanout, _peers.length);
    final activePeers = _peers.where((p) => p.isActive).toList();

    if (activePeers.isEmpty) return [];

    switch (config.peerSelectionStrategy) {
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

  List<GossipPeer> _selectRandomPeers(List<GossipPeer> peers, int count) {
    final shuffled = List<GossipPeer>.from(peers)..shuffle(_random);
    return shuffled.take(count).toList();
  }

  List<GossipPeer> _selectRoundRobinPeers(List<GossipPeer> peers, int count) {
    final selected = <GossipPeer>[];
    for (int i = 0; i < count; i++) {
      selected.add(peers[(_lastPeerIndex + i) % peers.length]);
    }
    _lastPeerIndex = (_lastPeerIndex + count) % peers.length;
    return selected;
  }

  List<GossipPeer> _selectLeastRecentlyContactedPeers(
    List<GossipPeer> peers,
    int count,
  ) {
    final sorted = List<GossipPeer>.from(peers);
    sorted.sort((a, b) {
      final aTime =
          _lastContactTimes[a.id] ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          _lastContactTimes[b.id] ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aTime.compareTo(bTime);
    });
    return sorted.take(count).toList();
  }

  List<GossipPeer> _selectMostReliablePeers(List<GossipPeer> peers, int count) {
    final sorted = List<GossipPeer>.from(peers);
    sorted.sort((a, b) {
      final aScore = _peerReliabilityScores[a.id] ?? 0;
      final bScore = _peerReliabilityScores[b.id] ?? 0;
      return bScore.compareTo(aScore); // Descending order
    });
    return sorted.take(count).toList();
  }

  /// Performs a gossip exchange with a specific peer.
  Future<GossipExchangeResult> _gossipWithPeer(GossipPeer peer) async {
    final startTime = DateTime.now();
    var eventsExchanged = 0;
    var success = false;
    String? error;

    try {
      // Find the corresponding transport peer from our mapping
      final transportPeer = _nodeIdToTransportPeerMap[peer.id];
      if (transportPeer == null) {
        throw StateError('Transport peer not found for gossip peer ${peer.id}');
      }

      // Create and send digest
      final digest = GossipDigest(
        senderId: config.nodeId,
        vectorClock: _vectorClock.summary,
        createdAt: DateTime.now(),
      );

      final response = await transport.sendDigest(
        transportPeer,
        digest,
        timeout: config.gossipTimeout,
      );

      // Process received events
      final receivedAt = DateTime.now();
      for (final event in response.events) {
        await eventStore.saveEvent(event);
        _vectorClock.merge(
          VectorClock()..setTimestampFor(event.nodeId, event.timestamp),
        );

        // Create ReceivedEvent with peer information
        final receivedEvent = ReceivedEvent(
          event: event,
          fromPeer: peer,
          receivedAt: receivedAt,
        );
        _eventReceivedController.add(receivedEvent);
      }
      eventsExchanged += response.events.length;

      // Send requested events
      final eventsToSend = <Event>[];
      for (final request in response.eventRequests.entries) {
        final requestedAfterTimestamp = request.value;
        final nodeId = request.key;

        if (requestedAfterTimestamp == 0) {
          // Peer is requesting all events (likely after detecting a reset)
          final events = await eventStore.getEventsSince(
            nodeId,
            0,
            limit: config.maxEventsPerMessage,
          );
          eventsToSend.addAll(events);
        } else {
          // Normal request for events after a specific timestamp
          final events = await eventStore.getEventsSince(
            nodeId,
            requestedAfterTimestamp,
            limit: config.maxEventsPerMessage,
          );
          eventsToSend.addAll(events);
        }
      }

      if (eventsToSend.isNotEmpty) {
        final eventMessage = GossipEventMessage(
          senderId: config.nodeId,
          events: eventsToSend,
          createdAt: DateTime.now(),
        );

        await transport.sendEvents(transportPeer, eventMessage);
        eventsExchanged += eventsToSend.length;
      }

      // Persist vector clock after successful exchange
      await _saveVectorClockState();

      // Update peer state
      _lastContactTimes[peer.id] = DateTime.now();
      _updatePeerReliability(peer.id, true);

      success = true;
    } catch (e) {
      error = e.toString();
      _updatePeerReliability(peer.id, false);
    }

    final result = GossipExchangeResult(
      peer: peer,
      success: success,
      eventsExchanged: eventsExchanged,
      duration: DateTime.now().difference(startTime),
      error: error,
    );

    _gossipExchangeController.add(result);
    return result;
  }

  /// Updates the reliability score for a peer based on exchange success.
  void _updatePeerReliability(GossipPeerID peerId, bool success) {
    final currentScore = _peerReliabilityScores[peerId] ?? 100.0;
    if (success) {
      _peerReliabilityScores[peerId] = math.min(100.0, currentScore + 1.0);
    } else {
      _peerReliabilityScores[peerId] = math.max(0.0, currentScore - 5.0);
    }
  }

  /// Performs anti-entropy operations to ensure consistency.
  Future<void> _performAntiEntropy() async {
    // Implementation would perform more comprehensive synchronization
    // This is a simplified version that just does regular gossip
    await _performGossipCycle();
  }

  /// Checks that the node has been started.
  void _checkStarted() {
    if (!_isStarted) {
      throw const NodeNotInitializedException('Node has not been started');
    }
    if (_isStopped) {
      throw const NodeNotInitializedException('Node has been stopped');
    }
  }

  /// Loads the vector clock state from persistent storage.
  ///
  /// This method is called during node startup to restore any previously
  /// persisted vector clock state. If no state exists or no vector clock
  /// store is configured, the vector clock starts fresh.
  Future<void> _loadVectorClockState() async {
    if (vectorClockStore == null) {
      return; // No persistence configured
    }

    try {
      final savedClock = await vectorClockStore!.loadVectorClock(config.nodeId);
      if (savedClock != null) {
        // Restore the saved state
        for (final entry in savedClock.summary.entries) {
          _vectorClock.setTimestampFor(entry.key, entry.value);
        }
      }
    } catch (e) {
      // Log warning but continue - better to start fresh than fail to start
      // In production, you might want to handle this differently
    }
  }

  /// Saves the current vector clock state to persistent storage.
  ///
  /// This method is called after vector clock updates to ensure the state
  /// is preserved across restarts. If no vector clock store is configured,
  /// this is a no-op.
  Future<void> _saveVectorClockState() async {
    if (vectorClockStore == null) {
      return; // No persistence configured
    }

    try {
      await vectorClockStore!.saveVectorClock(config.nodeId, _vectorClock);
    } catch (e) {
      // Log error but don't fail the operation
      // The gossip protocol can continue even if persistence fails
    }
  }
}

/// Result of a gossip exchange with a peer.
class GossipExchangeResult {
  /// The peer that was contacted.
  final GossipPeer peer;

  /// Whether the exchange was successful.
  final bool success;

  /// Number of events exchanged (sent + received).
  final int eventsExchanged;

  /// Duration of the exchange.
  final Duration duration;

  /// Error message if the exchange failed.
  final String? error;

  const GossipExchangeResult({
    required this.peer,
    required this.success,
    required this.eventsExchanged,
    required this.duration,
    this.error,
  });

  @override
  String toString() {
    return 'GossipExchangeResult('
        'peer: ${peer.id}, '
        'success: $success, '
        'eventsExchanged: $eventsExchanged, '
        'duration: $duration'
        '${error != null ? ', error: $error' : ''}'
        ')';
  }
}
