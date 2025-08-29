// main.dart - Entry point and example usage
import 'dart:async';
import 'dart:math';

// --- Core Data Structures ---

/// Represents a generic event in the system.
///
/// Each event has a unique ID, the ID of the node that created it,
/// a logical timestamp for causality, a creation timestamp for total ordering,
/// and a payload.
class Event {
  final String id;
  final String nodeId;
  final int timestamp; // Logical timestamp from Vector Clock
  final int creationTimestamp; // Wall-clock time for reporting
  final Map<String, dynamic> payload;

  Event({
    required this.id,
    required this.nodeId,
    required this.timestamp,
    required this.creationTimestamp,
    required this.payload,
  });

  /// Creates an Event from a JSON map.
  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'],
      nodeId: json['nodeId'],
      timestamp: json['timestamp'],
      creationTimestamp: json['creationTimestamp'],
      payload: Map<String, dynamic>.from(json['payload']),
    );
  }

  /// Converts the Event to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nodeId': nodeId,
      'timestamp': timestamp,
      'creationTimestamp': creationTimestamp,
      'payload': payload,
    };
  }

  @override
  String toString() {
    return 'Event(id: $id, nodeId: $nodeId, timestamp: $timestamp, creationTimestamp: $creationTimestamp, payload: $payload)';
  }
}

/// A Vector Clock to track the logical time of events across nodes.
///
/// This is crucial for determining the causality of events and ensuring
/// that events are not missed during synchronization.
class VectorClock {
  final Map<String, int> _clocks = {};

  /// Gets the current timestamp for a given node.
  int getTimestampFor(String nodeId) {
    return _clocks[nodeId] ?? 0;
  }

  /// Increments the timestamp for a given node.
  void increment(String nodeId) {
    _clocks[nodeId] = getTimestampFor(nodeId) + 1;
  }

  /// Merges this vector clock with another, taking the maximum of each entry.
  void merge(VectorClock other) {
    for (var entry in other._clocks.entries) {
      final localTimestamp = getTimestampFor(entry.key);
      if (entry.value > localTimestamp) {
        _clocks[entry.key] = entry.value;
      }
    }
  }

  /// Returns a summary of the vector clock, often used in the gossip digest.
  Map<String, int> get summary => Map.unmodifiable(_clocks);

  @override
  String toString() {
    return 'VectorClock($_clocks)';
  }
}

// --- Event Storage ---

/// Abstract interface for an event store.
///
/// This allows for different storage backends (e.g., in-memory, database).
abstract class EventStore {
  Future<void> saveEvent(Event event);
  Future<List<Event>> getEventsSince(String nodeId, int timestamp);
  Future<List<Event>> getAllEvents();
}

/// An in-memory implementation of the EventStore for demonstration.
class InMemoryEventStore implements EventStore {
  final List<Event> _events = [];

  @override
  Future<void> saveEvent(Event event) async {
    // Avoid duplicates
    if (!_events.any((e) => e.id == event.id)) {
      _events.add(event);
      // Sorting by logical timestamp is important for the protocol's internal logic
      _events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }
  }

  @override
  Future<List<Event>> getEventsSince(String nodeId, int timestamp) async {
    return _events
        .where((e) => e.nodeId == nodeId && e.timestamp > timestamp)
        .toList();
  }

  @override
  Future<List<Event>> getAllEvents() async {
    return List.unmodifiable(_events);
  }
}

// --- Node and Gossip Protocol ---

/// Represents a node in the gossip network.
class Node {
  final String id;
  final EventStore _eventStore;
  final VectorClock _vectorClock = VectorClock();
  final List<Node> _peers = [];
  final Random _random = Random();

  Node(this.id, {EventStore? eventStore})
    : _eventStore = eventStore ?? InMemoryEventStore();

  /// Adds a peer to this node's list of known peers.
  void addPeer(Node peer) {
    if (peer.id != id && !_peers.contains(peer)) {
      _peers.add(peer);
    }
  }

  /// Creates a new event and saves it to the local event store.
  Future<void> createEvent(Map<String, dynamic> payload) async {
    _vectorClock.increment(id);
    final event = Event(
      id: '${id}_${_vectorClock.getTimestampFor(id)}',
      nodeId: id,
      timestamp: _vectorClock.getTimestampFor(id),
      creationTimestamp:
          DateTime.now().millisecondsSinceEpoch, // Set wall-clock time
      payload: payload,
    );
    await _eventStore.saveEvent(event);
    print('$id created event: ${event.id}');
  }

  /// Initiates a gossip cycle with a random peer.
  Future<void> gossip() async {
    if (_peers.isEmpty) return;

    final peer = _peers[_random.nextInt(_peers.length)];
    print('$id gossiping with ${peer.id}');
    await _initiateGossip(peer);
  }

  /// Step 1: Send a digest of our knowledge (vector clock) to a peer.
  Future<void> _initiateGossip(Node peer) async {
    final digest = _vectorClock.summary;
    await peer.onReceiveGossipDigest(this, digest);
  }

