/// Stream transformer for typed events.
///
/// This module provides stream transformation capabilities for converting
/// raw gossip events into typed events. It includes transformers for
/// filtering, deserializing, and processing typed events in streams.
library;

import 'dart:async';

import 'package:gossip/gossip.dart';

import 'typed_event.dart';
import 'typed_event_registry.dart';

/// Stream transformer for typed events.
///
/// This transformer converts a stream of raw Events into a stream of
/// typed events using the registry for deserialization. It provides
/// filtering and error handling capabilities.
///
/// ## Usage
///
/// ```dart
/// final transformer = TypedEventTransformer<UserLoginEvent>(
///   eventType: 'user_login',
///   factory: (json) => UserLoginEvent.fromJson(json),
/// );
///
/// final typedEventStream = rawEventStream.transform(transformer);
/// ```
///
/// Or use the convenience function:
/// ```dart
/// final typedEventStream = rawEventStream.transform(
///   typedEventTransformer<UserLoginEvent>(
///     eventType: 'user_login',
///     factory: (json) => UserLoginEvent.fromJson(json),
///   ),
/// );
/// ```
class TypedEventTransformer<T extends TypedEvent>
    extends StreamTransformerBase<Event, T> {
  /// Creates a typed event transformer.
  ///
  /// Parameters:
  /// - [eventType]: The event type identifier to filter for
  /// - [factory]: Function to create typed events from JSON data
  /// - [skipErrors]: Whether to skip events that fail to deserialize (default: true)
  /// - [onError]: Optional error handler for deserialization failures
  const TypedEventTransformer({
    required this.eventType,
    required this.factory,
    this.skipErrors = true,
    this.onError,
  });

  /// The event type to filter for.
  final String eventType;

  /// The factory function to create typed events from JSON.
  final T Function(Map<String, dynamic>) factory;

  /// Whether to skip events that fail to deserialize.
  final bool skipErrors;

  /// Optional error handler for deserialization failures.
  final void Function(Event event, Object error, StackTrace stackTrace)?
      onError;

  @override
  Stream<T> bind(Stream<Event> stream) => stream
      .where(_isTargetEventType)
      .asyncMap(_deserializeEvent)
      .where((event) => event != null)
      .cast<T>();

  /// Checks if an event is the target event type.
  bool _isTargetEventType(Event event) {
    try {
      final payload = event.payload;
      if (!payload.containsKey('type') || !payload.containsKey('data')) {
        return false;
      }

      final type = payload['type'];
      return type == eventType;
    } catch (e) {
      return false;
    }
  }

  /// Deserializes an event to the typed event.
  Future<T?> _deserializeEvent(Event event) async {
    try {
      final data = event.payload['data'] as Map<String, dynamic>;
      return factory(data);
    } catch (e, stackTrace) {
      // Call error handler if provided
      onError?.call(event, e, stackTrace);

      if (!skipErrors) {
        rethrow;
      }

      return null;
    }
  }
}

