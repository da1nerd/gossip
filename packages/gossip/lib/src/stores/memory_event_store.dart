/// In-memory implementation of the EventStore interface.
///
/// This implementation stores all events in memory using Dart collections.
/// It's suitable for testing, development, and small-scale deployments where
/// persistence is not required. All operations are thread-safe using async
/// synchronization primitives.
library;

import 'dart:async';

import '../event.dart';
import '../event_store.dart';
import '../exceptions.dart';

/// An in-memory implementation of the EventStore for demonstration and testing.
///
/// This implementation stores events in memory using a List and provides
/// efficient querying through indexing by node ID. It maintains thread safety
/// through async operations and provides good performance for moderate event volumes.
///
/// **Important**: All data is lost when the application terminates as this
/// implementation does not persist data to disk.
class MemoryEventStore implements EventStore {
  final List<Event> _events = [];
  final Map<String, List<Event>> _eventsByNode = {};
  final Map<String, Event> _eventsById = {};

  bool _isClosed = false;

  /// Creates a new in-memory event store.
  MemoryEventStore();

  /// Creates an in-memory event store pre-populated with the given events.
  MemoryEventStore.withEvents(List<Event> initialEvents) {
    for (final event in initialEvents) {
      _addEventInternal(event);
    }
  }

  @override
  Future<void> saveEvent(Event event) async {
    _checkNotClosed();

    // Check for duplicates - we'll ignore them silently for idempotency
    if (_eventsById.containsKey(event.id)) {
      return;
    }

    _addEventInternal(event);
  }

  @override
  Future<void> saveEvents(List<Event> events) async {
    _checkNotClosed();

    for (final event in events) {
      // Skip duplicates silently
      if (!_eventsById.containsKey(event.id)) {
        _addEventInternal(event);
      }
    }
  }

