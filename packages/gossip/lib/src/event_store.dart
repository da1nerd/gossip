/// Abstract interface for event storage in the gossip protocol.
///
/// This module defines the storage interface that the gossip protocol uses
/// to persist and retrieve events. Different implementations can provide
/// various storage backends (in-memory, database, file system, etc.).
library;

import 'event.dart';
import 'exceptions.dart';
import 'transport.dart';

/// Abstract interface for an event store.
///
/// This allows for different storage backends and provides a clean
/// separation between the gossip protocol logic and the persistence layer.
/// Implementations should handle concurrent access safely and provide
/// efficient querying capabilities.
abstract class EventStore {
  /// Saves an event to the store.
  ///
  /// If an event with the same ID already exists, implementations may either:
  /// - Ignore the duplicate (recommended for idempotency)
  /// - Update the existing event
  /// - Throw a [DuplicateEventException]
  ///
  /// The behavior should be documented by the implementation.
  ///
  /// Throws [EventStoreException] if the event cannot be saved.
  Future<void> saveEvent(Event event);

  /// Saves multiple events to the store in a batch operation.
  ///
  /// This may be more efficient than calling [saveEvent] multiple times.
  /// All events should be saved atomically if possible.
  ///
  /// Throws [EventStoreException] if any events cannot be saved.
  Future<void> saveEvents(List<Event> events);

  /// Retrieves events from a specific node that have timestamps greater than the given value.
  ///
  /// This is used during gossip synchronization to find events that a peer
  /// doesn't have yet. Events should be returned in timestamp order (ascending).
  ///
  /// Parameters:
  /// - [nodeId]: The ID of the node whose events to retrieve
  /// - [afterTimestamp]: Only return events with timestamps > this value
  /// - [limit]: Optional maximum number of events to return
  ///
  /// Returns an empty list if no events match the criteria.
  ///
  /// Throws [EventStoreException] if the query cannot be performed.
  Future<List<Event>> getEventsSince(
    GossipPeerID nodeId,
    int afterTimestamp, {
    int? limit,
  });

  /// Retrieves all events from the store.
  ///
  /// This method should be used carefully as it may return a large number
  /// of events. Consider using [getEventsInRange] or pagination for
  /// production use cases.
  ///
  /// Events are typically returned in timestamp order, but this may vary
  /// by implementation.
  ///
  /// Throws [EventStoreException] if the events cannot be retrieved.
  Future<List<Event>> getAllEvents();

  /// Retrieves events within a specific timestamp range.
  ///
  /// This is useful for implementing anti-entropy mechanisms or
  /// historical event queries.
  ///
  /// Parameters:
  /// - [startTimestamp]: Inclusive start of the range
  /// - [endTimestamp]: Inclusive end of the range
  /// - [nodeId]: Optional filter to only include events from this node
  /// - [limit]: Optional maximum number of events to return
  ///
  /// Throws [EventStoreException] if the query cannot be performed.
  Future<List<Event>> getEventsInRange(
    int startTimestamp,
    int endTimestamp, {
    GossipPeerID? nodeId,
    int? limit,
  });

  /// Retrieves a specific event by its ID.
  ///
  /// Returns null if no event with the given ID exists.
  ///
  /// Throws [EventStoreException] if the query cannot be performed.
  Future<Event?> getEvent(String eventId);

  /// Checks if an event with the given ID exists in the store.
  ///
  /// This may be more efficient than calling [getEvent] when you only
  /// need to check existence.
  ///
  /// Throws [EventStoreException] if the check cannot be performed.
  Future<bool> hasEvent(String eventId);

  /// Returns the total number of events in the store.
  ///
  /// This may be an expensive operation for large stores.
  ///
  /// Throws [EventStoreException] if the count cannot be determined.
  Future<int> getEventCount();

  /// Returns the number of events for a specific node.
  ///
  /// Throws [EventStoreException] if the count cannot be determined.
  Future<int> getEventCountForNode(GossipPeerID nodeId);