/// Stream transformer that uses the TypedEventRegistry for deserialization.
///
/// This transformer automatically uses the global registry to deserialize
/// events, eliminating the need to provide factory functions manually.
///
/// ## Usage
///
/// ```dart
/// final transformer = RegistryTypedEventTransformer<UserLoginEvent>();
/// final typedEventStream = rawEventStream.transform(transformer);
/// ```
class RegistryTypedEventTransformer<T extends TypedEvent>
    extends StreamTransformerBase<Event, T> {
  /// Creates a registry-based typed event transformer.
  ///
  /// Parameters:
  /// - [skipErrors]: Whether to skip events that fail to deserialize (default: true)
  /// - [onError]: Optional error handler for deserialization failures
  /// - [registry]: Optional registry to use (defaults to singleton instance)
  const RegistryTypedEventTransformer({
    this.skipErrors = true,
    this.onError,
    this.registry,
  });

  /// Whether to skip events that fail to deserialize.
  final bool skipErrors;

  /// Optional error handler for deserialization failures.
  final void Function(Event event, Object error, StackTrace stackTrace)?
      onError;

  /// The registry to use for deserialization.
  final TypedEventRegistry? registry;

  @override
  Stream<T> bind(Stream<Event> stream) {
    final reg = registry ?? TypedEventRegistry();
    final eventType = reg.getType<T>();

    if (eventType == null) {
      throw TypedEventTransformerException(
        'Type ${T.toString()} is not registered in TypedEventRegistry',
        dartType: T,
      );
    }

    return stream
        .where((event) => _isTargetEventType(event, eventType))
        .asyncMap((event) => _deserializeEvent(event, reg, eventType))
        .where((event) => event != null)
        .cast<T>();
  }

  /// Checks if an event is the target event type.
  bool _isTargetEventType(Event event, String targetType) {
    try {
      final payload = event.payload;
      if (!payload.containsKey('type') || !payload.containsKey('data')) {
        return false;
      }

      final type = payload['type'];
      return type == targetType;
    } catch (e) {
      return false;
    }
  }

  /// Deserializes an event using the registry.
  Future<T?> _deserializeEvent(
    Event event,
    TypedEventRegistry registry,
    String eventType,
  ) async {
    try {
      final data = event.payload['data'] as Map<String, dynamic>;
      final typedEvent = registry.createFromJson(eventType, data);
      return typedEvent is T ? typedEvent : null;
    } catch (e, stackTrace) {
      // Call error handler if provided
      onError?.call(event, e, stackTrace);

      if (!skipErrors) {
        rethrow;
      }

      return null;
    }
  }
}

