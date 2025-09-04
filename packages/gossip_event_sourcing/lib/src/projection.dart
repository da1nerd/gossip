import 'package:gossip/gossip.dart';

/// Base class for all projections (read models).
/// Projections build and maintain UI state from events.
abstract class Projection {
  /// Apply an event to update this projection's state
  Future<void> apply(Event event);

  /// Reset the projection to initial state
  Future<void> reset();

  /// Get the current state of this projection
  Map<String, dynamic> getState();

  /// Restore the projection to a previously saved state
  /// This is used by the projection store to quickly restore state
  /// without replaying all events from the beginning.
  ///
  /// Implementations should:
  /// 1. Validate that the state format is compatible
  /// 2. Reset to initial state first
  /// 3. Restore all internal state from the provided data
  /// 4. Notify listeners if using change notification
  ///
  /// Returns true if restoration was successful, false otherwise.
  /// If false is returned, the projection will fall back to event replay.
  Future<bool> restoreState(Map<String, dynamic> state) async {
    // Default implementation - subclasses should override this
    // if they want to support projection store optimization
    return false;
  }

  /// Get the version of this projection's state schema
  /// This is used to ensure compatibility when loading saved states
  /// Increment this version when making breaking changes to getState() format
  String get stateVersion => '1.0.0';

  /// Check if a saved state is compatible with this projection
  /// Override this if you need custom compatibility logic
  bool isStateCompatible(String savedVersion) {
    return savedVersion == stateVersion;
  }

  /// Dispose any resources used by this projection
  void dispose() {
    // Override in subclasses if needed
  }
}

/// Simple change notifier mixin for projections that need to notify listeners
/// This is framework-agnostic and doesn't depend on Flutter's ChangeNotifier
mixin ProjectionChangeNotifier on Projection {
  final List<void Function()> _listeners = [];

  /// Add a listener that will be called when the projection state changes
  void addListener(void Function() listener) => _listeners.add(listener);

  /// Remove a previously added listener
  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// Notify all listeners that the projection state has changed
  void notifyListeners() {
    for (final listener in _listeners) {
      try {
        listener();
      } catch (e) {
        // Continue notifying other listeners even if one throws
        // In production, you might want to log this error
      }
    }
  }

  @override
  void dispose() {
    _listeners.clear();
    super.dispose();
  }
}
