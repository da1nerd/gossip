/// Clean architecture implementation of gossip protocol.
///
/// Provides the same core functionality as GossipNode but with better
/// separation of concerns and testability. Applications can migrate to this
/// when ready while GossipNode remains available for backward compatibility.
library;

import 'dart:async';

import 'package:gossip/src/event.dart';
import 'package:gossip/src/event_store.dart';
import 'package:gossip/src/exceptions.dart';
import 'package:gossip/src/gossip_config.dart';
import 'package:gossip/src/gossip_peer.dart';
import 'package:gossip/src/transport.dart';
import 'package:gossip/src/vector_clock.dart';
import 'package:gossip/src/vector_clock_store.dart';

import 'package:gossip/src/application/services/event_creation_service.dart';
import 'package:gossip/src/application/services/gossip_orchestration_service.dart';
import 'package:gossip/src/application/services/peer_management_service.dart';
import 'package:gossip/src/application/services/vector_clock_service.dart';
import 'package:gossip/src/application/use_cases/gossip_cycle_use_case.dart';
import 'package:gossip/src/application/use_cases/gossip_with_peer_use_case.dart';
import 'package:gossip/src/application/use_cases/handle_incoming_digest_use_case.dart';
import 'package:gossip/src/application/use_cases/handle_incoming_events_use_case.dart';
import 'package:gossip/src/application/use_cases/connected_gossip_cycle_use_case.dart';
import 'package:gossip/src/application/use_cases/gossip_with_connected_peer_use_case.dart';
import 'package:gossip/src/application/ports/peer_repository.dart';
import 'package:gossip/src/application/ports/connected_peer_repository.dart';
import 'package:gossip/src/domain/services/peer_selection_service.dart';
import 'package:gossip/src/domain/services/connected_peer_selection_service.dart';
import 'package:gossip/src/infrastructure/repositories/in_memory_peer_repository.dart';
import 'package:gossip/src/infrastructure/repositories/in_memory_connected_peer_repository.dart';
import 'package:gossip/src/infrastructure/repositories/in_memory_identified_node_repository.dart';

/// Clean architecture implementation of gossip protocol.
///
/// Provides the same core functionality as GossipNode but with better
/// separation of concerns and testability.
class ModularGossipNode {
  final GossipConfig config;
  final EventStore eventStore;
  final GossipTransport transport;
  final VectorClockStore? vectorClockStore;

  // Clean architecture components
  late final PeerRepository _peerRepository;
  late final PeerSelectionService _peerSelectionService;
  late final GossipCycleUseCase _gossipCycleUseCase;
  late final PeerManagementService _peerManagementService;
  late final EventCreationService _eventCreationService;
  late final VectorClockService _vectorClockService;
  late final GossipOrchestrationService _orchestrationService;

  // Public streams - simplified interface
  late final Stream<Event> onEvent;
  late final Stream<ReceivedEvent> onEventReceived;

  bool _isInitialized = false;

  /// Creates a new modular gossip node.
  ModularGossipNode({
    required this.config,
    required this.eventStore,
    required this.transport,
    this.vectorClockStore,
  });

  /// Alternative constructor for dependency injection (for testing).
  ModularGossipNode.withDependencies({
    required this.config,
    required this.eventStore,
    required this.transport,
    this.vectorClockStore,
    PeerRepository? peerRepository,
    PeerSelectionService? peerSelectionService,
    VectorClockService? vectorClockService,
  }) {
    if (peerRepository != null) _peerRepository = peerRepository;
    if (peerSelectionService != null)
      _peerSelectionService = peerSelectionService;
    if (vectorClockService != null) _vectorClockService = vectorClockService;
  }

  /// Initialize the node and wire up all dependencies.
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Wire up clean architecture components
    _peerRepository = InMemoryPeerRepository();
    _peerSelectionService = PeerSelectionService();

    _vectorClockService = VectorClockService(
      nodeId: config.nodeId,
      store: vectorClockStore,
    );

    _eventCreationService = EventCreationService(
      eventStore: eventStore,
      vectorClockService: _vectorClockService,
      nodeId: config.nodeId,
    );

    // New: Connected peer repository (transport-address keyed, no temp IDs)
    final ConnectedPeerRepository connectedPeerRepository =
        InMemoryConnectedPeerRepository();
    // New: Identified node repository (GossipNodeID-keyed, tracks identity and addresses)
    final identifiedNodeRepository = InMemoryIdentifiedNodeRepository();