/// Multi-type stream transformer for typed events.
///
/// This transformer can handle multiple event types in a single stream,
/// using the registry to deserialize any registered event type.
///
/// ## Usage
///
/// ```dart
/// final transformer = MultiTypeEventTransformer();
/// final typedEventStream = rawEventStream.transform(transformer);
///
/// typedEventStream.listen((event) {
///   if (event is UserLoginEvent) {
///     // Handle login
///   } else if (event is OrderCreatedEvent) {
///     // Handle order creation
///   }
/// });
/// ```
class MultiTypeEventTransformer
    extends StreamTransformerBase<Event, TypedEvent> {
  /// Creates a multi-type event transformer.
  ///
  /// Parameters:
  /// - [skipErrors]: Whether to skip events that fail to deserialize (default: true)
  /// - [onError]: Optional error handler for deserialization failures
  /// - [registry]: Optional registry to use (defaults to singleton instance)
  /// - [includeTypes]: Optional set of types to include (null means all)
  /// - [excludeTypes]: Optional set of types to exclude (null means none)
  const MultiTypeEventTransformer({
    this.skipErrors = true,
    this.onError,
    this.registry,
    this.includeTypes,
    this.excludeTypes,
  });

  /// Whether to skip events that fail to deserialize.
  final bool skipErrors;

  /// Optional error handler for deserialization failures.
  final void Function(Event event, Object error, StackTrace stackTrace)?
      onError;

  /// The registry to use for deserialization.
  final TypedEventRegistry? registry;

  /// Optional filter for event types to include.
  final Set<String>? includeTypes;

  /// Optional filter for event types to exclude.
  final Set<String>? excludeTypes;

  @override
  Stream<TypedEvent> bind(Stream<Event> stream) {
    final reg = registry ?? TypedEventRegistry();

    return stream
        .where(_isTypedEvent)
        .where(_shouldIncludeEvent)
        .asyncMap((event) => _deserializeEvent(event, reg))
        .where((event) => event != null)
        .cast<TypedEvent>();
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

  /// Checks if an event should be included based on filters.
  bool _shouldIncludeEvent(Event event) {
    try {
      final eventType = event.payload['type'] as String;

      // Check include filter
      if (includeTypes != null && !includeTypes!.contains(eventType)) {
        return false;
      }

      // Check exclude filter
      if (excludeTypes != null && excludeTypes!.contains(eventType)) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Deserializes an event using the registry.
  Future<TypedEvent?> _deserializeEvent(
    Event event,
    TypedEventRegistry registry,
  ) async {
    try {
      final eventType = event.payload['type'] as String;
      final data = event.payload['data'] as Map<String, dynamic>;

      return registry.createFromJson(eventType, data);
    } catch (e, stackTrace) {
      // Call error handler if provided
      onError?.call(event, e, stackTrace);

      if (!skipErrors) {
        rethrow;
      }

      return null;
    }
  }
}

/// Helper function to create a typed event transformer.
///
/// This is a convenience function that creates a TypedEventTransformer
/// with less boilerplate code.
///
/// Parameters:
/// - [eventType]: The event type identifier to filter for
/// - [factory]: Function to create typed events from JSON data
/// - [skipErrors]: Whether to skip events that fail to deserialize (default: true)
/// - [onError]: Optional error handler for deserialization failures
///
/// Example:
/// ```dart
/// final transformer = typedEventTransformer<UserLoginEvent>(
///   eventType: 'user_login',
///   factory: (json) => UserLoginEvent.fromJson(json),
/// );
/// ```
TypedEventTransformer<T> typedEventTransformer<T extends TypedEvent>({
  required String eventType,
  required T Function(Map<String, dynamic>) factory,
  bool skipErrors = true,
  void Function(Event event, Object error, StackTrace stackTrace)? onError,
}) =>
    TypedEventTransformer<T>(
      eventType: eventType,
      factory: factory,
      skipErrors: skipErrors,
      onError: onError,
    );

/// Helper function to create a registry-based typed event transformer.
///
/// This is a convenience function that creates a RegistryTypedEventTransformer.
///
/// Parameters:
/// - [skipErrors]: Whether to skip events that fail to deserialize (default: true)
/// - [onError]: Optional error handler for deserialization failures
/// - [registry]: Optional registry to use (defaults to singleton instance)
///
/// Example:
/// ```dart
/// final transformer = registryTypedEventTransformer<UserLoginEvent>();
/// ```
RegistryTypedEventTransformer<T>
    registryTypedEventTransformer<T extends TypedEvent>({
  bool skipErrors = true,
  void Function(Event event, Object error, StackTrace stackTrace)? onError,
  TypedEventRegistry? registry,
}) =>
        RegistryTypedEventTransformer<T>(
          skipErrors: skipErrors,
          onError: onError,
          registry: registry,
        );

/// Helper function to create a multi-type event transformer.
///
/// This is a convenience function that creates a MultiTypeEventTransformer.
///
/// Parameters:
/// - [skipErrors]: Whether to skip events that fail to deserialize (default: true)
/// - [onError]: Optional error handler for deserialization failures
/// - [registry]: Optional registry to use (defaults to singleton instance)
/// - [includeTypes]: Optional set of types to include (null means all)
/// - [excludeTypes]: Optional set of types to exclude (null means none)
///
/// Example:
/// ```dart
/// final transformer = multiTypeEventTransformer(
///   includeTypes: {'user_login', 'user_logout'},
/// );
/// ```
MultiTypeEventTransformer multiTypeEventTransformer({
  bool skipErrors = true,
  void Function(Event event, Object error, StackTrace stackTrace)? onError,
  TypedEventRegistry? registry,
  Set<String>? includeTypes,
  Set<String>? excludeTypes,
}) =>
    MultiTypeEventTransformer(
      skipErrors: skipErrors,
      onError: onError,
      registry: registry,
      includeTypes: includeTypes,
      excludeTypes: excludeTypes,
    );

/// Exception thrown when typed event transformer operations fail.
class TypedEventTransformerException implements Exception {
  const TypedEventTransformerException(
    this.message, {
    this.eventType,
    this.dartType,
    this.cause,
    this.stackTrace,
  });

  /// The error message.
  final String message;

  /// The event type that caused the error.
  final String? eventType;

  /// The Dart type that caused the error.
  final Type? dartType;

  /// The underlying cause of the error.
  final Object? cause;

  /// Stack trace from the original error.
  final StackTrace? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer('TypedEventTransformerException: $message');

    if (eventType != null) {
      buffer.write(' (eventType: $eventType)');
    }

    if (dartType != null) {
      buffer.write(' (dartType: $dartType)');
    }

    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }

    return buffer.toString();
  }
}
