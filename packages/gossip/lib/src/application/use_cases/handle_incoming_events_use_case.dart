import 'package:gossip/src/event.dart';
import 'package:gossip/src/event_store.dart';
import 'package:gossip/src/gossip_event_message.dart';
import 'package:gossip/src/gossip_peer.dart';
import 'package:gossip/src/vector_clock.dart';
import 'package:gossip/src/application/services/vector_clock_service.dart';
import 'package:gossip/src/domain/policies/event_admission_policy.dart';

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
    final knownIds = await _collectKnownIds(message);
    final admission = _admit(message, knownIds);
    await _persistAccepted(admission);
    await _advanceClock(admission);
    return _buildReceivedEvents(admission, fromPeer, now);
  }

  // Collect known event IDs to avoid re-persisting duplicates.
  Future<Set<String>> _collectKnownIds(GossipEventMessage message) async {
    final knownIds = <String>{};
    for (final e in message.events) {
      if (await eventStore.hasEvent(e.id)) {
        knownIds.add(e.id);
      }
    }
    return knownIds;
  }

  // Decide which events to accept using the domain policy.
  AdmissionResult _admit(GossipEventMessage message, Set<String> knownIds) {
    return EventAdmissionPolicy.admit(
      incoming: message.events,
      knownEventIds: knownIds,
    );
  }

  // Persist newly accepted events.
  Future<void> _persistAccepted(AdmissionResult admission) async {
    for (final e in admission.toPersist) {
      await eventStore.saveEvent(e);
    }
  }

  // Advance our vector clock based on the domain-produced delta.
  Future<void> _advanceClock(AdmissionResult admission) async {
    final delta = VectorClock();
    for (final entry in admission.delta.byNode.entries) {
      delta.setTimestampFor(entry.key.value, entry.value);
    }
    vectorClockService.update(delta);
    await vectorClockService.save();
  }

  // Build enriched ReceivedEvent records for higher layers.
  List<ReceivedEvent> _buildReceivedEvents(
    AdmissionResult admission,
    GossipPeer fromPeer,
    DateTime now,
  ) {
    return [
      for (final e in admission.toPersist)
        ReceivedEvent(event: e, fromPeer: fromPeer, receivedAt: now),
    ];
  }
}
