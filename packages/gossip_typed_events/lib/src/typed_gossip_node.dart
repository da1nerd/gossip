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
/// // Listen for typed events
/// node.onTypedEvent<UserLoginEvent>((json) => UserLoginEvent.fromJson(json))
///     .listen((event) {
///   print('User ${event.userId} logged in');
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

  /// Stream of typed events of a specific type.
  ///
  /// This method filters incoming events to only include those matching
  /// the specified type and deserializes them using the provided factory
  /// function. Events that cannot be deserialized are logged and skipped.
  ///
  /// The factory function should typically be the `fromJson` constructor
  /// of your typed event class.
  ///
  /// Parameters:
  /// - [fromJson]: Factory function to create typed events from JSON
  ///
  /// Returns a stream of typed events of type T.
  ///
  /// Example:
  /// ```dart
  /// node.onTypedEvent<UserLoginEvent>(
  ///   (json) => UserLoginEvent.fromJson(json)
  /// ).listen((event) {
  ///   print('User ${event.userId} logged in at ${event.timestamp}');
  /// });
  /// ```
  Stream<T> onTypedEvent<T extends TypedEvent>(
    T Function(Map<String, dynamic>) fromJson,
  ) =>
      onEventReceived
          .where((receivedEvent) => _isTypedEventOfType<T>(receivedEvent.event))
          .map(
            (receivedEvent) =>
                _deserializeTypedEvent<T>(receivedEvent.event, fromJson),
          )
          .where((event) => event != null)
          .cast<T>();

  /// Stream of typed events of a specific type using the registry.
  ///
  /// This is a convenience method that uses the global TypedEventRegistry
  /// to automatically deserialize events without requiring you to pass
  /// a factory function.
  ///
  /// The event type must be registered in the registry for this to work.
  ///
  /// Returns a stream of typed events of type T.
  ///
  /// Example:
  /// ```dart
  /// // After registering UserLoginEvent in the registry
  /// node.onRegisteredTypedEvent<UserLoginEvent>().listen((event) {
  ///   print('User ${event.userId} logged in');
  /// });
  /// ```
  Stream<T> onRegisteredTypedEvent<T extends TypedEvent>() {
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
        .map(
          (receivedEvent) =>
              _deserializeFromRegistry<T>(receivedEvent.event, registry),
        )
        .where((event) => event != null)
        .cast<T>();
  }

  /// Stream of all typed events with their metadata.
  ///
  /// This stream emits all incoming events that have the typed event format,
  /// along with metadata about when and from whom they were received.
  ///
  /// Returns a stream of TypedReceivedEvent objects.
  ///
  /// Example:
  /// ```dart
  /// node.onAnyTypedEvent().listen((typedReceived) {
  ///   print('Received ${typedReceived.event.type} from ${typedReceived.fromPeer.id}');
  /// });
  /// ```
  Stream<TypedReceivedEvent> onAnyTypedEvent() => onEventReceived
      .where((receivedEvent) => _isTypedEvent(receivedEvent.event))
      .map(
        (receivedEvent) => TypedReceivedEvent(
          event: _extractTypedEventInfo(receivedEvent.event),
          fromPeer: receivedEvent.fromPeer,
          receivedAt: receivedEvent.receivedAt,
          underlyingEvent: receivedEvent.event,
        ),
      );

  /// Checks if an event is a typed event of the specified type.
  bool _isTypedEventOfType<T extends TypedEvent>(Event event) {
    if (!_isTypedEvent(event)) return false;

    final registry = TypedEventRegistry();
    final expectedType = registry.getType<T>();
    if (expectedType == null) return false;

    final eventType = event.payload['type'] as String?;
    return eventType == expectedType;
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

  /// Deserializes a typed event using the provided factory function.
  T? _deserializeTypedEvent<T extends TypedEvent>(
    Event event,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    try {
      final data = event.payload['data'] as Map<String, dynamic>?;
      if (data == null) return null;

      return fromJson(data);
    } catch (e, stackTrace) {
      // Log error but don't throw - just filter out this event
      _logDeserializationError(event, e, stackTrace);
      return null;
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
