/// Main gossip node implementation that coordinates the gossip protocol.
///
/// This module contains the core GossipNode class that orchestrates event
/// creation, storage, and synchronization using the gossip protocol. It ties
/// together all the other components (events, vector clocks, storage, transport)
/// to provide a complete gossip protocol implementation.
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:async/async.dart';
import 'package:uuid/uuid.dart';

import 'event.dart';
import 'event_store.dart';
import 'exceptions.dart';
import 'gossip_config.dart';
import 'gossip_digest.dart';
import 'gossip_digest_response.dart';
import 'gossip_event_message.dart';
import 'gossip_node_id.dart';
import 'gossip_peer.dart';

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
  final Map<TransportPeerAddress, GossipNodeID> _transportToNodeIdMap = {};
  final Map<GossipNodeID, GossipPeer> _nodeIdToGossipPeerMap = {};
  final Map<GossipNodeID, TransportPeer> _nodeIdToTransportPeerMap = {};
  final math.Random _random = math.Random();

  Timer? _gossipTimer;
  Timer? _antiEntropyTimer;
  Timer? _peerDiscoveryTimer;

  bool _isInitialized = false;
  bool _isGossiping = false;
  // Reentrancy guard to avoid overlapping gossip cycles
  bool _gossipCycleInProgress = false;

  // Subscriptions for incoming transport streams
  StreamSubscription<IncomingDigest>? _digestSub;
  StreamSubscription<IncomingEvents>? _eventsSub;

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
  final Map<GossipNodeID, DateTime> _lastContactTimes = {};
  final Map<GossipNodeID, double> _peerReliabilityScores = {};

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

  /// Initializes the gossip node without starting gossip activities.
  ///
  /// This method:
  /// - Initializes the transport layer
  /// - Sets up incoming message handlers
  /// - Loads persisted vector clock state
  ///
  /// After initialization, the node can create events but will not sync
  /// with other nodes until startGossiping() is called.
  ///
  /// Must be called before any other operations.
  /// Throws [NodeNotInitializedException] if initialization fails.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize transport
      await transport.initialize();

      // Load persisted vector clock state
      await _loadVectorClockState();

      // Set up message handlers
      _setupIncomingMessageHandlers();

      _isInitialized = true;
    } catch (e, stackTrace) {
      throw NodeNotInitializedException(
        'Failed to initialize gossip node: $e',
        cause: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Shuts down the gossip node and cleans up all resources.
  ///
  /// This method:
  /// - Stops gossiping if currently active
  /// - Shuts down the transport layer
  /// - Closes stream controllers
  /// - Closes the event store
  /// - Marks the node as shut down
  Future<void> shutdown() async {
    if (!_isInitialized) return;

    // Stop gossiping if currently active
    if (_isGossiping) {
      await stopGossiping();
    }

    // Cancel transport stream subscriptions
    await _digestSub?.cancel();
    await _eventsSub?.cancel();

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

    _isInitialized = false;
  }

  /// Starts gossip activities and network synchronization.
  ///
  /// This method:
  /// - Starts active transport communication
  /// - Starts periodic gossip and maintenance timers
  /// - Begins peer discovery
  ///
  /// The node must be initialized before calling this method.
  /// Can be called multiple times to resume gossiping after stopping.
  /// Throws [NodeNotInitializedException] if not initialized.
  Future<void> startGossiping() async {
    _checkInitialized();
    if (_isGossiping) return;

    try {
      // Start active transport communication
      await transport.start();

      // Start periodic gossip
      _startGossipTimer();

      // Start anti-entropy if enabled
      if (config.enableAntiEntropy) {
        _startAntiEntropyTimer();
      }

      // Start peer discovery
      _startPeerDiscoveryTimer();

      _isGossiping = true;
    } catch (e, stackTrace) {
      throw NodeNotInitializedException(
        'Failed to start gossiping: $e',
        cause: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Stops gossip activities but keeps the node initialized.
  ///
  /// This method:
  /// - Stops all periodic timers
  /// - Stops active transport communication
  /// - Preserves node state and connections
  ///
  /// The node remains initialized and can create events.
  /// Gossiping can be resumed by calling startGossiping().
  Future<void> stopGossiping() async {
    if (!_isGossiping) return;

    // Stop timers
    _gossipTimer?.cancel();
    _antiEntropyTimer?.cancel();
    _peerDiscoveryTimer?.cancel();

    // Stop active transport communication
    await transport.stop();

    _isGossiping = false;
  }

  /// Initializes and starts the gossip node (backward compatibility).
  ///
  /// This method calls initialize() followed by startGossiping() to maintain
  /// backward compatibility with existing code. New code should use the
  /// separate initialize() and startGossiping() methods for more control.
  ///
  /// Throws [NodeNotInitializedException] if initialization or starting fails.
  @Deprecated(
    'Use initialize() and startGossiping() separately for better control',
  )
  Future<void> start() async {
    await initialize();
    await startGossiping();
  }

  /// Stops the gossip node and cleans up resources (backward compatibility).
  ///
  /// This method is equivalent to shutdown() and is provided for backward
  /// compatibility with existing code. New code should use shutdown()
  /// or stopGossiping() depending on the desired behavior.
  @Deprecated('Use shutdown() or stopGossiping() depending on needs')
  Future<void> stop() async {
    await shutdown();
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
    _checkInitialized();

    if (payload.isEmpty) {
      throw const InvalidEventException('Event payload cannot be empty');
    }

    // Increment our vector clock to get a unique logical timestamp
    _vectorClock.increment(config.nodeId);
    final ts = _vectorClock.getTimestampFor(config.nodeId);

    // Create a decoupled event ID
    final id = const Uuid().v4();
    final event = Event(
      id: id,
      nodeId: GossipNodeID(config.nodeId),
      timestamp: ts,
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
  @Deprecated('Will be removed in a future release')
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
  bool removePeer(GossipNodeID peerId) {
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

  /// Whether the node is initialized and ready for operations.
  bool get isInitialized => _isInitialized;

  /// Whether the node is actively gossiping with other nodes.
  bool get isGossiping => _isGossiping;

  /// Stream of events created by this node.
  Stream<Event> get onEventCreated => _eventCreatedController.stream;

  /// Stream of events received from other nodes.
  Stream<ReceivedEvent> get onEventReceived => _eventReceivedController.stream;

  /// A unified stream of all events created or received by this node.
  /// Streamed events are either of type GossipEventCreated or GossipEventReceived.
  Stream<GossipEventBase> get onEvent {
    return StreamGroup.merge([
      _eventCreatedController.stream.map((event) => GossipEventCreated(event)),
      _eventReceivedController.stream.map(
        (event) => GossipEventReceived(event),
      ),
    ]);
  }

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
  /// Requires the node to be gossiping actively.
  Future<void> gossip() async {
    _checkGossiping();
    await _performGossipCycle();
  }

  /// Manually triggers a gossip exchange with a specific peer.
  ///
  /// Parameters:
  /// - [peer]: The peer to gossip with
  ///
  /// Requires the node to be gossiping actively.
  /// Throws [PeerException] if the gossip exchange fails.
  Future<GossipExchangeResult> gossipWith(GossipPeer peer) async {
    _checkGossiping();
    return await _gossipWithPeer(peer);
  }

  /// Manually triggers vector clock garbage collection.
  ///
  /// This removes vector clock entries for nodes that haven't been seen
  /// for longer than the configured expiration time. Only runs if vector
  /// clock GC is enabled in the configuration.
  ///
  /// Returns the number of nodes that were removed from the vector clock.
  Future<int> garbageCollectVectorClock() async {
    _checkInitialized();
    return await _performVectorClockGC();
  }

  /// Performs peer discovery to find new nodes in the network.
  /// Requires the node to be gossiping actively.
  /// A peer is removed only when all known transport addresses for that peer
  /// are no longer discovered.
  Future<void> discoverPeers() async {
    _checkGossiping();

    try {
      final discoveredTransportPeers = await transport.discoverPeers();

      // Proactively initiate gossip with new transport peers
      for (final transportPeer in discoveredTransportPeers) {
        // Skip if we already have a gossip relationship with this transport peer
        if (!_transportToNodeIdMap.containsKey(transportPeer.address)) {
          // Send initial digest to establish gossip relationship
          await _initiateGossipWithTransportPeer(transportPeer);
        }
      }

      // Remove peers only if none of their known addresses are active
      final activeTransportIds = discoveredTransportPeers
          .map((tp) => tp.address)
          .toSet();

      final activeNodeIds = activeTransportIds
          .map((addr) => _transportToNodeIdMap[addr])
          .whereType<GossipNodeID>()
          .toSet();

      final peersToRemove = <GossipNodeID>[];
      for (final nodeId in _nodeIdToGossipPeerMap.keys) {
        if (!activeNodeIds.contains(nodeId)) {
          peersToRemove.add(nodeId);
        }
      }

      for (final gossipPeerID in peersToRemove) {
        removePeer(gossipPeerID);
      }
    } catch (e) {
      // TODO: Log discovery failure but don't throw - this is best effort
    }
  }

  /// Sets up handlers for incoming gossip messages.
  void _setupIncomingMessageHandlers() {
    // Handle incoming digests
    _digestSub = transport.incomingDigests.listen(_handleIncomingDigest);

    // Handle incoming events
    _eventsSub = transport.incomingEvents.listen(_handleIncomingEvents);
  }

  /// Handles an incoming gossip digest from a peer.
  ///
  /// This method processes gossip digests to determine which events need to be
  /// exchanged between nodes based on their vector clock states.
  Future<void> _handleIncomingDigest(IncomingDigest incoming) async {
    try {
      final digest = incoming.digest;
      final theirClock = VectorClock.fromMap(digest.vectorClock);
      final senderNodeId = digest.senderId;

      // Create or update GossipPeer now that we know their node ID from digest
      _getOrCreateGossipPeer(incoming.fromTransportPeer, senderNodeId);

      // Find events they're missing
      final eventsToSend = <Event>[];
      for (final entry in _vectorClock.summary.entries) {
        final theirTimestamp = theirClock.getTimestampFor(entry.key);
        if (entry.value > theirTimestamp) {
          final missingEvents = await eventStore.getEventsSince(
            GossipNodeID(entry.key),
            theirTimestamp,
            limit: config.maxEventsPerMessage,
          );
          eventsToSend.addAll(missingEvents);
        }
      }

      // Find events we're missing (ignore our own node ID)
      final eventRequests = <GossipNodeID, int>{};
      for (final entry in digest.vectorClock.entries) {
        if (entry.key == config.nodeId) {
          continue;
        }
        final ourTimestamp = _vectorClock.getTimestampFor(entry.key);
        if (entry.value > ourTimestamp) {
          eventRequests[GossipNodeID(entry.key)] = ourTimestamp;
        }
      }

      // Send response
      final capped = _capForMessage(eventsToSend);
      final response = GossipDigestResponse(
        senderId: GossipNodeID(config.nodeId),
        events: capped,
        eventRequests: eventRequests,
        createdAt: DateTime.now(),
      );

      await incoming.respond(response);

      // Update peer contact time
      _lastContactTimes[senderNodeId] = DateTime.now();

      // Note: eventsToSend are events we're sending to them, not events we received
      // So we don't need to process them as received events here
    } catch (e) {
      // TODO: Log error but don't propagate - gossip should be resilient
    }
  }

  /// Cap events for a message to fit within the maximum message size.
  List<Event> _capForMessage(List<Event> events) {
    final capped = <Event>[];
    var bytes = 0;
    for (final e in events) {
      if (capped.length >= config.maxEventsPerMessage) break;
      final sz = e.toJson().toString().length; // rough size OK
      if (bytes + sz > config.maxMessageSizeBytes) break;
      capped.add(e);
      bytes += sz;
    }
    return capped;
  }

  /// Handles incoming events from another node with sender validation.
  Future<void> _handleIncomingEvents(IncomingEvents incoming) async {
    try {
      final receivedAt = DateTime.now();

      // Validate that the claimed sender matches the established mapping
      final mappedSenderId =
          _transportToNodeIdMap[incoming.fromTransportPeer.address];
      final claimedSenderId = incoming.message.senderId;

      // Only process events if we have an established mapping and it matches
      if (mappedSenderId != null && mappedSenderId == claimedSenderId) {
        final existingGossipPeer = _nodeIdToGossipPeerMap[claimedSenderId];

        if (existingGossipPeer != null) {
          for (final event in incoming.message.events) {
            // Check if this is a new event to avoid duplicate notifications
            final isNewEvent = !(await eventStore.hasEvent(event.id));

            await eventStore.saveEvent(event);

            // Update vector clock
            _vectorClock.merge(
              VectorClock()
                ..setTimestampFor(event.nodeId.value, event.timestamp),
            );

            _lastContactTimes[event.nodeId] = receivedAt;

            // Only notify application layer if this is a new event
            if (isNewEvent) {
              final receivedEvent = ReceivedEvent(
                event: event,
                fromPeer: existingGossipPeer,
                receivedAt: receivedAt,
              );
              _eventReceivedController.add(receivedEvent);
            }
          }

          // Update peer contact time
          _lastContactTimes[claimedSenderId] = DateTime.now();

          // Persist the updated vector clock after processing events
          await _saveVectorClockState();
        }
      }
      // If we don't have a GossipPeer yet, or mapping mismatched, ignore the events
    } catch (e) {
      // TODO: Log error but continue - we want to be resilient
    }
  }

  /// Starts the periodic gossip timer.
  /// Uses a reentrancy guard to avoid overlapping cycles when a tick fires
  /// while a previous cycle is still running.
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
    GossipNodeID gossipPeerID,
  ) {
    // Check if we already have a GossipPeer for this gossip peer ID
    if (_nodeIdToGossipPeerMap.containsKey(gossipPeerID)) {
      return _nodeIdToGossipPeerMap[gossipPeerID]!;
    }

    // Create new GossipPeer with proper gossip peer ID and transport address
    final gossipPeer = GossipPeer(
      id: gossipPeerID, // Use stable gossip peer ID
      address: transportPeer.address, // Use transport address
      lastContactTime: transportPeer.connectedAt,
      isActive: transportPeer.isActive,
      metadata: {
        'displayName': transportPeer.displayName,
        'transportId': transportPeer.address.value,
        ...transportPeer.metadata,
      },
    );

    // Store the mappings
    _transportToNodeIdMap[transportPeer.address] = gossipPeerID;
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
      (_) => discoverPeers(),
    );
  }

  /// Performs a single gossip cycle with selected peers.
  Future<void> _performGossipCycle() async {
    if (_peers.isEmpty) return;
    if (_gossipCycleInProgress) return;

    _gossipCycleInProgress = true;
    try {
      // Select a subset of peers for gossip (fanout)
      final selectedPeers = _selectPeersForGossip();

      // Perform gossip with selected peers concurrently
      final futures = selectedPeers.map((peer) => _gossipWithPeer(peer));
      await Future.wait(futures, eagerError: false);
    } finally {
      _gossipCycleInProgress = false;
    }
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

      final response = await _exchangeDigestsWithTransportPeer(transportPeer);

      // Validate response sender matches the expected peer id
      if (response.senderId != peer.id) {
        throw StateError(
          'Digest response sender mismatch: expected ${peer.id}, got ${response.senderId}',
        );
      }

      // Process received events with existing peer
      eventsExchanged += await _processReceivedEvents(response.events, peer);

      // Send requested events
      eventsExchanged += await _sendRequestedEvents(
        response.eventRequests,
        transportPeer,
      );

      // Update peer state tracking
      await _updateSuccessfulDigestExchange(peer.id);

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

  /// Initiates gossip with a newly discovered transport peer.
  Future<void> _initiateGossipWithTransportPeer(
    TransportPeer transportPeer,
  ) async {
    try {
      final response = await _exchangeDigestsWithTransportPeer(transportPeer);

      // Validate mapping consistency for this transport address
      final existingMapped = _transportToNodeIdMap[transportPeer.address];
      if (existingMapped != null && existingMapped != response.senderId) {
        // Inconsistent mapping; ignore this peer for now
        return;
      }

      // Create or get the gossip peer using the sender ID from response
      final senderNodeId = response.senderId;
      final gossipPeer = _getOrCreateGossipPeer(transportPeer, senderNodeId);

      // Process received events with newly created peer
      await _processReceivedEvents(response.events, gossipPeer);

      // Send requested events
      await _sendRequestedEvents(response.eventRequests, transportPeer);

      // Update peer state tracking
      await _updateSuccessfulDigestExchange(senderNodeId);
    } catch (e) {
      // Log error but don't propagate - peer discovery should be resilient
      // The peer might not be ready or might have connection issues
    }
  }

  /// Sends a digest and returns the response.
  Future<GossipDigestResponse> _exchangeDigestsWithTransportPeer(
    TransportPeer transportPeer,
  ) async {
    final digest = GossipDigest(
      senderId: GossipNodeID(config.nodeId),
      vectorClock: _vectorClock.summary,
      createdAt: DateTime.now(),
    );

    return await transport.sendDigest(
      transportPeer,
      digest,
      timeout: config.gossipTimeout,
    );
  }

  /// Processes received events and returns the count of events processed.
  Future<int> _processReceivedEvents(
    List<Event> events,
    GossipPeer peer,
  ) async {
    final receivedAt = DateTime.now();

    for (final event in events) {
      // Check if this is a new event to avoid duplicate notifications
      final isNewEvent = !(await eventStore.hasEvent(event.id));

      await eventStore.saveEvent(event);
      _vectorClock.merge(
        VectorClock()..setTimestampFor(event.nodeId.value, event.timestamp),
      );
      _lastContactTimes[event.nodeId] = receivedAt;

      // Only notify application layer if this is a new event
      if (isNewEvent) {
        final receivedEvent = ReceivedEvent(
          event: event,
          fromPeer: peer,
          receivedAt: receivedAt,
        );
        _eventReceivedController.add(receivedEvent);
      }
    }

    return events.length;
  }

  /// Sends requested events and returns the count of events sent.
  /// Events are chunked to respect maxEventsPerMessage and maxMessageSizeBytes.
  Future<int> _sendRequestedEvents(
    Map<GossipNodeID, int> eventRequests,
    TransportPeer transportPeer,
  ) async {
    final eventsToSend = <Event>[];

    for (final request in eventRequests.entries) {
      final requestedAfterTimestamp = request.value;
      final nodeId = request.key.value;

      if (requestedAfterTimestamp == 0) {
        // Peer is requesting all events (likely after detecting a reset)
        final events = await eventStore.getEventsSince(
          GossipNodeID(nodeId),
          0,
          limit: config.maxEventsPerMessage,
        );
        eventsToSend.addAll(events);
      } else {
        // Normal request for events after a specific timestamp
        final events = await eventStore.getEventsSince(
          GossipNodeID(nodeId),
          requestedAfterTimestamp,
          limit: config.maxEventsPerMessage,
        );
        eventsToSend.addAll(events);
      }
    }

    if (eventsToSend.isEmpty) {
      return 0;
    }

    final capped = _capForMessage(eventsToSend);
    final eventMessage = GossipEventMessage(
      senderId: GossipNodeID(config.nodeId),
      events: capped,
      createdAt: DateTime.now(),
    );
    if (capped.length > 0) {
      await transport.sendEvents(transportPeer, eventMessage);
    }
    return capped.length;
  }

  /// Updates state after a successful exchange.
  Future<void> _updateSuccessfulDigestExchange(GossipNodeID peerId) async {
    // Persist vector clock after successful exchange
    await _saveVectorClockState();

    // Update peer state
    _lastContactTimes[peerId] = DateTime.now();
    _updatePeerReliability(peerId, true);
  }

  /// Updates the reliability score for a peer based on exchange success.
  void _updatePeerReliability(GossipNodeID peerId, bool success) {
    final currentScore = _peerReliabilityScores[peerId] ?? 100.0;
    if (success) {
      _peerReliabilityScores[peerId] = math.min(100.0, currentScore + 1.0);
    } else {
      _peerReliabilityScores[peerId] = math.max(0.0, currentScore - 5.0);
    }
  }

  /// Performs anti-entropy operations to ensure consistency.
  Future<void> _performAntiEntropy() async {
    // Perform vector clock garbage collection before anti-entropy
    await _garbageCollectVectorClock();

    // Implementation would perform more comprehensive synchronization
    // This is a simplified version that just does regular gossip
    await _performGossipCycle();
  }

  /// Performs garbage collection on the vector clock to remove entries
  /// for nodes that haven't been seen for longer than the configured
  /// expiration time.
  ///
  /// This prevents unbounded growth of vector clocks in systems with
  /// high node churn. Only runs if vector clock GC is enabled in config.
  Future<void> _garbageCollectVectorClock() async {
    // Reuse the public method logic but don't check if started
    // since this is called during internal operations
    await _performVectorClockGC();
  }

  /// Internal method that performs the actual vector clock garbage collection.
  Future<int> _performVectorClockGC() async {
    if (!config.enableVectorClockGC) return 0;

    final now = DateTime.now();
    final expiredNodes = <String>[];

    // Find nodes that haven't been seen for too long
    for (final nodeId in _vectorClock.knownNodes) {
      // Never remove our own node from the vector clock
      if (nodeId == config.nodeId) continue;

      final lastContact = _lastContactTimes[GossipNodeID(nodeId)];
      if (lastContact == null ||
          now.difference(lastContact) > config.nodeExpirationAge) {
        expiredNodes.add(nodeId);
      }
    }

    // Remove expired nodes from vector clock
    for (final nodeId in expiredNodes) {
      _vectorClock.removeNode(nodeId);
    }

    // Persist the cleaned vector clock if any nodes were removed
    if (expiredNodes.isNotEmpty) {
      await _saveVectorClockState();
    }

    return expiredNodes.length;
  }

  /// Checks that the node has been initialized.
  void _checkInitialized() {
    if (!_isInitialized) {
      throw const NodeNotInitializedException('Node has not been initialized');
    }
  }

  /// Checks that the node is actively gossiping.
  void _checkGossiping() {
    _checkInitialized();
    if (!_isGossiping) {
      throw const NodeNotInitializedException('Node is not gossiping');
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
      // TODO: Log warning but continue - better to start fresh than fail to start
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
      // TODO: Log error but don't fail the operation
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
