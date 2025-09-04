/// Event Sourcing and CQRS library for Dart applications
///
/// This library provides the core components for implementing Event Sourcing
/// and Command Query Responsibility Segregation (CQRS) patterns in distributed
/// applications built on the Gossip protocol.
///
/// Key components:
/// - [EventProcessor]: Coordinates event processing to projections
/// - [Projection]: Base class for read models
/// - [ProjectionStore]: Interface for persistent projection state storage
///
/// Example usage:
/// ```dart
/// // Create a custom projection store implementation
/// final projectionStore = MyProjectionStore();
/// await projectionStore.initialize();
///
/// // Create event processor
/// final eventProcessor = EventProcessor(
///   projectionStore: projectionStore,
///   storeConfig: const ProjectionStoreConfig(),
/// );
///
/// // Create and register your projections
/// final myProjection = MyProjection();
/// eventProcessor.registerProjection(myProjection);
///
/// // Process events
/// await eventProcessor.processEvent(event);
/// ```
library gossip_event_sourcing;

export 'src/event_processor.dart';
export 'src/projection.dart';
export 'src/projection_store.dart';
