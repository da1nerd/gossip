import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gossip/gossip.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// Hive-based implementation of EventStore.
///
/// This implementation uses Hive as the storage backend, providing persistent
/// storage of events across app restarts. Events are stored in a Hive box
/// with efficient indexing for common queries.
///
/// ## Storage Structure
/// - Events are stored with their ID as the key
/// - Supports efficient queries by nodeId and timestamp
/// - Uses lazy boxes for better memory management with large datasets
///
/// ## Initialization
/// Must call [initialize] before using any other methods.
/// The store will create necessary Hive boxes and handle migrations.
class HiveEventStore implements EventStore {
  static const String _eventsBoxName = 'gossip_events';
  static const String _metadataBoxName = 'gossip_metadata';
  static const String _nodeTimestampsKey = 'node_timestamps';

  LazyBox<Map<dynamic, dynamic>>? _eventsBox;
  Box<dynamic>? _metadataBox;
  bool _isInitialized = false;
  bool _isClosed = false;

  /// Initializes the Hive event store.
  ///
  /// This method must be called before any other operations.
  /// It sets up the necessary Hive boxes and handles any required migrations.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize Hive
      if (!Hive.isAdapterRegistered(0)) {
        await Hive.initFlutter();
      }

      // Get app documents directory for Hive storage
      Directory appDocDir;
      if (!kIsWeb) {
        appDocDir = await getApplicationDocumentsDirectory();
        Hive.init('${appDocDir.path}/hive_gossip');
      }

      // Open the events box (lazy for better memory usage)
      _eventsBox = await Hive.openLazyBox<Map<dynamic, dynamic>>(
        _eventsBoxName,
      );

      // Open metadata box for storing additional info
      _metadataBox = await Hive.openBox(_metadataBoxName);

