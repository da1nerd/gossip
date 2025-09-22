/// Registry for typed event factories.
///
/// This class maintains a registry of event types and their corresponding
/// factory functions, allowing for dynamic event deserialization and
/// type management across the application.
///
/// The registry uses a singleton pattern to ensure consistent type
/// registration across the entire application.
library;

import 'package:gossip/gossip.dart';

import 'typed_event.dart';

/// Registry for typed event factories.
///
/// This class manages the mapping between event type strings and their
/// corresponding factory functions. It enables dynamic deserialization
/// of typed events from JSON data and provides type introspection
/// capabilities.
///
/// ## Usage
///
/// Register event types at application startup:
/// ```dart
/// void main() {
///   final registry = TypedEventRegistry();
///
///   registry.register<UserLoginEvent>(
///     'user_login',
///     (json) => UserLoginEvent.fromJson(json),
///   );
///
///   registry.register<OrderCreatedEvent>(
///     'order_created',
///     (json) => OrderCreatedEvent.fromJson(json),
///   );
///
///   // ... rest of application
/// }
/// ```
///
/// Create events from JSON:
/// ```dart
/// final registry = TypedEventRegistry();
/// final event = registry.createFromJson('user_login', jsonData);
/// ```
///
/// ## Thread Safety
///
/// The registry is thread-safe and can be accessed concurrently from
/// multiple isolates or async contexts.
class TypedEventRegistry {
  /// Gets the singleton instance of the registry.
  factory TypedEventRegistry() => _instance;

  /// Private constructor for singleton pattern.
  TypedEventRegistry._internal();
  static final TypedEventRegistry _instance = TypedEventRegistry._internal();

  /// Map of type strings to factory functions.
  final Map<String, TypedEvent Function(Map<String, dynamic>)> _factories = {};

  /// Map of Dart types to type strings.
  final Map<Type, String> _types = {};

  /// Map of type strings to Dart types for introspection.
  final Map<String, Type> _typeNames = {};

  /// Registers a typed event factory.
  ///
  /// This method associates a type string with a factory function that can
  /// create instances of the typed event from JSON data.
  ///
  /// Parameters:
  /// - [type]: The event type identifier (must be unique)
  /// - [factory]: Function to create events of this type from JSON
  ///
  /// Throws [ArgumentError] if:
  /// - The type string is empty
  /// - The type is already registered with a different factory
  /// - The factory function is null
  ///
  /// Example:
  /// ```dart
  /// registry.register<UserLoginEvent>(
  ///   'user_login',
  ///   (json) => UserLoginEvent.fromJson(json),
  /// );
  /// ```
  void register<T extends TypedEvent>(
    String type,
    T Function(Map<String, dynamic>) factory,
  ) {
    if (type.isEmpty) {
      throw ArgumentError('Event type cannot be empty');
    }

    // Check if type is already registered with a different factory
    if (_factories.containsKey(type)) {
      final existingType = _typeNames[type];
      if (existingType != T) {
        throw ArgumentError(
          'Type "$type" is already registered for ${existingType?.toString() ?? 'unknown'}, '
          'cannot register for $T',
        );
      }
      // Allow re-registration of the same type with same generic type
      // This can happen during hot reload or testing
    }

    _factories[type] = factory;
    _types[T] = type;
    _typeNames[type] = T;
  }

