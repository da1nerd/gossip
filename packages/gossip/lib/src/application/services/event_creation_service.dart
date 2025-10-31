/// Service responsible for creating and managing events.
///
/// This service handles the creation of new events and coordinates with
/// the vector clock service to maintain causality tracking.
library;

import 'dart:async';
import 'package:uuid/uuid.dart';

import '../../event.dart';
import '../../event_store.dart';
import '../../gossip_node_id.dart';
import 'vector_clock_service.dart';

/// Service responsible for creating and managing events.
class EventCreationService {
  final EventStore eventStore;
  final VectorClockService vectorClockService;
  final String nodeId;

  final StreamController<Event> _eventCreatedController =
      StreamController<Event>.broadcast();

  EventCreationService({
    required this.eventStore,
    required this.vectorClockService,
    required this.nodeId,
  });

  /// Stream of events that have been created by this node.
  Stream<Event> get eventCreated => _eventCreatedController.stream;

  /// Create a new event and add it to the event store.
  ///
  /// This method:
  /// 1. Creates a new event with the current vector clock
  /// 2. Increments the vector clock
  /// 3. Stores the event
  /// 4. Saves the vector clock state
  /// 5. Notifies listeners
  Future<Event> createEvent(Map<String, dynamic> data) async {
    // Increment our vector clock to get a unique logical timestamp
    vectorClockService.increment();
    final vectorClock = vectorClockService.currentClock;
    final timestamp = vectorClock.getTimestampFor(nodeId);

    // Generate unique event ID
    final id = const Uuid().v4();

    final event = Event(
      id: id,
      nodeId: GossipNodeID(nodeId),
      timestamp: timestamp,
      creationTimestamp: DateTime.now().millisecondsSinceEpoch,
      payload: Map<String, dynamic>.from(data),
    );

    await eventStore.saveEvent(event);
    await vectorClockService.save();

    _eventCreatedController.add(event);
    return event;
  }

  /// Dispose of resources.
  void dispose() {
    _eventCreatedController.close();
  }
}