      _isInitialized = true;
      debugPrint('✅ HiveEventStore initialized successfully');
    } catch (e) {
      throw EventStoreException('Failed to initialize Hive event store: $e');
    }
  }

  void _checkInitialized() {
    if (!_isInitialized) {
      throw const EventStoreException(
        'Event store not initialized. Call initialize() first.',
      );
    }
    if (_isClosed) {
      throw const EventStoreException('Event store has been closed');
    }
  }

  @override
  Future<void> saveEvent(Event event) async {
    _checkInitialized();

    try {
      await _eventsBox!.put(event.id, event.toJson());
      await _updateNodeTimestamp(event.nodeId.value, event.timestamp);
      debugPrint('💾 Saved event ${event.id} to Hive');
    } catch (e) {
      throw EventStoreException('Failed to save event ${event.id}: $e');
    }
  }

  @override
  Future<void> saveEvents(List<Event> events) async {
    _checkInitialized();

    if (events.isEmpty) return;

    try {
      final Map<String, Map<String, dynamic>> eventMap = {};
      final Map<String, int> nodeTimestamps = {};

      for (final event in events) {
        eventMap[event.id] = event.toJson();
        final currentMax = nodeTimestamps[event.nodeId.value] ?? 0;
        if (event.timestamp > currentMax) {
          nodeTimestamps[event.nodeId.value] = event.timestamp;
        }
      }

      // Batch save events
      await _eventsBox!.putAll(eventMap);

      // Update node timestamps
      for (final entry in nodeTimestamps.entries) {
        await _updateNodeTimestamp(entry.key, entry.value);
      }

      debugPrint('💾 Saved ${events.length} events to Hive');
    } catch (e) {
      throw EventStoreException('Failed to save events: $e');
    }
  }

  @override
  Future<List<Event>> getEventsSince(
    GossipNodeID nodeId,
    int afterTimestamp, {
    int? limit,
  }) async {
    _checkInitialized();

    try {
      final List<Event> matchingEvents = [];

      for (final key in _eventsBox!.keys) {
        final eventData = await _eventsBox!.get(key);
        if (eventData != null) {
          final event = Event.fromJson(Map<String, dynamic>.from(eventData));
          if (event.nodeId.value == nodeId.value &&
              event.timestamp > afterTimestamp) {
            matchingEvents.add(event);
          }
        }
      }

      // Sort by timestamp
      matchingEvents.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Apply limit if specified
      if (limit != null && matchingEvents.length > limit) {
        return matchingEvents.take(limit).toList();
      }

      return matchingEvents;
    } catch (e) {
      throw EventStoreException(
        'Failed to get events since $afterTimestamp for node $nodeId: $e',
      );
    }
  }

  @override
  Future<List<Event>> getAllEvents() async {
    _checkInitialized();

    try {
      final List<Event> allEvents = [];

      for (final key in _eventsBox!.keys) {
        final eventData = await _eventsBox!.get(key);
        if (eventData != null) {
          final event = Event.fromJson(Map<String, dynamic>.from(eventData));
          allEvents.add(event);
        }
      }

      // Sort by creation timestamp for consistent ordering
      allEvents.sort(
        (a, b) => a.creationTimestamp.compareTo(b.creationTimestamp),
      );

      return allEvents;
    } catch (e) {
      throw EventStoreException('Failed to get all events: $e');
    }
  }

  @override
  Future<List<Event>> getEventsInRange(
    int startTimestamp,
    int endTimestamp, {
    GossipNodeID? nodeId,
    int? limit,
  }) async {
    _checkInitialized();

    try {
      final List<Event> matchingEvents = [];

      for (final key in _eventsBox!.keys) {
        final eventData = await _eventsBox!.get(key);
        if (eventData != null) {
          final event = Event.fromJson(Map<String, dynamic>.from(eventData));

          // Check timestamp range
          if (event.timestamp >= startTimestamp &&
              event.timestamp <= endTimestamp) {
            // Check node filter if specified
            if (nodeId == null || event.nodeId.value == nodeId.value) {
              matchingEvents.add(event);
            }
          }
        }
      }

      // Sort by timestamp
      matchingEvents.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Apply limit if specified
      if (limit != null && matchingEvents.length > limit) {
        return matchingEvents.take(limit).toList();
      }

      return matchingEvents;
    } catch (e) {
      throw EventStoreException(
        'Failed to get events in range [$startTimestamp, $endTimestamp]: $e',
      );
    }
  }

  @override
  Future<Event?> getEvent(String eventId) async {
    _checkInitialized();

    try {
      final eventData = await _eventsBox!.get(eventId);
      if (eventData == null) return null;

      return Event.fromJson(Map<String, dynamic>.from(eventData));
    } catch (e) {
      throw EventStoreException('Failed to get event $eventId: $e');
    }
  }

  @override
  Future<bool> hasEvent(String eventId) async {
    _checkInitialized();

    try {
      return _eventsBox!.containsKey(eventId);
    } catch (e) {
      throw EventStoreException('Failed to check if event $eventId exists: $e');
    }
  }

  @override
  Future<int> getEventCount() async {
    _checkInitialized();

    try {
      return _eventsBox!.length;
    } catch (e) {
      throw EventStoreException('Failed to get event count: $e');
    }
  }

  @override
  Future<int> getEventCountForNode(GossipNodeID nodeId) async {
    _checkInitialized();

    try {
      int count = 0;

      for (final key in _eventsBox!.keys) {
        final eventData = await _eventsBox!.get(key);
        if (eventData != null) {
          final event = Event.fromJson(Map<String, dynamic>.from(eventData));
          if (event.nodeId.value == nodeId.value) {
            count++;
          }
        }
      }

      return count;
    } catch (e) {
      throw EventStoreException(
        'Failed to get event count for node $nodeId: $e',
      );
    }
  }

  @override
  Future<int> getLatestTimestampForNode(GossipNodeID nodeId) async {
    _checkInitialized();

    try {
      final nodeTimestamps = _getNodeTimestamps();
      return nodeTimestamps[nodeId.value] ?? 0;
    } catch (e) {
      throw EventStoreException(
        'Failed to get latest timestamp for node $nodeId: $e',
      );
    }
  }

  @override
  Future<Map<GossipNodeID, int>> getLatestTimestampsForAllNodes() async {
    _checkInitialized();

    try {
      final nodeTimestamps = _getNodeTimestamps();
      final result = <GossipNodeID, int>{};
      for (final entry in nodeTimestamps.entries) {
        result[GossipNodeID(entry.key)] = entry.value;
      }
      return result;
    } catch (e) {
      throw EventStoreException(
        'Failed to get latest timestamps for all nodes: $e',
      );
    }
  }

  @override
  Future<int> removeEventsOlderThan(int timestamp) async {
    _checkInitialized();

    try {
      final List<String> keysToRemove = [];

      for (final key in _eventsBox!.keys) {
        final eventData = await _eventsBox!.get(key);
        if (eventData != null) {
          final event = Event.fromJson(Map<String, dynamic>.from(eventData));
          if (event.timestamp < timestamp) {
            keysToRemove.add(key.toString());
          }
        }
      }

      for (final key in keysToRemove) {
        await _eventsBox!.delete(key);
      }

      // Rebuild node timestamps after cleanup
      await _rebuildNodeTimestamps();

      debugPrint(
        '🧹 Removed ${keysToRemove.length} events older than $timestamp',
      );
      return keysToRemove.length;
    } catch (e) {
      throw EventStoreException(
        'Failed to remove events older than $timestamp: $e',
      );
    }
  }

  @override
  Future<int> removeEventsForNode(GossipNodeID nodeId) async {
    _checkInitialized();

    try {
      final List<String> keysToRemove = [];

      for (final key in _eventsBox!.keys) {
        final eventData = await _eventsBox!.get(key);
        if (eventData != null) {
          final event = Event.fromJson(Map<String, dynamic>.from(eventData));
          if (event.nodeId.value == nodeId.value) {
            keysToRemove.add(key.toString());
          }
        }
      }

      for (final key in keysToRemove) {
        await _eventsBox!.delete(key);
      }

      // Remove node from timestamps
      final nodeTimestamps = _getNodeTimestamps();
      nodeTimestamps.remove(nodeId);
      await _setNodeTimestamps(nodeTimestamps);

      debugPrint('🧹 Removed ${keysToRemove.length} events for node $nodeId');
      return keysToRemove.length;
    } catch (e) {
      throw EventStoreException('Failed to remove events for node $nodeId: $e');
    }
  }

  @override
  Future<void> clear() async {
    _checkInitialized();

    try {
      await _eventsBox!.clear();
      await _metadataBox!.clear();
      debugPrint('🧹 Cleared all events from Hive store');
    } catch (e) {
      throw EventStoreException('Failed to clear event store: $e');
    }
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;

    try {
      await _eventsBox?.close();
      await _metadataBox?.close();
      _isClosed = true;
      _isInitialized = false;
      debugPrint('🔒 HiveEventStore closed successfully');
    } catch (e) {
      throw EventStoreException('Failed to close event store: $e');
    }
  }

  @override
  Future<EventStoreStats> getStats() async {
    _checkInitialized();

    try {
      final totalEvents = _eventsBox!.length;
      final nodeTimestamps = _getNodeTimestamps();
      final uniqueNodes = nodeTimestamps.length;

      int? oldestTimestamp;
      int? newestTimestamp;

      if (nodeTimestamps.isNotEmpty) {
        final timestamps = nodeTimestamps.values;
        oldestTimestamp = timestamps.reduce((a, b) => a < b ? a : b);
        newestTimestamp = timestamps.reduce((a, b) => a > b ? a : b);
      }

      return EventStoreStats(
        totalEvents: totalEvents,
        uniqueNodes: uniqueNodes,
        oldestEventTimestamp: oldestTimestamp,
        newestEventTimestamp: newestTimestamp,
        additionalStats: {
          'storageBackend': 'Hive',
          'eventsBoxName': _eventsBoxName,
          'metadataBoxName': _metadataBoxName,
          'boxPath': _eventsBox?.path,
        },
      );
    } catch (e) {
      throw EventStoreException('Failed to get event store stats: $e');
    }
  }

  /// Updates the latest timestamp for a node
  Future<void> _updateNodeTimestamp(String nodeId, int timestamp) async {
    final nodeTimestamps = _getNodeTimestamps();
    final currentTimestamp = nodeTimestamps[nodeId] ?? 0;

    if (timestamp > currentTimestamp) {
      nodeTimestamps[nodeId] = timestamp;
      await _setNodeTimestamps(nodeTimestamps);
    }
  }

  /// Gets the node timestamps map from metadata
  Map<String, int> _getNodeTimestamps() {
    final data = _metadataBox!.get(_nodeTimestampsKey);
    if (data == null) return {};
    return Map<String, int>.from(data);
  }

  /// Sets the node timestamps map in metadata
  Future<void> _setNodeTimestamps(Map<String, int> timestamps) async {
    await _metadataBox!.put(_nodeTimestampsKey, timestamps);
  }

  /// Rebuilds node timestamps by scanning all events
  /// This is used after cleanup operations
  Future<void> _rebuildNodeTimestamps() async {
    final Map<String, int> nodeTimestamps = {};

    for (final key in _eventsBox!.keys) {
      final eventData = await _eventsBox!.get(key);
      if (eventData != null) {
        final event = Event.fromJson(Map<String, dynamic>.from(eventData));
        final currentMax = nodeTimestamps[event.nodeId.value] ?? 0;
        if (event.timestamp > currentMax) {
          nodeTimestamps[event.nodeId.value] = event.timestamp;
        }
      }
    }

    await _setNodeTimestamps(nodeTimestamps);
  }

  /// Compacts the Hive boxes to reclaim storage space
  /// Call this periodically for better storage efficiency
  Future<void> compact() async {
    _checkInitialized();

    try {
      await _eventsBox!.compact();
      await _metadataBox!.compact();
      debugPrint('📦 Compacted Hive event store');
    } catch (e) {
      throw EventStoreException('Failed to compact event store: $e');
    }
  }
}
