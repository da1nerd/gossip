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

import 'package:gossip/src/gossip_transport.dart';
import 'package:gossip/src/vector_clock.dart';
import 'package:gossip/src/vector_clock_store.dart';

import 'package:gossip/src/application/services/event_creation_service.dart';
import 'package:gossip/src/application/services/gossip_orchestration_service.dart';
import 'package:gossip/src/application/services/peer_management_service.dart';
import 'package:gossip/src/application/services/vector_clock_service.dart';

import 'package:gossip/src/application/use_cases/handle_incoming_digest_use_case.dart';
import 'package:gossip/src/application/use_cases/handle_incoming_events_use_case.dart';
import 'package:gossip/src/application/use_cases/connected_gossip_cycle_use_case.dart';
import 'package:gossip/src/application/use_cases/gossip_with_connected_peer_use_case.dart';

import 'package:gossip/src/application/ports/connected_peer_repository.dart';

import 'package:gossip/src/domain/services/connected_peer_selection_service.dart';

import 'package:gossip/src/infrastructure/repositories/in_memory_connected_peer_repository.dart';
import 'package:gossip/src/application/ports/identified_node_repository.dart';
import 'package:gossip/src/infrastructure/repositories/in_memory_identified_node_repository.dart';

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
class Gossip {
  final GossipConfig config;
  final EventStore eventStore;
  final GossipTransport transport;
  final VectorClockStore? vectorClockStore;

  // Clean architecture components
  final ConnectedPeerRepository _connectedPeerRepository;
  final IdentifiedNodeRepository _identifiedNodeRepository;

  late final PeerManagementService _peerManagementService;
  late final EventCreationService _eventCreationService;
  late final VectorClockService _vectorClockService;
  late final GossipOrchestrationService _orchestrationService;

  // Public streams
  late final Stream<Event> onEvent;
  late final Stream<ReceivedEvent> onEventReceived;
  late final Stream<GossipPeer> onPeerAdded;
  late final Stream<GossipPeer> onPeerRemoved;

  bool _isInitialized = false;

  /// Creates a new modular gossip node.
  Gossip({
    required this.config,
    required this.eventStore,
    required this.transport,
    this.vectorClockStore,
  }) : _connectedPeerRepository = InMemoryConnectedPeerRepository(),
       _identifiedNodeRepository = InMemoryIdentifiedNodeRepository();

  /// Alternative constructor for dependency injection (for testing).
  Gossip.withDependencies({
    required this.config,
    required this.eventStore,
    required this.transport,
    this.vectorClockStore,
    ConnectedPeerRepository? connectedPeerRepository,
    IdentifiedNodeRepository? identifiedNodeRepository,
    VectorClockService? vectorClockService,
  }) : _connectedPeerRepository =
           connectedPeerRepository ?? InMemoryConnectedPeerRepository(),
       _identifiedNodeRepository =
           identifiedNodeRepository ?? InMemoryIdentifiedNodeRepository() {
    if (vectorClockService != null) _vectorClockService = vectorClockService;
  }

  /// Initialize the node and wire up all dependencies.
  Future<void> initialize() async {
    if (_isInitialized) return;

    _vectorClockService = VectorClockService(
      nodeId: config.nodeId,
      store: vectorClockStore,
    );

    _eventCreationService = EventCreationService(
      eventStore: eventStore,
      vectorClockService: _vectorClockService,
      nodeId: config.nodeId,
    );

    // New: Identified node repository (GossipNodeID-keyed, tracks identity and addresses)

    _peerManagementService = PeerManagementService(
      transport: transport,
      connectedPeerRepository: _connectedPeerRepository,
      identifiedNodeRepository: _identifiedNodeRepository,
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

    // New connected-peer selection/cycle (non-breaking: provided as optional to orchestration)
    final connectedPeerSelectionService = ConnectedPeerSelectionService();
    final gossipWithConnectedPeerUseCase = GossipWithConnectedPeerUseCase(
      transport: transport,
      eventStore: eventStore,
      vectorClockService: _vectorClockService,
      connectedPeerRepository: _connectedPeerRepository,
      maxEventsPerMessage: config.maxEventsPerMessage,
      operationTimeout: config.gossipTimeout,
    );
    final connectedGossipCycleUseCase = ConnectedGossipCycleUseCase(
      connectedPeerRepository: _connectedPeerRepository,
      connectedPeerSelectionService: connectedPeerSelectionService,
      gossipWithConnectedPeerUseCase: gossipWithConnectedPeerUseCase,
      config: config,
    );
    _orchestrationService = GossipOrchestrationService(
      config: config,
      transport: transport,
      handleIncomingDigestUseCase: handleIncomingDigestUseCase,
      handleIncomingEventsUseCase: handleIncomingEventsUseCase,
      connectedGossipCycleUseCase: connectedGossipCycleUseCase,
      gossipWithConnectedPeerUseCase: gossipWithConnectedPeerUseCase,
      connectedPeerRepository: _connectedPeerRepository,
      eventCreationService: _eventCreationService,
      peerManagementService: _peerManagementService,
    );

    // Wire up event streams
    onEvent = _eventCreationService.eventCreated;
    onEventReceived = _orchestrationService.eventReceived;
    onPeerAdded = _peerManagementService.peerAdded;
    onPeerRemoved = _peerManagementService.peerRemoved;

    // Initialize services
    await _vectorClockService.initialize();
    await _peerManagementService.initialize();
    await _orchestrationService.initialize();

    _isInitialized = true;
  }

  /// Shutdown and cleanup all resources.
  Future<void> shutdown() async {
    if (!_isInitialized) return;

    await _orchestrationService.shutdown();
    _eventCreationService.dispose();
    await _peerManagementService.shutdown();

    await _connectedPeerRepository.dispose();

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
    final nodes = await _identifiedNodeRepository.getAllNodes();

    final result = <GossipPeer>[];
    for (final n in nodes) {
      if (n.addresses.isEmpty) continue;

      // Select the address with the most recent successful contact.
      var selectedAddress = n.addresses.first;
      DateTime? selectedLastContact;
      var selectedIsActive = true;

      for (final addr in n.addresses) {
        final cp = await _connectedPeerRepository.getByAddress(addr);
        final cpTime = cp?.lastContactTime;
        if (cpTime != null) {
          if (selectedLastContact == null ||
              cpTime.isAfter(selectedLastContact)) {
            selectedAddress = addr;
            selectedLastContact = cpTime;
            selectedIsActive = cp?.isActive ?? true;
          }
        }
      }

      // If no address had a last contact time, derive isActive from the first address (if present).
      if (selectedLastContact == null) {
        final cp = await _connectedPeerRepository.getByAddress(selectedAddress);
        selectedIsActive = cp?.isActive ?? true;
      }

      result.add(
        GossipPeer(
          id: n.id,
          address: selectedAddress,
          metadata: n.metadata,
          lastContactTime: selectedLastContact,
          isActive: selectedIsActive,
        ),
      );
    }
    return result;
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
