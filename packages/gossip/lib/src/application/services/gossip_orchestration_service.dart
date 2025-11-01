/// Service that orchestrates gossip operations and manages lifecycle.
///
/// This service coordinates gossip operations, manages timers for periodic
/// activities, and handles incoming transport messages. It acts as the
/// orchestration layer between the transport and domain logic.
library;

import 'dart:async';

import '../../event.dart';
import '../../gossip_config.dart';
import '../../transport.dart';
import '../use_cases/gossip_cycle_use_case.dart';
import 'event_creation_service.dart';
import 'peer_management_service.dart';

/// Service that orchestrates gossip operations and manages lifecycle.
class GossipOrchestrationService {
  final GossipConfig config;
  final GossipTransport transport;
  final GossipCycleUseCase gossipCycleUseCase;
  final EventCreationService eventCreationService;
  final PeerManagementService peerManagementService;

  // Infrastructure concerns (timers)
  Timer? _gossipTimer;
  Timer? _antiEntropyTimer;
  Timer? _peerDiscoveryTimer;

  // Transport subscriptions
  StreamSubscription<IncomingDigest>? _digestSub;
  StreamSubscription<IncomingEvents>? _eventsSub;

  final StreamController<ReceivedEvent> _eventReceivedController =
      StreamController<ReceivedEvent>.broadcast();

  bool _isGossiping = false;
  bool _gossipCycleInProgress = false;

  GossipOrchestrationService({
    required this.config,
    required this.transport,
    required this.gossipCycleUseCase,
    required this.eventCreationService,
    required this.peerManagementService,
  });

  /// Stream of events that have been received from other nodes.
  Stream<ReceivedEvent> get eventReceived => _eventReceivedController.stream;

  /// Whether gossip operations are currently active.
  bool get isGossiping => _isGossiping;

  /// Initialize the orchestration service.
  ///
  /// This sets up transport message handlers but does not start gossiping.
  Future<void> initialize() async {
    await transport.initialize();
    await _setupIncomingMessageHandlers();
  }

  /// Shutdown and cleanup all resources.
  Future<void> shutdown() async {
    await stopGossiping();
    await _digestSub?.cancel();
    await _eventsSub?.cancel();
    await transport.shutdown();
    await _eventReceivedController.close();
  }

  /// Start gossip operations and periodic activities.
  Future<void> startGossiping() async {
    if (_isGossiping) return;

    // Ensure transport is started before scheduling timers
    await transport.start();

    _startGossipTimer();
    _startAntiEntropyTimer();
    _startPeerDiscoveryTimer();

    _isGossiping = true;
  }

  /// Stop gossip operations and cancel all timers.
  Future<void> stopGossiping() async {
    _gossipTimer?.cancel();
    _antiEntropyTimer?.cancel();
    _peerDiscoveryTimer?.cancel();

    // Stop transport to cease network activity
    await transport.stop();

    _isGossiping = false;
  }

  /// Start the periodic gossip timer.
  void _startGossipTimer() {
    _gossipTimer = Timer.periodic(
      config.gossipInterval,
      (_) => _performGossipCycle(),
    );
  }

  /// Start the periodic anti-entropy timer.
  void _startAntiEntropyTimer() {
    _antiEntropyTimer = Timer.periodic(
      config.antiEntropyInterval,
      (_) => _performAntiEntropy(),
    );
  }

  /// Start the periodic peer discovery timer.
  void _startPeerDiscoveryTimer() {
    _peerDiscoveryTimer = Timer.periodic(
      config.peerDiscoveryInterval,
      (_) => _discoverPeers(),
    );
  }

  /// Perform a single gossip cycle.
  ///
  /// This is the main gossip operation that selects peers and exchanges
  /// information with them. Uses a guard to prevent overlapping cycles.
  Future<void> _performGossipCycle() async {
    if (_gossipCycleInProgress) return;

    _gossipCycleInProgress = true;
    try {
      await gossipCycleUseCase.execute();
    } finally {
      _gossipCycleInProgress = false;
    }
  }

  /// Perform anti-entropy operations to ensure eventual consistency.
  Future<void> _performAntiEntropy() async {
    await gossipCycleUseCase.performAntiEntropy();
  }

  /// Discover new peers using the peer management service.
  Future<void> _discoverPeers() async {
    await peerManagementService.discoverPeers();
  }

  /// Set up handlers for incoming transport messages.
  Future<void> _setupIncomingMessageHandlers() async {
    _digestSub = transport.incomingDigests.listen(_handleIncomingDigest);
    _eventsSub = transport.incomingEvents.listen(_handleIncomingEvents);
  }

  /// Handle incoming digest messages from other nodes.
  Future<void> _handleIncomingDigest(IncomingDigest digest) async {
    await gossipCycleUseCase.handleIncomingDigest(digest);
  }

  /// Handle incoming event messages from other nodes.
  ///
  /// Processes the events and notifies listeners of newly received events.
  Future<void> _handleIncomingEvents(IncomingEvents events) async {
    final receivedEvents = await gossipCycleUseCase.handleIncomingEvents(
      events,
    );
    for (final event in receivedEvents) {
      _eventReceivedController.add(event);
    }
  }
}
