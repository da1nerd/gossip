/// Typed event system for better developer experience.
///
/// This module provides a type-safe way to work with events in the gossip
/// protocol, allowing developers to define custom event types with proper
/// serialization and deserialization.
library;

import 'dart:async';

import 'event.dart';
import 'gossip_node.dart';

/// Base class for typed events.
///
/// All custom event types should extend this class and implement the
/// required methods for type identification and serialization.
abstract class TypedEvent {
  /// The type identifier for this event.
  ///
  /// This should be a unique string that identifies the event type.
  /// It's used for serialization and routing of events.
  String get type;

  /// Converts this typed event to a JSON representation.
  ///
  /// This method should serialize all the event's data to a map
  /// that can be converted to JSON.
  Map<String, dynamic> toJson();

  /// Creates a typed event from a JSON representation.
  ///
  /// This factory method should be implemented by subclasses to
  /// deserialize events from JSON data.
  static TypedEvent fromJson(Map<String, dynamic> json) {
    throw UnimplementedError('Subclasses must implement fromJson');
  }
}

/// Extension on GossipNode to support typed events.
extension TypedGossipNode on GossipNode {
  /// Broadcasts a typed event to all peers.
  ///
  /// The typed event is automatically serialized and wrapped in the
  /// standard event payload format.
  ///
  /// Parameters:
  /// - [event]: The typed event to broadcast
  ///
  /// Returns the underlying Event that was created and broadcast.
  Future<Event> broadcastTypedEvent<T extends TypedEvent>(T event) async {
    return await createEvent({
      'type': event.type,
      'data': event.toJson(),
    });
  }

  /// Stream of typed events of a specific type.
  ///
  /// This method filters incoming events to only include those matching
  /// the specified type and deserializes them using the provided factory.
  ///
  /// Parameters:
  /// - [fromJson]: Factory function to create typed events from JSON
  ///
  /// Returns a stream of typed events of type T.
  Stream<T> onTypedEvent<T extends TypedEvent>(
    T Function(Map<String, dynamic>) fromJson,
  ) {
    return onEventReceived.where((event) {
      try {
        final eventType = event.payload['type'] as String?;
        if (eventType == null) return false;

        final registry = TypedEventRegistry();
        final filterType = registry.getType<T>();

        return eventType == filterType;
      } catch (e) {
        return false;
      }
    }).map((event) {
      final data = event.payload['data'] as Map<String, dynamic>;
      return fromJson(data);
    }).handleError((error) {
      // Log error but continue stream
      print('Error deserializing typed event: $error');
    });
  }
}

/// Mixin for common typed event functionality.
///
/// This mixin provides common functionality that typed events might need,
/// such as timestamp tracking or common validation.
mixin TypedEventMixin on TypedEvent {
  /// Timestamp when this event was created.
  DateTime get createdAt => DateTime.now();

  /// Validates the event data.
  ///
  /// Override this method to add custom validation logic.
  /// Should throw an exception if the event is invalid.
  void validate() {
    // Default implementation does nothing
  }

  /// Converts this event to JSON with common metadata.
  Map<String, dynamic> toJsonWithMetadata() {
    final json = toJson();
    json['createdAt'] = createdAt.millisecondsSinceEpoch;
    return json;
  }
}

/// Registry for typed event factories.
///
/// This class maintains a registry of event types and their corresponding
/// factory functions, allowing for dynamic event deserialization.
class TypedEventRegistry {
  static final TypedEventRegistry _instance = TypedEventRegistry._internal();
  factory TypedEventRegistry() => _instance;
  TypedEventRegistry._internal();

  final Map<String, TypedEvent Function(Map<String, dynamic>)> _factories = {};
  final Map<Type, String> _types = {};

  /// Registers a typed event factory.
  ///
  /// Parameters:
  /// - [type]: The event type identifier
  /// - [factory]: Function to create events of this type from JSON
  void register<T extends TypedEvent>(
    String type,
    T Function(Map<String, dynamic>) factory,
  ) {
    _factories[type] = factory;
    _types[T] = type;
  }

  /// Creates a typed event from JSON using the registry.
  ///
  /// Parameters:
  /// - [type]: The event type identifier
  /// - [json]: The JSON data to deserialize
  ///
  /// Returns the typed event, or null if the type is not registered.
  TypedEvent? createFromJson(String type, Map<String, dynamic> json) {
    final factory = _factories[type];
    return factory?.call(json);
  }

  /// Gets all registered event types.
  List<String> get registeredTypes => _factories.keys.toList();

  /// Checks if a type is registered.
  bool isRegistered(String type) => _factories.containsKey(type);

  /// Gets the type identifier for a given TypedEvent subclass.
  String? getType<T extends TypedEvent>() => _types[T];

  /// Clears all registered factories (useful for testing).
  void clear() => _factories.clear();
}

/// Stream transformer for typed events.
///
/// This transformer can be used to convert a stream of raw events
/// into a stream of typed events using the registry.
class TypedEventTransformer<T extends TypedEvent>
    extends StreamTransformerBase<Event, T> {
  final String eventType;
  final T Function(Map<String, dynamic>) factory;

  const TypedEventTransformer({
    required this.eventType,
    required this.factory,
  });

  @override
  Stream<T> bind(Stream<Event> stream) {
    return stream.where((event) {
      final type = event.payload['type'] as String?;
      return type == eventType;
    }).map((event) {
      final data = event.payload['data'] as Map<String, dynamic>;
      return factory(data);
    }).handleError((error) {
      print('Error in typed event transformer: $error');
    });
  }
}

/// Helper function to create a typed event transformer.
TypedEventTransformer<T> typedEventTransformer<T extends TypedEvent>({
  required String eventType,
  required T Function(Map<String, dynamic>) factory,
}) {
  return TypedEventTransformer<T>(
    eventType: eventType,
    factory: factory,
  );
}
