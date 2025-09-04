/// Interface for storing and loading projection states to avoid replaying all events
/// This is an optional performance optimization for large event stores
abstract class ProjectionStore {
  /// Initialize the projection store
  Future<void> initialize();

  /// Save the state of a projection with metadata about when it was saved
  /// [projectionType] - The type name of the projection
  /// [state] - The serialized state from projection.getState()
  /// [lastProcessedEventId] - The ID of the last event processed when this state was saved
  /// [eventCount] - The number of events that were processed to build this state
  Future<void> saveProjectionState(
    String projectionType,
    Map<String, dynamic> state,
    String? lastProcessedEventId,
    int eventCount,
  );

  /// Load the saved state of a projection if available
  /// Returns null if no saved state exists or if loading fails
  /// [projectionType] - The type name of the projection
  Future<ProjectionStateSnapshot?> loadProjectionState(String projectionType);

  /// Remove the saved state of a projection
  Future<void> clearProjectionState(String projectionType);

  /// Clear all saved projection states
  Future<void> clearAllProjectionStates();

  /// Get metadata about all saved projection states
  Future<List<ProjectionStateMetadata>> getAllProjectionMetadata();

  /// Check if a saved state exists for a projection
  Future<bool> hasProjectionState(String projectionType);

  /// Close the projection store
  Future<void> close();

  /// Get statistics about the projection store
  ProjectionStoreStats getStats();
}

/// Represents a saved projection state with metadata
class ProjectionStateSnapshot {
  final String projectionType;
  final Map<String, dynamic> state;
  final String? lastProcessedEventId;
  final int eventCount;
  final DateTime savedAt;
  final String version; // For schema versioning

  const ProjectionStateSnapshot({
    required this.projectionType,
    required this.state,
    required this.lastProcessedEventId,
    required this.eventCount,
    required this.savedAt,
    required this.version,
  });

  factory ProjectionStateSnapshot.fromJson(Map<String, dynamic> json) {
    return ProjectionStateSnapshot(
      projectionType: json['projectionType'] as String,
      state: Map<String, dynamic>.from(json['state'] as Map),
      lastProcessedEventId: json['lastProcessedEventId'] as String?,
      eventCount: json['eventCount'] as int,
      savedAt: DateTime.parse(json['savedAt'] as String),
      version: json['version'] as String? ?? '1.0.0',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'projectionType': projectionType,
      'state': state,
      'lastProcessedEventId': lastProcessedEventId,
      'eventCount': eventCount,
      'savedAt': savedAt.toIso8601String(),
      'version': version,
    };
  }
}

/// Metadata about a saved projection state (without the actual state data)
class ProjectionStateMetadata {
  final String projectionType;
  final String? lastProcessedEventId;
  final int eventCount;
  final DateTime savedAt;
  final String version;

  const ProjectionStateMetadata({
    required this.projectionType,
    required this.lastProcessedEventId,
    required this.eventCount,
    required this.savedAt,
    required this.version,
  });
}

/// Statistics about the projection store
class ProjectionStoreStats {
  final int totalProjections;
  final int totalStates;
  final DateTime? lastSaveTime;
  final Map<String, dynamic> additionalStats;

  const ProjectionStoreStats({
    required this.totalProjections,
    required this.totalStates,
    this.lastSaveTime,
    this.additionalStats = const {},
  });
}

/// Exception thrown by projection store operations
class ProjectionStoreException implements Exception {
  final String message;
  final Object? cause;

  const ProjectionStoreException(this.message, [this.cause]);

  @override
  String toString() => 'ProjectionStoreException: $message';
}
