/// Service responsible for vector clock management and persistence.
///
/// This service handles vector clock operations, state management,
/// and persistence to storage when available.
library;

import 'dart:async';

import '../../vector_clock.dart';
import '../../vector_clock_store.dart';

/// Service responsible for vector clock management and persistence.
class VectorClockService {
  final VectorClockStore? store;
  final String nodeId;
  late VectorClock _vectorClock;

  VectorClockService({
    required this.nodeId,
    this.store,
    VectorClock? initialClock,
  }) : _vectorClock = initialClock ?? VectorClock();

  /// Get the current vector clock.
  VectorClock get currentClock => _vectorClock;

  /// Initialize the service and load persisted state if available.
  Future<void> initialize() async {
    if (store != null) {
      await _loadVectorClockState();
    }
  }

  /// Increment the vector clock for this node.
  void increment() {
    _vectorClock.increment(nodeId);
  }

  /// Update the vector clock with a received clock.
  void update(VectorClock receivedClock) {
    _vectorClock.merge(receivedClock);
  }

  /// Save the current vector clock state to storage.
  Future<void> save() async {
    if (store != null) {
      await _saveVectorClockState();
    }
  }

  /// Perform garbage collection on the vector clock.
  ///
  /// For now, this is a no-op since VectorClock doesn't have built-in GC.
  /// In the future, we could implement logic to remove old nodes.
  Future<void> garbageCollect() async {
    // TODO: Implement garbage collection logic if needed
    await save();
  }

  /// Load vector clock state from storage.
  Future<void> _loadVectorClockState() async {
    if (store == null) return;

    try {
      final savedClock = await store!.loadVectorClock(nodeId);
      if (savedClock != null) {
        // Restore the saved state
        for (final entry in savedClock.summary.entries) {
          _vectorClock.setTimestampFor(entry.key, entry.value);
        }
      }
    } catch (e) {
      // If loading fails, continue with default vector clock
      // This could happen on first run or if storage is corrupted
    }
  }

  /// Save vector clock state to storage.
  Future<void> _saveVectorClockState() async {
    if (store == null) return;

    try {
      await store!.saveVectorClock(nodeId, _vectorClock);
    } catch (e) {
      // Log error but don't throw - vector clock state is recoverable
      // The node can continue operating even if persistence fails
    }
  }
}