  /// Step 2: Receive a digest, compare it with our knowledge, and request missing events.
  Future<void> onReceiveGossipDigest(
    Node fromNode,
    Map<String, int> digest,
  ) async {
    final eventsToSend = <Event>[];
    final theirClock = VectorClock();
    digest.forEach((nodeId, timestamp) {
      theirClock._clocks[nodeId] = timestamp;
    });

    // Find events the other node doesn't have
    for (var entry in _vectorClock.summary.entries) {
      if (entry.value > theirClock.getTimestampFor(entry.key)) {
        final missingEvents = await _eventStore.getEventsSince(
          entry.key,
          theirClock.getTimestampFor(entry.key),
        );
        eventsToSend.addAll(missingEvents);
      }
    }

    // Prepare a request for events we are missing
    final myMissingEventsRequest = <String, int>{};
    for (var entry in digest.entries) {
      if (entry.value > _vectorClock.getTimestampFor(entry.key)) {
        myMissingEventsRequest[entry.key] = _vectorClock.getTimestampFor(
          entry.key,
        );
      }
    }

    await fromNode.onReceiveEventRequest(
      this,
      eventsToSend,
      myMissingEventsRequest,
    );
  }

  /// Step 3: Receive a request for events, send them back, and process their request.
  Future<void> onReceiveEventRequest(
    Node fromNode,
    List<Event> events,
    Map<String, int> requestForMissing,
  ) async {
    // Save the events they sent us
    for (final event in events) {
      await _eventStore.saveEvent(event);
      _vectorClock.merge(
        VectorClock().._clocks[event.nodeId] = event.timestamp,
      );
    }
    if (events.isNotEmpty) {
      print('$id received ${events.length} events from ${fromNode.id}');
    }

    // Fulfill their request for events they are missing
    final eventsToSendBack = <Event>[];
    for (var entry in requestForMissing.entries) {
      final missing = await _eventStore.getEventsSince(entry.key, entry.value);
      eventsToSendBack.addAll(missing);
    }

    if (eventsToSendBack.isNotEmpty) {
      await fromNode.onReceiveFinalEvents(this, eventsToSendBack);
    }
  }

  /// Step 4: Receive the final batch of events and merge them.
  Future<void> onReceiveFinalEvents(Node fromNode, List<Event> events) async {
    for (final event in events) {
      await _eventStore.saveEvent(event);
      _vectorClock.merge(
        VectorClock().._clocks[event.nodeId] = event.timestamp,
      );
    }
    print('$id received final ${events.length} events from ${fromNode.id}');
    print('$id state after gossip: ${_vectorClock}');
  }

  /// Prints all events in the node's store.
  Future<void> printEvents() async {
    final events = await _eventStore.getAllEvents();
    print('--- Events for Node $id ---');
    // For reporting, you could sort by creationTimestamp here
    final sortedForReporting = List<Event>.from(events)
      ..sort((a, b) => a.creationTimestamp.compareTo(b.creationTimestamp));
    sortedForReporting.forEach(print);
    print('--------------------------');
  }
}

// --- Main Simulation ---

void main() async {
  // 1. Create nodes
  final nodeA = Node('A');
  final nodeB = Node('B');
  final nodeC = Node('C');

  // 2. Establish peer connections
  nodeA.addPeer(nodeB);
  nodeA.addPeer(nodeC);
  nodeB.addPeer(nodeA);
  nodeB.addPeer(nodeC);
  nodeC.addPeer(nodeA);
  nodeC.addPeer(nodeB);

  // 3. Nodes generate some initial events
  await nodeA.createEvent({'data': 'A1'});
  await nodeB.createEvent({'data': 'B1'});
  await Future.delayed(Duration(milliseconds: 10));
  await nodeA.createEvent({'data': 'A2'});
  await nodeC.createEvent({'data': 'C1'});

  print('\n--- Initial State ---');
  await nodeA.printEvents();
  await nodeB.printEvents();
  await nodeC.printEvents();

  // 4. Start gossiping to sync events
  print('\n--- Gossiping ---');
  final random = Random();
  for (int i = 0; i < 5; i++) {
    final nodes = [nodeA, nodeB, nodeC];
    final gossipingNode = nodes[random.nextInt(nodes.length)];
    await gossipingNode.gossip();
    await Future.delayed(Duration(milliseconds: 50));
  }

  // 5. Create more events after some syncing
  await nodeB.createEvent({'data': 'B2'});
  await nodeC.createEvent({'data': 'C2'});

  // 6. More gossiping
  print('\n--- More Gossiping ---');
  for (int i = 0; i < 5; i++) {
    final nodes = [nodeA, nodeB, nodeC];
    final gossipingNode = nodes[random.nextInt(nodes.length)];
    await gossipingNode.gossip();
    await Future.delayed(Duration(milliseconds: 50));
  }

  print('\n--- Final State ---');
  await nodeA.printEvents();
  await nodeB.printEvents();
  await nodeC.printEvents();
}