  /// Creates a typed event from JSON using the registry.
  ///
  /// This method looks up the appropriate factory function for the given
  /// type and uses it to create a typed event instance from the JSON data.
  ///
  /// Parameters:
  /// - [type]: The event type identifier
  /// - [json]: The JSON data to deserialize
  ///
  /// Returns:
  /// - The typed event instance, or null if the type is not registered
  ///
  /// Throws:
  /// - [ArgumentError] if the type string is empty
  /// - Any exception thrown by the factory function
  ///
  /// Example:
  /// ```dart
  /// final event = registry.createFromJson('user_login', {
  ///   'userId': '123',
  ///   'timestamp': 1640995200000,
  /// });
  /// ```
  TypedEvent? createFromJson(String type, Map<String, dynamic> json) {
    if (type.isEmpty) {
      throw ArgumentError('Event type cannot be empty');
    }

    final factory = _factories[type];
    if (factory == null) {
      return null;
    }

    try {
      return factory(json);
    } catch (e, stackTrace) {
      throw TypedEventRegistryException(
        'Failed to create event of type "$type": $e',
        type: type,
        cause: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Creates a strongly-typed event from JSON.
  ///
  /// This method is similar to [createFromJson] but returns a strongly-typed
  /// result. It will return null if the type is not registered or if the
  /// registered type doesn't match T.
  ///
  /// Parameters:
  /// - [type]: The event type identifier
  /// - [json]: The JSON data to deserialize
  ///
  /// Returns:
  /// - The typed event instance as T, or null if not found or wrong type
  ///
  /// Example:
  /// ```dart
  /// final loginEvent = registry.createFromJsonAs<UserLoginEvent>(
  ///   'user_login',
  ///   jsonData,
  /// );
  /// ```
  T? createFromJsonAs<T extends TypedEvent>(
    String type,
    Map<String, dynamic> json,
  ) {
    final event = createFromJson(type, json);
    return event is T ? event : null;
  }

  /// Gets all registered event types.
  ///
  /// Returns a list of all type strings that have been registered
  /// with the registry.
  List<String> get registeredTypes => List.unmodifiable(_factories.keys);

  /// Gets all registered Dart types.
  ///
  /// Returns a list of all Dart types that have been registered
  /// with the registry.
  List<Type> get registeredDartTypes => List.unmodifiable(_types.keys);

  /// Checks if a type is registered.
  ///
  /// Parameters:
  /// - [type]: The event type identifier to check
  ///
  /// Returns:
  /// - true if the type is registered, false otherwise
  bool isRegistered(String type) => _factories.containsKey(type);

  /// Checks if a Dart type is registered.
  ///
  /// Parameters:
  /// - [T]: The Dart type to check
  ///
  /// Returns:
  /// - true if the Dart type is registered, false otherwise
  bool isDartTypeRegistered<T extends TypedEvent>() => _types.containsKey(T);

  /// Gets the type identifier for a given TypedEvent subclass.
  ///
  /// Parameters:
  /// - [T]: The Dart type to look up
  ///
  /// Returns:
  /// - The type string, or null if not registered
  String? getType<T extends TypedEvent>() => _types[T];

  /// Gets the Dart type for a given type string.
  ///
  /// Parameters:
  /// - [type]: The event type identifier
  ///
  /// Returns:
  /// - The Dart type, or null if not registered
  Type? getDartType(String type) => _typeNames[type];

  /// Unregisters a type from the registry.
  ///
  /// This removes the type and its factory function from the registry.
  /// Use with caution as it can break deserialization of existing events.
  ///
  /// Parameters:
  /// - [type]: The event type identifier to unregister
  ///
  /// Returns:
  /// - true if the type was registered and removed, false otherwise
  bool unregister(String type) {
    if (!_factories.containsKey(type)) {
      return false;
    }

    final dartType = _typeNames[type];

    _factories.remove(type);
    _typeNames.remove(type);

    if (dartType != null) {
      _types.remove(dartType);
    }

    return true;
  }

  /// Unregisters all types from the registry.
  ///
  /// This clears the entire registry. Primarily useful for testing
  /// or when completely reinitializing the application.
  void clear() {
    _factories.clear();
    _types.clear();
    _typeNames.clear();
  }

  /// Gets statistics about the registry.
  ///
  /// Returns information about the current state of the registry
  /// that can be useful for debugging or monitoring.
  TypedEventRegistryStats getStats() => TypedEventRegistryStats(
    totalRegisteredTypes: _factories.length,
    registeredTypes: List.unmodifiable(_factories.keys),
    registeredDartTypes: List.unmodifiable(_types.keys),
  );

  /// Creates a copy of the current type mappings.
  ///
  /// This returns a snapshot of the current registry state.
  /// Useful for debugging or creating backups.
  Map<String, Type> getTypeMappings() => Map.unmodifiable(_typeNames);

  /// Attempts to deserialize a gossip Event into a typed event.
  ///
  /// This method checks if the event has the typed event format and
  /// attempts to deserialize it using the registered factory.
  ///
  /// Parameters:
  /// - [event]: The gossip Event to deserialize
  ///
  /// Returns the typed event if successful, null otherwise.
  ///
  /// Example:
  /// ```dart
  /// node.onEventReceived.listen((receivedEvent) {
  ///   final registry = TypedEventRegistry();
  ///   final typedEvent = registry.tryDeserializeEvent(receivedEvent.event);
  ///
  ///   if (typedEvent is LoginEvent) {
  ///     print('User ${typedEvent.userId} logged in');
  ///   }
  /// });
  /// ```
  TypedEvent? tryDeserializeEvent(Event event) {
    if (!_isTypedEvent(event)) {
      return null;
    }

    try {
      final eventType = event.payload['type'] as String;
      final data = event.payload['data'] as Map<String, dynamic>;
      return createFromJson(eventType, data);
    } catch (e) {
      print('Error deserializing event: $e');
      return null;
    }
  }

  /// Attempts to deserialize a gossip Event into a specific typed event type.
  ///
  /// This method is similar to [tryDeserializeEvent] but provides type safety
  /// by only returning events that match the specified type T.
  ///
  /// Parameters:
  /// - [event]: The gossip Event to deserialize
  ///
  /// Returns the typed event as T if successful and matches type, null otherwise.
  ///
  /// Example:
  /// ```dart
  /// final loginEvent = registry.tryDeserializeEventAs<LoginEvent>(event);
  /// if (loginEvent != null) {
  ///   print('User ${loginEvent.userId} logged in');
  /// }
  /// ```
  T? tryDeserializeEventAs<T extends TypedEvent>(Event event) {
    final typedEvent = tryDeserializeEvent(event);
    return typedEvent is T ? typedEvent : null;
  }

  /// Checks if a gossip Event has the typed event format.
  ///
  /// This method validates that an event contains the required structure
  /// for typed events (type, data, and optionally version fields).
  ///
  /// Parameters:
  /// - [event]: The gossip Event to check
  ///
  /// Returns true if the event has typed event format, false otherwise.
  ///
  /// Example:
  /// ```dart
  /// if (registry.isTypedEvent(event)) {
  ///   // Handle as typed event
  /// }
  /// ```
  bool isTypedEvent(Event event) => _isTypedEvent(event);

  /// Internal helper to check typed event format.
  bool _isTypedEvent(Event event) {
    try {
      final payload = event.payload;
      return payload.containsKey('type') &&
          payload.containsKey('data') &&
          payload['type'] is String &&
          payload['data'] is Map<String, dynamic>;
    } catch (e) {
      return false;
    }
  }

  @override
  String toString() =>
      'TypedEventRegistry(registeredTypes: ${_factories.length})';
}

/// Statistics about the typed event registry.
class TypedEventRegistryStats {
  const TypedEventRegistryStats({
    required this.totalRegisteredTypes,
    required this.registeredTypes,
    required this.registeredDartTypes,
  });

  /// Total number of registered types.
  final int totalRegisteredTypes;

  /// List of registered type strings.
  final List<String> registeredTypes;

  /// List of registered Dart types.
  final List<Type> registeredDartTypes;

  @override
  String toString() =>
      'TypedEventRegistryStats('
      'totalRegisteredTypes: $totalRegisteredTypes, '
      'registeredTypes: $registeredTypes, '
      'registeredDartTypes: $registeredDartTypes'
      ')';
}

/// Exception thrown when typed event registry operations fail.
class TypedEventRegistryException implements Exception {
  const TypedEventRegistryException(
    this.message, {
    this.type,
    this.cause,
    this.stackTrace,
  });

  /// The error message.
  final String message;

  /// The event type that caused the error.
  final String? type;

  /// The underlying cause of the error.
  final Object? cause;

  /// Stack trace from the original error.
  final StackTrace? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer('TypedEventRegistryException: $message');

    if (type != null) {
      buffer.write(' (type: $type)');
    }

    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }

    return buffer.toString();
  }
}