    _peerManagementService = PeerManagementService(
      peerRepository: _peerRepository,
      transport: transport,
      connectedPeerRepository: connectedPeerRepository,
      identifiedNodeRepository: identifiedNodeRepository,
    );

    // Wire application use cases
    final handleIncomingDigestUseCase = HandleIncomingDigestUseCase(
      eventStore: eventStore,
      vectorClockService: _vectorClockService,
      maxEventsPerMessage: config.maxEventsPerMessage,
    );

    final handleIncomingEventsUseCase = HandleIncomingEventsUseCase(
      eventStore: eventStore,
      vectorClockService: _vectorClockService,
    );

    final gossipWithPeerUseCase = GossipWithPeerUseCase(
      transport: transport,
      eventStore: eventStore,
      vectorClockService: _vectorClockService,
      maxEventsPerMessage: config.maxEventsPerMessage,
      operationTimeout: config.gossipTimeout,
    );

    _gossipCycleUseCase = GossipCycleUseCase(
      peerRepository: _peerRepository,
      peerSelectionService: _peerSelectionService,
      config: config,
      gossipWithPeerUseCase: gossipWithPeerUseCase,
      handleIncomingDigestUseCase: handleIncomingDigestUseCase,
      handleIncomingEventsUseCase: handleIncomingEventsUseCase,
    );

    // New connected-peer selection/cycle (non-breaking: provided as optional to orchestration)
    final connectedPeerSelectionService = ConnectedPeerSelectionService();
    final gossipWithConnectedPeerUseCase = GossipWithConnectedPeerUseCase(
      transport: transport,
      eventStore: eventStore,
      vectorClockService: _vectorClockService,
      connectedPeerRepository: connectedPeerRepository,
      maxEventsPerMessage: config.maxEventsPerMessage,
      operationTimeout: config.gossipTimeout,
    );
    final connectedGossipCycleUseCase = ConnectedGossipCycleUseCase(
      connectedPeerRepository: connectedPeerRepository,
      connectedPeerSelectionService: connectedPeerSelectionService,
      gossipWithConnectedPeerUseCase: gossipWithConnectedPeerUseCase,
      config: config,
    );
    _orchestrationService = GossipOrchestrationService(
      config: config,
      transport: transport,
      gossipCycleUseCase: _gossipCycleUseCase,
      connectedGossipCycleUseCase: connectedGossipCycleUseCase,
      gossipWithConnectedPeerUseCase: gossipWithConnectedPeerUseCase,
      connectedPeerRepository: connectedPeerRepository,
      eventCreationService: _eventCreationService,
      peerManagementService: _peerManagementService,
    );

    // Wire up event streams
    onEvent = _eventCreationService.eventCreated;
    onEventReceived = _orchestrationService.eventReceived;

    // Initialize services
    await _vectorClockService.initialize();
    await _orchestrationService.initialize();

    _isInitialized = true;
  }

  /// Shutdown and cleanup all resources.
  Future<void> shutdown() async {
    if (!_isInitialized) return;

    await _orchestrationService.shutdown();
    _eventCreationService.dispose();

    if (_peerRepository is InMemoryPeerRepository) {
      await (_peerRepository as InMemoryPeerRepository).dispose();
    }

    _isInitialized = false;
  }

  /// Start gossiping with other nodes.
  Future<void> startGossiping() async {
    _checkInitialized();
    await _orchestrationService.startGossiping();
  }

  /// Stop gossiping with other nodes.
  Future<void> stopGossiping() async {
    _checkInitialized();
    await _orchestrationService.stopGossiping();
  }

  /// Create a new event and add it to the gossip network.
  Future<Event> createEvent(Map<String, dynamic> data) async {
    _checkInitialized();
    return await _eventCreationService.createEvent(data);
  }

  /// Get current list of peers (converted to external GossipPeer format).
  Future<List<GossipPeer>> get peers async {
    _checkInitialized();
    final internalPeers = await _peerRepository.getAllPeers();
    return internalPeers.map((p) => p.toGossipPeer()).toList();
  }

  /// Get current vector clock.
  VectorClock get vectorClock {
    _checkInitialized();
    return _vectorClockService.currentClock;
  }

  /// Check if the node has been initialized.
  bool get isInitialized => _isInitialized;

  /// Check if gossip operations are active.
  bool get isGossiping {
    _checkInitialized();
    return _orchestrationService.isGossiping;
  }

  void _checkInitialized() {
    if (!_isInitialized) {
      throw NodeNotInitializedException('Node must be initialized first');
    }
  }
}