  /// Internal method to add an event to all data structures.
  void _addEventInternal(Event event) {
    // Add to main list
    _events.add(event);

    // Add to events by ID index
    _eventsById[event.id] = event;

    // Add to events by node index
    final nodeEvents = _eventsByNode.putIfAbsent(
      event.nodeId.value,
      () => <Event>[],
    );
    nodeEvents.add(event);

    // Keep node events sorted by timestamp for efficient range queries
    nodeEvents.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Keep main events list sorted by logical timestamp
    _events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Future<List<Event>> getEventsSince(
    String nodeId,
    int afterTimestamp, {
    int? limit,
  }) async {
    _checkNotClosed();

    final nodeEvents = _eventsByNode[nodeId];
    if (nodeEvents == null) {
      return [];
    }

    final result = nodeEvents
        .where((e) => e.timestamp > afterTimestamp)
        .toList();

    if (limit != null && result.length > limit) {
      return result.take(limit).toList();
    }

    return result;
  }

  @override
  Future<List<Event>> getAllEvents() async {
    _checkNotClosed();
    return List.unmodifiable(_events);
  }

  @override
  Future<List<Event>> getEventsInRange(
    int startTimestamp,
    int endTimestamp, {
    String? nodeId,
    int? limit,
  }) async {
    _checkNotClosed();

    List<Event> sourceEvents;

    if (nodeId != null) {
      sourceEvents = _eventsByNode[nodeId] ?? [];
    } else {
      sourceEvents = _events;
    }

    final result = sourceEvents
        .where(
          (e) => e.timestamp >= startTimestamp && e.timestamp <= endTimestamp,
        )
        .toList();

    if (limit != null && result.length > limit) {
      return result.take(limit).toList();
    }

    return result;
  }

  @override
  Future<Event?> getEvent(String eventId) async {
    _checkNotClosed();
    return _eventsById[eventId];
  }

  @override
  Future<bool> hasEvent(String eventId) async {
    _checkNotClosed();
    return _eventsById.containsKey(eventId);
  }

  @override
  Future<int> getEventCount() async {
    _checkNotClosed();
    return _events.length;
  }

  @override
  Future<int> getEventCountForNode(String nodeId) async {
    _checkNotClosed();
    return _eventsByNode[nodeId]?.length ?? 0;
  }

  @override
  Future<int> getLatestTimestampForNode(String nodeId) async {
    _checkNotClosed();

    final nodeEvents = _eventsByNode[nodeId];
    if (nodeEvents == null || nodeEvents.isEmpty) {
      return 0;
    }

    // Events are kept sorted by timestamp, so the last one has the highest timestamp
    return nodeEvents.last.timestamp;
  }

  @override
  Future<Map<String, int>> getLatestTimestampsForAllNodes() async {
    _checkNotClosed();

    final result = <String, int>{};

    for (final entry in _eventsByNode.entries) {
      if (entry.value.isNotEmpty) {
        result[entry.key] = entry.value.last.timestamp;
      }
    }

    return result;
  }

  @override
  Future<int> removeEventsOlderThan(int timestamp) async {
    _checkNotClosed();

    int removedCount = 0;

    // Remove from main events list
    _events.removeWhere((event) {
      if (event.creationTimestamp < timestamp) {
        removedCount++;
        return true;
      }
      return false;
    });

    // Remove from events by node index
    for (final nodeEvents in _eventsByNode.values) {
      nodeEvents.removeWhere((event) => event.creationTimestamp < timestamp);
    }

    // Remove from events by ID index
    _eventsById.removeWhere((id, event) => event.creationTimestamp < timestamp);

    // Clean up empty node lists
    _eventsByNode.removeWhere((nodeId, events) => events.isEmpty);

    return removedCount;
  }

  @override
  Future<int> removeEventsForNode(String nodeId) async {
    _checkNotClosed();

    final nodeEvents = _eventsByNode.remove(nodeId);
    if (nodeEvents == null) {
      return 0;
    }

    final removedCount = nodeEvents.length;

    // Remove from main events list
    for (final event in nodeEvents) {
      _events.remove(event);
      _eventsById.remove(event.id);
    }

    return removedCount;
  }

  @override
  Future<void> clear() async {
    _checkNotClosed();

    _events.clear();
    _eventsByNode.clear();
    _eventsById.clear();
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;

    _isClosed = true;

    // Clear all data to help with garbage collection
    _events.clear();
    _eventsByNode.clear();
    _eventsById.clear();
  }

  @override
  Future<EventStoreStats> getStats() async {
    _checkNotClosed();

    int? oldestTimestamp;
    int? newestTimestamp;

    if (_events.isNotEmpty) {
      oldestTimestamp = _events.first.creationTimestamp;
      newestTimestamp = _events.last.creationTimestamp;

      // Find actual min/max since sorting is by logical timestamp, not creation timestamp
      for (final event in _events) {
        if (oldestTimestamp == null ||
            event.creationTimestamp < oldestTimestamp) {
          oldestTimestamp = event.creationTimestamp;
        }
        if (newestTimestamp == null ||
            event.creationTimestamp > newestTimestamp) {
          newestTimestamp = event.creationTimestamp;
        }
      }
    }

    // Calculate approximate size in memory (rough estimate)
    int approximateSize = 0;
    for (final event in _events) {
      approximateSize += _estimateEventSize(event);
    }

    return EventStoreStats(
      totalEvents: _events.length,
      uniqueNodes: _eventsByNode.length,
      oldestEventTimestamp: oldestTimestamp,
      newestEventTimestamp: newestTimestamp,
      sizeInBytes: approximateSize,
      additionalStats: {
        'eventsById': _eventsById.length,
        'averageEventsPerNode': _eventsByNode.isEmpty
            ? 0.0
            : _events.length / _eventsByNode.length,
      },
    );
  }

  /// Estimates the memory size of an event in bytes.
  int _estimateEventSize(Event event) {
    // Rough estimation: strings + integers + object overhead
    int size = 0;
    size += event.id.length * 2; // UTF-16 chars
    size += event.nodeId.value.length * 2;
    size += 8; // timestamp (int)
    size += 8; // creationTimestamp (int)
    size += _estimateMapSize(event.payload);
    size += 64; // Object overhead estimate
    return size;
  }

  /// Estimates the memory size of a map in bytes.
  int _estimateMapSize(Map<String, dynamic> map) {
    int size = 0;
    for (final entry in map.entries) {
      size += entry.key.length * 2; // Key string
      size += _estimateValueSize(entry.value); // Value
      size += 16; // Map entry overhead
    }
    return size;
  }

  /// Estimates the memory size of a dynamic value in bytes.
  int _estimateValueSize(dynamic value) {
    if (value is String) {
      return value.length * 2; // UTF-16
    } else if (value is int) {
      return 8;
    } else if (value is double) {
      return 8;
    } else if (value is bool) {
      return 1;
    } else if (value is Map) {
      return _estimateMapSize(value.cast<String, dynamic>());
    } else if (value is List) {
      int size = 0;
      for (final item in value) {
        size += _estimateValueSize(item);
      }
      return size + (value.length * 8); // List overhead
    }
    return 8; // Default for unknown types
  }

  /// Checks if the store has been closed and throws an exception if it has.
  void _checkNotClosed() {
    if (_isClosed) {
      throw const EventStoreException('Event store has been closed');
    }
  }

  /// Returns whether the store has been closed.
  bool get isClosed => _isClosed;

  /// Returns the current number of events stored (for testing/debugging).
  int get eventCount => _events.length;

  /// Returns the current number of unique nodes (for testing/debugging).
  int get nodeCount => _eventsByNode.length;
}
