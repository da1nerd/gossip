/// Mixin for common typed event functionality.
///
/// This mixin provides common functionality that typed events might need,
/// such as timestamp tracking, validation, and metadata handling.
/// It's designed to be mixed in with TypedEvent subclasses to provide
/// additional capabilities without requiring inheritance.
library;

import 'typed_event.dart';

/// Mixin for common typed event functionality.
///
/// This mixin provides shared functionality that many typed events need:
/// - Automatic timestamp tracking
/// - Event validation framework
/// - Metadata handling
/// - Common serialization helpers
///
/// Usage:
/// ```dart
/// class UserActionEvent extends TypedEvent with TypedEventMixin {
///   final String userId;
///   final String action;
///
///   UserActionEvent({required this.userId, required this.action});
///
///   @override
///   String get type => 'user_action';
///
///   @override
///   Map<String, dynamic> toJson() => {
///     ...toJsonWithMetadata(),
///     'userId': userId,
///     'action': action,
///   };
///
///   @override
///   void validate() {
///     super.validate();
///     if (userId.isEmpty) throw ArgumentError('userId cannot be empty');
///   }
/// }
/// ```
mixin TypedEventMixin on TypedEvent {
  DateTime? _createdAt;

  /// Timestamp when this event was created.
  ///
  /// This is automatically set when the event is first accessed.
  /// The timestamp represents when the event object was created,
  /// not when the underlying gossip event was created.
  DateTime get createdAt => _createdAt ??= DateTime.now();

  /// Optional metadata associated with this event.
  ///
  /// This can be used to store additional information that doesn't
  /// belong in the main event data but might be useful for processing,
  /// routing, or debugging.
  Map<String, dynamic> get metadata => _metadata;
  Map<String, dynamic> _metadata = {};

  /// Sets metadata for this event.
  ///
  /// Parameters:
  /// - [key]: The metadata key
  /// - [value]: The metadata value (must be JSON-serializable)
  void setMetadata(String key, value) {
    _metadata[key] = value;
  }

  /// Gets a metadata value by key.
  ///
  /// Returns null if the key doesn't exist.
  T? getMetadata<T>(String key) {
    final value = _metadata[key];
    return value is T ? value : null;
  }

  /// Removes a metadata key.
  ///
  /// Returns true if the key was present and removed, false otherwise.
  bool removeMetadata(String key) => _metadata.remove(key) != null;

  /// Validates the event data.
  ///
  /// Override this method to add custom validation logic.
  /// The base implementation performs common validations:
  /// - Ensures type is not empty
  /// - Validates that toJson() doesn't return null
  /// - Checks that required fields are present
  ///
  /// Should throw an exception if the event is invalid.
  ///
  /// Example:
  /// ```dart
  /// @override
  /// void validate() {
  ///   super.validate(); // Always call super first
  ///
  ///   if (userId.isEmpty) {
  ///     throw ArgumentError('userId cannot be empty');
  ///   }
  ///
  ///   if (!['create', 'update', 'delete'].contains(action)) {
  ///     throw ArgumentError('Invalid action: $action');
  ///   }
  /// }
  /// ```
  void validate() {
    if (type.isEmpty) {
      throw ArgumentError('Event type cannot be empty');
    }

    try {
      final json = toJson();
      if (json.isEmpty && _requiresData) {
        throw ArgumentError('Event data cannot be empty for type: $type');
      }
    } catch (e) {
      throw ArgumentError('Event serialization failed: $e');
    }
  }

  /// Whether this event type requires non-empty data.
  ///
  /// Override this to false if your event type is allowed to have empty data.
  /// Most events should have some data, but some marker events might not.
  bool get _requiresData => true;

  /// Converts this event to JSON with common metadata included.
  ///
  /// This includes the creation timestamp and any custom metadata
  /// in addition to the event's core data. Use this instead of toJson()
  /// if you want to include the standard metadata.
  ///
  /// The resulting JSON will have this structure:
  /// ```json
  /// {
  ///   "createdAt": 1640995200000,
  ///   "metadata": {...},
  ///   ...your event data...
  /// }
  /// ```
  Map<String, dynamic> toJsonWithMetadata() {
    final json = <String, dynamic>{
      'createdAt': createdAt.millisecondsSinceEpoch,
    };

    if (_metadata.isNotEmpty) {
      json['metadata'] = Map<String, dynamic>.from(_metadata);
    }

    return json;
  }

  /// Creates metadata from JSON representation.
  ///
  /// This should be called from your fromJson constructor if you're using
  /// toJsonWithMetadata(). It will extract and set the standard metadata
  /// fields.
  ///
  /// Example:
  /// ```dart
  /// factory UserActionEvent.fromJson(Map<String, dynamic> json) {
  ///   final event = UserActionEvent(
  ///     userId: json['userId'] as String,
  ///     action: json['action'] as String,
  ///   );
  ///
  ///   event.fromJsonWithMetadata(json);
  ///   return event;
  /// }
  /// ```
  void fromJsonWithMetadata(Map<String, dynamic> json) {
    if (json.containsKey('createdAt')) {
      _createdAt = DateTime.fromMillisecondsSinceEpoch(
        json['createdAt'] as int,
      );
    }

    if (json.containsKey('metadata')) {
      _metadata = Map<String, dynamic>.from(
        json['metadata'] as Map<String, dynamic>,
      );
    }
  }

  /// Returns a detailed string representation including metadata.
  @override
  String toString() {
    final buffer = StringBuffer('$runtimeType(')
      ..write('type: $type')
      ..write(', createdAt: $createdAt');

    if (_metadata.isNotEmpty) {
      buffer.write(', metadata: $_metadata');
    }

    final data = toJson();
    if (data.isNotEmpty) {
      buffer.write(', data: $data');
    }

    buffer.write(')');
    return buffer.toString();
  }

  /// Calculates a hash code that includes metadata.
  @override
  int get hashCode => Object.hash(
        super.hashCode,
        createdAt.millisecondsSinceEpoch,
        _deepHashCode(_metadata),
      );

  /// Deep hash code calculation for nested structures.
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

  /// Checks equality including metadata.
  @override
  bool operator ==(Object other) {
    if (!(super == other)) return false;
    if (other is! TypedEventMixin) return true; // Base equality passed

    return createdAt.millisecondsSinceEpoch ==
            other.createdAt.millisecondsSinceEpoch &&
        _deepEquals(_metadata, other._metadata);
  }

  /// Deep equality check for nested structures.
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
}
