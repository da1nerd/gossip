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
import 'simple_transport.dart';
import 'stores/memory_event_store.dart';
import 'transport.dart';
import 'vector_clock.dart';

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
  final VectorClock _vectorClock = VectorClock();
  final List<GossipPeer> _peers = [];
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
  final Map<String, DateTime> _lastContactTimes = {};
  final Map<String, int> _peerReliabilityScores = {};

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
  });

  /// Creates a simple gossip node with custom simple transport.
  ///
  /// This factory constructor makes it easier to use simple transport
  /// implementations by automatically wrapping them with the adapter.
  ///
  /// Parameters:
  /// - [nodeId]: Unique identifier for this node
  /// - [transport]: Simple transport implementation
  /// - [eventStore]: Optional event store (defaults to MemoryEventStore)
  /// - [config]: Optional configuration (uses nodeId if not provided)
  factory GossipNode.simple({
    required String nodeId,
    required SimpleGossipTransport transport,
    EventStore? eventStore,
    GossipConfig? config,
  }) {
    return GossipNode(
      config: config ?? GossipConfig(nodeId: nodeId),
      eventStore: eventStore ?? MemoryEventStore(),
      transport: SimpleTransportAdapter(transport),
    );
  }

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

      // Set up incoming message handlers
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

  /// Creates a new event with the specified payload.
  ///
  /// The event is assigned a unique ID, timestamped with the current
  /// vector clock value, and saved to the local event store.
  ///
  /// Parameters:
  /// - [payload]: Application-specific event data
  ///
  /// Returns the created event.
  /// Throws [InvalidEventException] if the payload is invalid.
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
  ///
  /// The peer will be included in future gossip exchanges and peer
  /// selection algorithms.
  /// TODO: this is not used
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
  bool removePeer(String peerId) {
    final peerIndex = _peers.indexWhere((p) => p.id == peerId);
    if (peerIndex >= 0) {
      final removedPeer = _peers.removeAt(peerIndex);
      _lastContactTimes.remove(peerId);
      _peerReliabilityScores.remove(peerId);
      _peerRemovedController.add(removedPeer);
      return true;
    }
    return false;
  }

  /// Returns a list of currently known peers.
  List<GossipPeer> get peers => List.unmodifiable(_peers);

  /// Returns the current vector clock state.
  VectorClock get vectorClock => _vectorClock.copy();

  /// Sets the vector clock timestamp for a specific node (for testing only).
  ///
  /// **⚠️ Warning: This method is intended for testing only!**
  ///
  /// This method should only be used in test environments to simulate
  /// specific vector clock states for testing vector clock reset detection
  /// and other edge cases.
  ///
  /// In production, vector clocks should only be modified through normal
  /// event creation and gossip exchange processes.
  void setVectorClockTimestamp(String nodeId, int timestamp) {
    _vectorClock.setTimestampFor(nodeId, timestamp);
  }

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
  Future<void> discoverPeers() async {
    _checkStarted();

    try {
      final discoveredPeers = await transport.discoverPeers();

      // Add new peers
      for (final peer in discoveredPeers) {
        if (peer.id != config.nodeId && !_peers.any((p) => p.id == peer.id)) {
          addPeer(peer);
        }
      }

      // Remove lost peers
      for (final peer in _peers) {
        if (!discoveredPeers.any((p) => p.id == peer.id)) {
          removePeer(peer.id);
        }
      }
    } catch (e) {
      // TODO: Log discovery failure but don't throw - this is best effort
    }
  }

  /// Sets up handlers for incoming gossip messages.
  void _setupIncomingMessageHandlers() {
    // Handle incoming digests
    transport.incomingDigests.listen(_handleIncomingDigest);

    // Handle incoming events
    transport.incomingEvents.listen(_handleIncomingEvents);
  }

  /// Handles an incoming gossip digest from another node.
  /// Handles an incoming gossip digest from a peer.
  ///
  /// This method implements vector clock reset detection to handle scenarios
  /// where a peer's vector clock has been reset (e.g., due to storage loss,
  /// system restart, or other failures). The detection works by:
  ///
  /// 1. **Normal Case**: If their timestamp > our timestamp, request missing events
  /// 2. **Reset Detection**: If their timestamp < our timestamp, assume reset and request all events
  /// 3. **Bidirectional Protection**: Also send recent events if we might have reset
  ///
  /// **Vector Clock Reset Scenarios:**
  /// - Peer goes offline, loses vector clock state, comes back with timestamp 1
  /// - Storage corruption causes vector clock to be reset to initial state
  /// - Application restart without persisted vector clock state
  ///
  /// **Detection Strategy:**
  /// When a peer reports a timestamp lower than what we believe they should have,
  /// we assume they've reset their vector clock and request ALL their events from
  /// timestamp 0. This ensures we don't miss new events created after the reset.
  ///
  /// **Safety:**
  /// The gossip protocol handles duplicate events gracefully, so requesting from
  /// timestamp 0 is safe even if it wasn't actually a reset.
  Future<void> _handleIncomingDigest(IncomingDigest incoming) async {
    try {
      final digest = incoming.digest;
      final theirClock = VectorClock.fromMap(digest.vectorClock);

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
        } else if (entry.value < theirTimestamp) {
          // Potential reset on our side - check if we have newer events they might need
          // by looking at creation timestamps of recent events
          final ourRecentEvents = await eventStore.getEventsSince(
            entry.key,
            0, // Get all our events for this node
            limit: config.maxEventsPerMessage,
          );

          // Send events that were created recently even if they have lower logical timestamps
          // This handles the case where we reset and created new events
          final now = DateTime.now().millisecondsSinceEpoch;
          final recentThreshold = now -
              (config.gossipInterval.inMilliseconds *
                  10); // Last 10 gossip intervals

          final recentEvents = ourRecentEvents
              .where((event) => event.creationTimestamp > recentThreshold)
              .toList();

          if (recentEvents.isNotEmpty) {
            eventsToSend.addAll(recentEvents);
          }
        }
      }

      // Find events we're missing (with vector clock reset detection)
      final eventRequests = <String, int>{};
      for (final entry in digest.vectorClock.entries) {
        final ourTimestamp = _vectorClock.getTimestampFor(entry.key);
        if (entry.value > ourTimestamp) {
          // Normal case: they're ahead of us
          eventRequests[entry.key] = ourTimestamp;
        } else if (entry.value < ourTimestamp) {
          // **Vector Clock Reset Detection**
          // Their reported timestamp is lower than what we think they should have.
          // This indicates they may have reset their vector clock and created new
          // events with lower logical timestamps than we expected.
          //
          // Example scenario:
          // - We think peer is at timestamp 100
          // - Peer reports timestamp 3 (after reset and creating 3 new events)
          // - Without this detection, we'd miss their new events 1, 2, 3
          //
          // Solution: Request all their events from timestamp 0 to ensure we get
          // any events created after the reset.
          eventRequests[entry.key] = 0;
        }
        // Note: If entry.value == ourTimestamp, no events are needed
      }

      // Send response
      final response = GossipDigestResponse(
        senderId: config.nodeId,
        events: eventsToSend,
        eventRequests: eventRequests,
        createdAt: DateTime.now(),
      );

      await incoming.respond(response);

      // **Selective Vector Clock Merge**
      // Only merge vector clock entries that advance our knowledge.
      // Don't merge lower timestamps as they might indicate resets - we keep
      // our higher timestamp until we receive confirmation that the peer
      // actually has events at those higher timestamps.
      for (final entry in theirClock.summary.entries) {
        final ourTimestamp = _vectorClock.getTimestampFor(entry.key);
        if (entry.value > ourTimestamp) {
          _vectorClock.setTimestampFor(entry.key, entry.value);
        }
      }

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

      for (final event in incoming.message.events) {
        await eventStore.saveEvent(event);

        // Update vector clock
        _vectorClock.merge(
          VectorClock()..setTimestampFor(event.nodeId, event.timestamp),
        );

        // Create ReceivedEvent with peer information
        final receivedEvent = ReceivedEvent(
          event: event,
          fromPeer: incoming.fromPeer,
          receivedAt: receivedAt,
        );

        _eventReceivedController.add(receivedEvent);
      }

      // Update peer contact time
      final peerId = incoming.fromPeer.id;
      _lastContactTimes[peerId] = DateTime.now();
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

  /// Starts the peer discovery timer.
  void _startPeerDiscoveryTimer() {
    _peerDiscoveryTimer = Timer.periodic(
      config.peerDiscoveryInterval,
      (_) => discoverPeers(),
    );
  }

  /// Performs a single gossip cycle with selected peers.
  Future<void> _performGossipCycle() async {
    if (_peers.isEmpty) return;

    final selectedPeers = _selectPeersForGossip();

    // Gossip with selected peers concurrently
    final futures = selectedPeers.map(_gossipWithPeer);
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
      // Create and send digest
      final digest = GossipDigest(
        senderId: config.nodeId,
        vectorClock: _vectorClock.summary,
        createdAt: DateTime.now(),
      );

      final response = await transport.sendDigest(
        peer,
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

        await transport.sendEvents(peer, eventMessage);
        eventsExchanged += eventsToSend.length;
      }

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
  void _updatePeerReliability(String peerId, bool success) {
    final currentScore = _peerReliabilityScores[peerId] ?? 100;
    if (success) {
      _peerReliabilityScores[peerId] = math.min(100, currentScore + 1);
    } else {
      _peerReliabilityScores[peerId] = math.max(0, currentScore - 5);
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
