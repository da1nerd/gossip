/// Typed event extensions for GossipNode.
///
/// This module provides type-safe extensions to the core GossipNode class
/// from the gossip library, enabling strongly-typed event creation and
/// consumption while maintaining compatibility with the underlying protocol.
library;

import 'dart:async';

import 'package:gossip/gossip.dart';

import 'typed_event.dart';
import 'typed_event_registry.dart';

/// Extension on GossipNode to support typed events.
///
/// This extension adds type-safe methods for creating and consuming events
/// while maintaining full compatibility with the underlying gossip protocol.
/// All typed events are automatically serialized to the standard event format
/// used by the gossip library.
///
/// ## Usage
///
/// ```dart
/// import 'package:gossip/gossip.dart';
/// import 'package:gossip_typed_events/gossip_typed_events.dart';
///
/// // Register event types
/// final registry = TypedEventRegistry();
/// registry.register<UserLoginEvent>(
///   'user_login',
///   (json) => UserLoginEvent.fromJson(json),
/// );
///
/// // Create typed events
/// final loginEvent = UserLoginEvent(userId: '123');
/// await node.createTypedEvent(loginEvent);
///
/// // Listen for created typed events with full metadata
/// node.onTypedEventCreated<UserLoginEvent>().listen((created) {
///   print('Created ${created.typedEvent.userId} with ID ${created.eventId}');
/// });
///
/// // Listen for received typed events with full metadata
/// node.onTypedEventReceived<UserLoginEvent>().listen((received) {
///   print('Received ${received.typedEvent.userId} from ${received.fromPeer.id}');
/// });
/// ```
extension TypedGossipNode on GossipNode {
  /// Creates a typed event.
  ///
  /// The typed event is automatically serialized and wrapped in the
  /// standard event payload format expected by the gossip protocol.
  /// The event will be distributed to all connected peers through
  /// the normal gossip mechanisms.
  ///
  /// The serialized format includes:
  /// - `type`: The event type identifier
  /// - `data`: The serialized event data from `toJson()`
  /// - `version`: Format version for future compatibility
  ///
  /// Parameters:
  /// - [event]: The typed event to broadcast
  ///
  /// Returns the underlying Event that was created.
  ///
  /// Throws:
  /// - [ArgumentError] if the event is invalid
  /// - [TypedEventException] if serialization fails
  /// - Any exception from the underlying gossip node
  ///
  /// Example:
  /// ```dart
  /// final orderEvent = OrderCreatedEvent(
  ///   orderId: '12345',
  ///   customerId: 'cust-456',
  ///   amount: 99.99,
  /// );
  ///
  /// final gossipEvent = await node.createTypedEvent(orderEvent);
  /// print('Created event with ID: ${gossipEvent.id}');
  /// ```
  Future<Event> createTypedEvent<T extends TypedEvent>(T event) async {
    try {
      // Validate the event if it supports validation
      if (event is TypedEventValidatable) {
        (event as TypedEventValidatable).validate();
      }

      final payload = {
        'type': event.type,
        'data': event.toJson(),
        'version': '1.0', // Format version for future compatibility
      };

      return await createEvent(payload);
    } catch (e, stackTrace) {
      throw TypedEventException(
        'Failed to create typed event of type "${event.type}": $e',
        eventType: event.type,
        cause: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Stream of typed events with metadata of a specific type that were created locally.
  ///
  /// This method uses the global TypedEventRegistry to automatically
  /// deserialize events and includes the original Event metadata.
  ///
  /// The event type must be registered in the registry for this to work.
  ///
  /// Returns a stream of TypedEventCreated<T> that includes both the typed
  /// event and the original Event metadata.
  ///
  /// Caution: Events are only guarenteed to be in the correct order within a single stream.
  /// Since this returns a filtered stream of events that match the specified type,
  /// you could encounter race conditions with other streams.
  ///
  /// Example:
  /// ```dart
  /// // After registering UserLoginEvent in the registry
  /// node.onTypedEventCreated<UserLoginEvent>().listen((created) {
  ///   print('Created ${created.typedEvent.userId} with ID ${created.eventId}');
  /// });
  /// ```
  @Deprecated('''
    This can lead to race conditions between streams.
    Listen to onEventCreated directly and use EventRegistry.tryDeserializeEvent to manually deserialize events
    ''')
  Stream<TypedEventCreated<T>> onTypedEventCreated<T extends TypedEvent>() {
    final registry = TypedEventRegistry();
    final typeString = registry.getType<T>();

    if (typeString == null) {
      throw TypedEventException(
        'Type ${T.toString()} is not registered in TypedEventRegistry',
        eventType: T.toString(),
      );
    }

    return onEventCreated
        .where((event) => _isEventType(event, typeString))
        .map((event) {
          final typedEvent = _deserializeFromRegistry<T>(event, registry);
          return typedEvent != null
              ? TypedEventCreated(typedEvent: typedEvent, originalEvent: event)
              : null;
        })
        .where((wrapper) => wrapper != null)
        .cast<TypedEventCreated<T>>();
  }

  /// Stream of typed events with metadata of a specific type that were received from peers.
  ///
  /// This method uses the global TypedEventRegistry to automatically
  /// deserialize events and includes the original Event metadata plus
  /// peer and timing information.
  ///
  /// The event type must be registered in the registry for this to work.
  ///
  /// Returns a stream of TypedEventReceived<T> that includes the typed
  /// event, original Event metadata, peer info, and timing.
  ///
  /// Caution: Events are only guarenteed to be in the correct order within a single stream.
  /// Since this returns a filtered stream of events that match the specified type,
  /// you could encounter race conditions with other streams.
  ///
  /// Example:
  /// ```dart
  /// // After registering UserLoginEvent in the registry
  /// node.onTypedEventReceived<UserLoginEvent>().listen((received) {
  ///   print('Received ${received.typedEvent.userId} from ${received.fromPeer.id}');
  /// });
  /// ```
  @Deprecated('''
    This can lead to race conditions between streams.
    Listen to onEventReceived directly and use EventRegistry.tryDeserializeEvent to manually deserialize events
    ''')
  Stream<TypedEventReceived<T>> onTypedEventReceived<T extends TypedEvent>() {
    final registry = TypedEventRegistry();
    final typeString = registry.getType<T>();

    if (typeString == null) {
      throw TypedEventException(
        'Type ${T.toString()} is not registered in TypedEventRegistry',
        eventType: T.toString(),
      );
    }

    return onEventReceived
        .where((receivedEvent) => _isEventType(receivedEvent.event, typeString))
        .map((receivedEvent) {
          final typedEvent = _deserializeFromRegistry<T>(
            receivedEvent.event,
            registry,
          );
          return typedEvent != null
              ? TypedEventReceived(
                  typedEvent: typedEvent,
                  originalEvent: receivedEvent.event,
                  fromPeer: receivedEvent.fromPeer,
                  receivedAt: receivedEvent.receivedAt,
                )
              : null;
        })
        .where((wrapper) => wrapper != null)
        .cast<TypedEventReceived<T>>();
  }

  /// Checks if an event is a typed event with the specified type string.
  bool _isEventType(Event event, String typeString) {
    if (!_isTypedEvent(event)) return false;

    final eventType = event.payload['type'] as String?;
    return eventType == typeString;
  }

  /// Checks if an event has the typed event format.
  bool _isTypedEvent(Event event) {
    try {
      final payload = event.payload;
      return payload.containsKey('type') &&
          payload.containsKey('data') &&
          payload['type'] is String;
    } catch (e) {
      return false;
    }
  }

  /// Deserializes a typed event using the registry.
  T? _deserializeFromRegistry<T extends TypedEvent>(
    Event event,
    TypedEventRegistry registry,
  ) {
    try {
      final eventType = event.payload['type'] as String;
      final data = event.payload['data'] as Map<String, dynamic>;

      final typedEvent = registry.createFromJson(eventType, data);
      return typedEvent is T ? typedEvent : null;
    } catch (e, stackTrace) {
      _logDeserializationError(event, e, stackTrace);
      return null;
    }
  }

  /// Extracts typed event information without full deserialization.
  TypedEventInfo _extractTypedEventInfo(Event event) {
    final eventType = event.payload['type'] as String;
    final data = event.payload['data'] as Map<String, dynamic>;
    final version = event.payload['version'] as String? ?? '1.0';

    return TypedEventInfo(type: eventType, data: data, version: version);
  }

  /// Logs deserialization errors (override this for custom logging).
  void _logDeserializationError(
    Event event,
    Object error,
    StackTrace stackTrace,
  ) {
    // In a real implementation, you might want to use a proper logging framework
    print('Warning: Failed to deserialize typed event ${event.id}: $error');
  }
}

/// Interface for typed events that support validation.
abstract class TypedEventValidatable {
  /// Validates the event and throws an exception if invalid.
  void validate();
}

/// A typed event that was created locally with its original Event metadata.
class TypedEventCreated<T extends TypedEvent> {
  const TypedEventCreated({
    required this.typedEvent,
    required this.originalEvent,
  });

  /// The deserialized typed event.
  final T typedEvent;

  /// The original gossip Event that contained this typed event.
  final Event originalEvent;

  /// Convenience getter for the event ID.
  String get eventId => originalEvent.id;

  /// Convenience getter for when the event was created.
  DateTime get createdAt =>
      DateTime.fromMillisecondsSinceEpoch(originalEvent.creationTimestamp);

  /// Convenience getter for the full original payload.
  Map<String, dynamic> get fullPayload => originalEvent.payload;

  @override
  String toString() =>
      'TypedEventCreated<${T.toString()}>(eventId: $eventId, '
      'createdAt: $createdAt, typedEvent: $typedEvent)';
}

/// A typed event that was received from a peer with full metadata.
class TypedEventReceived<T extends TypedEvent> {
  const TypedEventReceived({
    required this.typedEvent,
    required this.originalEvent,
    required this.fromPeer,
    required this.receivedAt,
  });

  /// The deserialized typed event.
  final T typedEvent;

  /// The original gossip Event that contained this typed event.
  final Event originalEvent;

  /// The peer that sent this event.
  final GossipPeer fromPeer;

  /// When this event was received locally.
  final DateTime receivedAt;

  /// Convenience getter for the event ID.
  String get eventId => originalEvent.id;

  /// Convenience getter for when the event was originally created.
  DateTime get createdAt =>
      DateTime.fromMillisecondsSinceEpoch(originalEvent.creationTimestamp);

  /// Convenience getter for the full original payload.
  Map<String, dynamic> get fullPayload => originalEvent.payload;

  @override
  String toString() =>
      'TypedEventReceived<${T.toString()}>(eventId: $eventId, '
      'fromPeer: ${fromPeer.id}, receivedAt: $receivedAt, '
      'typedEvent: $typedEvent)';
}

/// Information about a typed event without full deserialization.
class TypedEventInfo {
  const TypedEventInfo({
    required this.type,
    required this.data,
    required this.version,
  });

  /// The event type identifier.
  final String type;

  /// The raw event data.
  final Map<String, dynamic> data;

  /// The format version.
  final String version;

  @override
  String toString() =>
      'TypedEventInfo(type: $type, version: $version, data: $data)';
}

/// A typed event that was received from a peer.
class TypedReceivedEvent {
  const TypedReceivedEvent({
    required this.event,
    required this.fromPeer,
    required this.receivedAt,
    required this.underlyingEvent,
  });

  /// The typed event information.
  final TypedEventInfo event;

  /// The peer that sent this event.
  final GossipPeer fromPeer;

  /// When this event was received locally.
  final DateTime receivedAt;

  /// The underlying gossip event.
  final Event underlyingEvent;

  /// Convenience getter for the event type.
  String get eventType => event.type;

  /// Convenience getter for the event data.
  Map<String, dynamic> get eventData => event.data;

  @override
  String toString() =>
      'TypedReceivedEvent(type: ${event.type}, fromPeer: ${fromPeer.id}, '
      'receivedAt: $receivedAt, underlyingEventId: ${underlyingEvent.id})';
}

/// Exception thrown when typed event operations fail.
class TypedEventException implements Exception {
  const TypedEventException(
    this.message, {
    this.eventType,
    this.cause,
    this.stackTrace,
  });

  /// The error message.
  final String message;

  /// The event type that caused the error.
  final String? eventType;

  /// The underlying cause of the error.
  final Object? cause;

  /// Stack trace from the original error.
  final StackTrace? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer('TypedEventException: $message');

    if (eventType != null) {
      buffer.write(' (eventType: $eventType)');
    }

    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }

    return buffer.toString();
  }
}