  /// Gets the latest timestamp for a specific node.
  ///
  /// Returns 0 if no events exist for the node.
  ///
  /// Throws [EventStoreException] if the query cannot be performed.
  Future<int> getLatestTimestampForNode(GossipPeerID nodeId);

  /// Gets the latest timestamps for all nodes that have events in the store.
  ///
  /// Returns a map where keys are node IDs and values are their latest timestamps.
  ///
  /// Throws [EventStoreException] if the query cannot be performed.
  Future<Map<GossipPeerID, int>> getLatestTimestampsForAllNodes();

  /// Removes events older than the specified timestamp.
  ///
  /// This is useful for implementing event retention policies and
  /// preventing unbounded growth of the event store.
  ///
  /// Returns the number of events that were removed.
  ///
  /// Throws [EventStoreException] if the cleanup cannot be performed.
  Future<int> removeEventsOlderThan(int timestamp);

  /// Removes all events for a specific node.
  ///
  /// This might be used when a node permanently leaves the system.
  ///
  /// Returns the number of events that were removed.
  ///
  /// Throws [EventStoreException] if the removal cannot be performed.
  Future<int> removeEventsForNode(GossipPeerID nodeId);

  /// Removes all events from the store.
  ///
  /// This is primarily useful for testing or system reset scenarios.
  /// Use with caution in production environments.
  ///
  /// Throws [EventStoreException] if the clear operation cannot be performed.
  Future<void> clear();

  /// Closes the event store and releases any resources.
  ///
  /// After calling this method, the event store should not be used.
  /// Implementations should ensure that any pending operations are
  /// completed or cancelled gracefully.
  Future<void> close();

  /// Returns statistics about the event store.
  ///
  /// This can be useful for monitoring and debugging purposes.
  /// The exact statistics provided may vary by implementation.
  Future<EventStoreStats> getStats();
}

/// Statistics about an event store's current state.
///
/// This class provides information about the event store that can be
/// useful for monitoring, debugging, and performance optimization.
class EventStoreStats {
  /// Total number of events in the store.
  final int totalEvents;

  /// Number of unique nodes that have events in the store.
  final int uniqueNodes;

  /// Timestamp of the oldest event in the store.
  final int? oldestEventTimestamp;

  /// Timestamp of the newest event in the store.
  final int? newestEventTimestamp;

  /// Approximate size of the store in bytes (if available).
  final int? sizeInBytes;

  /// Additional implementation-specific statistics.
  final Map<String, dynamic> additionalStats;

  const EventStoreStats({
    required this.totalEvents,
    required this.uniqueNodes,
    this.oldestEventTimestamp,
    this.newestEventTimestamp,
    this.sizeInBytes,
    this.additionalStats = const {},
  });

  @override
  String toString() {
    final buffer = StringBuffer('EventStoreStats(');
    buffer.write('totalEvents: $totalEvents, ');
    buffer.write('uniqueNodes: $uniqueNodes');

    if (oldestEventTimestamp != null) {
      buffer.write(', oldestEventTimestamp: $oldestEventTimestamp');
    }
    if (newestEventTimestamp != null) {
      buffer.write(', newestEventTimestamp: $newestEventTimestamp');
    }
    if (sizeInBytes != null) {
      buffer.write(', sizeInBytes: $sizeInBytes');
    }
    if (additionalStats.isNotEmpty) {
      buffer.write(', additionalStats: $additionalStats');
    }

    buffer.write(')');
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EventStoreStats) return false;

    return totalEvents == other.totalEvents &&
        uniqueNodes == other.uniqueNodes &&
        oldestEventTimestamp == other.oldestEventTimestamp &&
        newestEventTimestamp == other.newestEventTimestamp &&
        sizeInBytes == other.sizeInBytes &&
        _mapEquals(additionalStats, other.additionalStats);
  }

  @override
  int get hashCode {
    return Object.hash(
      totalEvents,
      uniqueNodes,
      oldestEventTimestamp,
      newestEventTimestamp,
      sizeInBytes,
      Object.hashAll(
        additionalStats.entries.map((e) => Object.hash(e.key, e.value)),
      ),
    );
  }

  static bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }
}
