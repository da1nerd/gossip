/// Simplified GossipNode for basic event broadcasting.
///
/// This provides a much simpler alternative to the full GossipNode for use cases
/// where you just need basic event synchronization without the complexity of
/// the full gossip protocol.
library;

import 'dart:async';

import 'event.dart';
import 'event_store.dart';
import 'simple_transport.dart';
import 'vector_clock.dart';

/// Simplified GossipNode for basic event broadcasting.
///
/// This is a streamlined version of the full GossipNode that focuses on
/// simple event creation and synchronization without the complex 3-phase
/// gossip protocol. It's perfect for use cases like chat apps, real-time
/// collaboration, or simple event streaming.
class SimpleGossipNode {
  final String nodeId;
  final SimpleGossipTransport transport;
  final EventStore eventStore;

  final VectorClock _vectorClock = VectorClock();

  final StreamController<Event> _eventReceivedController =
      StreamController.broadcast();
  final StreamController<Event> _eventCreatedController =
      StreamController.broadcast();
  final StreamController<String> _peerJoinedController =
      StreamController.broadcast();
  final StreamController<String> _peerLeftController =
      StreamController.broadcast();

  bool _started = false;
  Set<String> _lastKnownPeers = {};
  Timer? _peerMonitorTimer;

  SimpleGossipNode({
    required this.nodeId,
    required this.transport,
    required this.eventStore,
  }) {
    // Listen to incoming events
    transport.incomingEvents.listen((event) {
      if (event.nodeId != nodeId) {
        _handleIncomingEvent(event);
      }
    });
  }

  /// Start the gossip node
  Future<void> start() async {
    if (_started) return;

    await transport.initialize();
    _started = true;

    // Start monitoring peer changes
    _peerMonitorTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _checkPeerChanges();
    });
  }

  /// Stop the gossip node
  Future<void> stop() async {
    if (!_started) return;

    _peerMonitorTimer?.cancel();
    await transport.dispose();
    _started = false;
  }

  /// Create and broadcast an event
  Future<Event> createEvent(Map<String, dynamic> payload) async {
    if (!_started) throw StateError('Node not started');

    // Increment our vector clock
    _vectorClock.increment(nodeId);

    final event = Event(
      id: '${nodeId}_${_vectorClock.getTimestampFor(nodeId)}',
      nodeId: nodeId,
      timestamp: _vectorClock.getTimestampFor(nodeId),
      creationTimestamp: DateTime.now().millisecondsSinceEpoch,
      payload: Map<String, dynamic>.from(payload),
    );

    // Save locally
    await eventStore.saveEvent(event);

    // Broadcast to peers
    await transport.broadcastEvent(event);

    // Notify listeners
    _eventCreatedController.add(event);

    return event;
  }

  Future<void> _handleIncomingEvent(Event event) async {
    // Check if we already have this event
    final existing = await eventStore.getEvent(event.id);
    if (existing != null) return; // Already have it

    // Save the event
    await eventStore.saveEvent(event);

    // Update our vector clock
    _vectorClock.merge(
      VectorClock()..setTimestampFor(event.nodeId, event.timestamp),
    );

    // Notify listeners
    _eventReceivedController.add(event);
  }

  void _checkPeerChanges() {
    if (!_started) return;

    final currentPeers = transport.connectedPeerIds.toSet();

    // Find newly joined peers
    final newPeers = currentPeers.difference(_lastKnownPeers);
    for (final peerId in newPeers) {
      _peerJoinedController.add(peerId);
    }

    // Find peers that left
    final leftPeers = _lastKnownPeers.difference(currentPeers);
    for (final peerId in leftPeers) {
      _peerLeftController.add(peerId);
    }

    _lastKnownPeers = currentPeers;
  }

  /// Stream of events created by this node
  Stream<Event> get onEventCreated => _eventCreatedController.stream;

  /// Stream of events received from other nodes
  Stream<Event> get onEventReceived => _eventReceivedController.stream;

  /// Stream of peer join events
  Stream<String> get onPeerJoined => _peerJoinedController.stream;

  /// Stream of peer leave events
  Stream<String> get onPeerLeft => _peerLeftController.stream;

  /// Get list of connected peers
  List<String> get connectedPeers => transport.connectedPeerIds;

  /// Get the current vector clock
  VectorClock get vectorClock => _vectorClock.copy();

  /// Check if the node is started
  bool get isStarted => _started;

  /// Dispose resources
  Future<void> dispose() async {
    await stop();
    await _eventReceivedController.close();
    await _eventCreatedController.close();
    await _peerJoinedController.close();
    await _peerLeftController.close();
  }
}
