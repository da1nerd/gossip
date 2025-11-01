import '../../event.dart';
import '../../event_store.dart';
import '../../gossip_event_message.dart';
import '../../gossip_peer.dart';
import '../../vector_clock.dart';
import '../services/vector_clock_service.dart';
import '../../domain/policies/event_admission_policy.dart';

/// Use case for handling incoming gossip events.
///
/// Orchestrates the pure domain admission policy with persistence and
/// vector clock advancement. The domain remains fully pure and typed,
/// while this use case performs the necessary I/O.
class HandleIncomingEventsUseCase {
  final EventStore eventStore;
  final VectorClockService vectorClockService;

  HandleIncomingEventsUseCase({
    required this.eventStore,
    required this.vectorClockService,
  });

  /// Process a batch of incoming events:
  /// - Filters out events we already have (via EventAdmissionPolicy)
  /// - Persists newly accepted events
  /// - Advances the local vector clock based on accepted events
  /// - Returns the list of newly received events enriched with metadata
  Future<List<ReceivedEvent>> execute({
    required GossipEventMessage message,
    required GossipPeer fromPeer,
    required DateTime now,
  }) async {
    // Build a set of known event IDs (simple per-id check; can be optimized with batch APIs).
    final knownIds = <String>{};
    for (final e in message.events) {
      if (await eventStore.hasEvent(e.id)) {
        knownIds.add(e.id);
      }
    }

    // Pure domain decision: which events to accept and the vector-clock delta.
    final admission = EventAdmissionPolicy.admit(
      incoming: message.events,
      knownEventIds: knownIds,
    );

    // Persist accepted events.
    for (final e in admission.toPersist) {
      await eventStore.saveEvent(e);
    }

    // Advance vector clock using the delta produced by the domain policy.
    final delta = VectorClock();
    for (final entry in admission.delta.byNode.entries) {
      delta.setTimestampFor(entry.key.value, entry.value);
    }
    vectorClockService.update(delta);
    await vectorClockService.save();

    // Return enriched records for higher layers to consume.
    return [
      for (final e in admission.toPersist)
        ReceivedEvent(event: e, fromPeer: fromPeer, receivedAt: now),
    ];
  }
}
