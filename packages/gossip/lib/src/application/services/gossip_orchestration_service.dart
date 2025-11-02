/// Service that orchestrates gossip operations and manages lifecycle.
///
/// This service coordinates gossip operations, manages timers for periodic
/// activities, and handles incoming transport messages. It acts as the
/// orchestration layer between the transport and domain logic.
library;

import 'dart:async';
import 'dart:math';

import '../../event.dart';
import '../../gossip_config.dart';
import '../../gossip_transport.dart';
import '../use_cases/handle_incoming_digest_use_case.dart';
import '../use_cases/handle_incoming_events_use_case.dart';
import '../use_cases/connected_gossip_cycle_use_case.dart';
import '../use_cases/gossip_with_connected_peer_use_case.dart';
import '../ports/connected_peer_repository.dart';
import '../../gossip_peer.dart';
import 'event_creation_service.dart';
import 'peer_management_service.dart';

/// Service that orchestrates gossip operations and manages lifecycle.
class GossipOrchestrationService {
  final GossipConfig config;
  final GossipTransport transport;
  final HandleIncomingDigestUseCase handleIncomingDigestUseCase;
  final HandleIncomingEventsUseCase handleIncomingEventsUseCase;
  final ConnectedGossipCycleUseCase? connectedGossipCycleUseCase;
  final GossipWithConnectedPeerUseCase? gossipWithConnectedPeerUseCase;
  final ConnectedPeerRepository? connectedPeerRepository;
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

  // One-off targeted exchange cooldown tracking (by address)
  final Map<String, DateTime> _lastTargetedExchange = {};
  final Duration _targetedExchangeCooldown = Duration(seconds: 2);

  GossipOrchestrationService({
    required this.config,
    required this.transport,
    required this.handleIncomingDigestUseCase,
    required this.handleIncomingEventsUseCase,
    this.connectedGossipCycleUseCase,
    this.gossipWithConnectedPeerUseCase,
    this.connectedPeerRepository,
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
    await transport.dispose();
    await _eventReceivedController.close();
  }

  /// Start gossip operations and periodic activities.
  Future<void> startGossiping() async {
    if (_isGossiping) return;

    // Ensure transport is started before scheduling timers
    await transport.onStartGossip();

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
    await transport.onStoppedGossip();

    _isGossiping = false;
  }

  /// Start the periodic gossip timer.
  void _startGossipTimer() {
    final interval = config.gossipInterval;

    // Add jitter to avoid synchronized cycles across nodes (hot spots).
    // Jitter up to 20% of the interval.
    final jitterMs = (interval.inMilliseconds * 0.2).toInt();
    final initialDelay = jitterMs > 0
        ? Duration(milliseconds: Random().nextInt(jitterMs))
        : Duration.zero;

    // Start with a one-shot timer for the initial jitter, then switch to periodic.
    _gossipTimer = Timer(initialDelay, () {
      _performGossipCycle();
      _gossipTimer = Timer.periodic(interval, (_) => _performGossipCycle());
    });
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
      if (connectedGossipCycleUseCase != null) {
        await connectedGossipCycleUseCase!.execute();
      }
    } finally {
      _gossipCycleInProgress = false;
    }
  }

  /// Perform anti-entropy operations to ensure eventual consistency.
  Future<void> _performAntiEntropy() async {
    if (connectedGossipCycleUseCase != null) {
      await connectedGossipCycleUseCase!.execute();
    }
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
    // Update peer repository immediately with latest transport info to improve liveness after partitions heal.
    try {
      await peerManagementService.updatePeerFromTransport(
        digest.fromTransportPeer,
      );
      // Link transport address -> real node id when digest identity is learned.
      await peerManagementService.promote(
        digest.fromTransportPeer.address,
        digest.digest.senderId,
      );
      // Schedule a one-off targeted exchange back to this address (cooldown-guarded)
      _maybeScheduleTargetedExchangeByAddress(digest.fromTransportPeer.address);
    } catch (_) {
      // Ignore repository update failures; proceed with digest handling.
    }

    final response = await handleIncomingDigestUseCase.createResponse(
      incoming: digest.digest,
      now: DateTime.now(),
    );
    await digest.respond(response);
  }

  /// Handle incoming event messages from other nodes.
  ///
  /// Processes the events and notifies listeners of newly received events.
  Future<void> _handleIncomingEvents(IncomingEvents events) async {
    // Update peer repository immediately with latest transport info to improve liveness after partitions heal.
    try {
      await peerManagementService.updatePeerFromTransport(
        events.fromTransportPeer,
      );
      // Link transport address -> real node id when message identity is learned.
      await peerManagementService.promote(
        events.fromTransportPeer.address,
        events.message.senderId,
      );
      // Schedule a one-off targeted exchange back to this address (cooldown-guarded)
      _maybeScheduleTargetedExchangeByAddress(events.fromTransportPeer.address);
    } catch (_) {
      // Ignore repository update failures; proceed with event handling.
    }

    final fromPeer = GossipPeer(
      id: events.message.senderId,
      address: events.fromTransportPeer.address,
      metadata: events.fromTransportPeer.metadata,
      lastContactTime: events.fromTransportPeer.connectedAt,
      isActive: events.fromTransportPeer.isActive,
    );
    final receivedEvents = await handleIncomingEventsUseCase.execute(
      message: events.message,
      fromPeer: fromPeer,
      now: DateTime.now(),
    );
    for (final event in receivedEvents) {
      _eventReceivedController.add(event);
    }
  }

  // Schedules a one-off targeted exchange to the specified address
  // if cooldown has elapsed and no cycle is currently in progress.
  void _maybeScheduleTargetedExchangeByAddress(TransportPeerAddress address) {
    final now = DateTime.now();
    final key = address.value;
    final last = _lastTargetedExchange[key];
    if (last != null && now.difference(last) < _targetedExchangeCooldown) {
      return;
    }
    _lastTargetedExchange[key] = now;

    if (_gossipCycleInProgress) {
      return;
    }

    // If connected-peer plumbing is not available, skip.
    if (connectedPeerRepository == null ||
        gossipWithConnectedPeerUseCase == null) {
      return;
    }

    // Fire-and-forget targeted exchange using the connected peer resolved by address.
    unawaited(_exchangeWithAddress(address));
  }

  Future<void> _exchangeWithAddress(TransportPeerAddress address) async {
    try {
      final peer = await connectedPeerRepository!.getByAddress(address);
      if (peer == null) return;
      await gossipWithConnectedPeerUseCase!.execute(
        peer: peer,
        now: DateTime.now(),
      );
    } catch (_) {
      // Best-effort; do not propagate errors from targeted exchange
    }
  }
}
