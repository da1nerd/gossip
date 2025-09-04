/// Base class for typed events in the gossip protocol.
///
/// This abstract class provides a type-safe way to work with events in the
/// gossip protocol, allowing developers to define custom event types with
/// proper serialization and deserialization.
///
/// All custom event types should extend this class and implement the
/// required methods for type identification and serialization.
library;

/// Base class for typed events.
///
/// This class provides the foundation for creating type-safe events that
/// can be used with the gossip protocol. Each typed event must have a
/// unique type identifier and be serializable to/from JSON.
///
/// Example usage:
/// ```dart
/// class UserLoginEvent extends TypedEvent {
///   final String userId;
///   final DateTime timestamp;
///
///   UserLoginEvent({required this.userId, required this.timestamp});
///
///   @override
///   String get type => 'user_login';
///
///   @override
///   Map<String, dynamic> toJson() => {
///     'userId': userId,
///     'timestamp': timestamp.millisecondsSinceEpoch,
///   };
///
///   factory UserLoginEvent.fromJson(Map<String, dynamic> json) {
///     return UserLoginEvent(
///       userId: json['userId'] as String,
///       timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
///     );
///   }
/// }
/// ```
abstract class TypedEvent {
  /// The type identifier for this event.
  ///
  /// This should be a unique string that identifies the event type.
  /// It's used for serialization, deserialization, and routing of events.
  ///
  /// The type identifier should:
  /// - Be unique across your application
  /// - Use a consistent naming convention (e.g., snake_case)
  /// - Be descriptive of the event's purpose
  /// - Remain stable across versions (changing it breaks compatibility)
  String get type;

  /// Converts this typed event to a JSON representation.
  ///
  /// This method should serialize all the event's data to a map
  /// that can be converted to JSON. The returned map should contain
  /// all necessary data to reconstruct the event via [fromJson].
  ///
  /// Guidelines:
  /// - Include all relevant event data
  /// - Use JSON-serializable types (String, int, double, bool, List, Map)
  /// - Consider forward/backward compatibility
  /// - Don't include the type identifier (handled by the framework)
  ///
  /// Example:
  /// ```dart
  /// @override
  /// Map<String, dynamic> toJson() => {
  ///   'userId': userId,
  ///   'action': action,
  ///   'timestamp': timestamp.millisecondsSinceEpoch,
  /// };
  /// ```
  Map<String, dynamic> toJson();

  /// Creates a typed event from a JSON representation.
  ///
  /// This factory method should be implemented by subclasses to
  /// deserialize events from JSON data. The JSON map will contain
  /// the data that was previously serialized by [toJson].
  ///
  /// Note: This is a static method that should be overridden in each
  /// subclass. It cannot be made abstract due to Dart's limitations
  /// with static abstract methods.
  ///
  /// Example:
  /// ```dart
  /// factory UserLoginEvent.fromJson(Map<String, dynamic> json) {
  ///   return UserLoginEvent(
  ///     userId: json['userId'] as String,
  ///     action: json['action'] as String,
  ///     timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
  ///   );
  /// }
  /// ```
  static TypedEvent fromJson(Map<String, dynamic> json) {
    throw UnimplementedError(
      'Subclasses must implement their own fromJson factory constructor',
    );
  }

  /// Returns a string representation of this typed event.
  ///
  /// This is useful for debugging and logging purposes.
  @override
  String toString() => '$runtimeType(type: $type, data: ${toJson()})';

  /// Checks if two typed events are equal.
  ///
  /// Two typed events are considered equal if they have the same type
  /// and the same JSON representation.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TypedEvent) return false;
    if (type != other.type) return false;

    // Compare JSON representations for deep equality
    return _deepEquals(toJson(), other.toJson());
  }

  @override
  int get hashCode => Object.hash(type, _deepHashCode(toJson()));

  /// Deep equality check for maps and lists.
  bool _deepEquals(a, b) {
    if (identical(a, b)) return true;
    if (a.runtimeType != b.runtimeType) return false;

    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key)) return false;
        if (!_deepEquals(a[key], b[key])) return false;
      }
      return true;
    }

    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }

    return a == b;
  }

  /// Deep hash code calculation for maps and lists.
  int _deepHashCode(value) {
    if (value is Map) {
      var hash = 0;
      for (final entry in value.entries) {
        hash ^= Object.hash(entry.key, _deepHashCode(entry.value));
      }
      return hash;
    }

    if (value is List) {
      var hash = 0;
      for (var i = 0; i < value.length; i++) {
        hash ^= Object.hash(i, _deepHashCode(value[i]));
      }
      return hash;
    }

    return value.hashCode;
  }
}
