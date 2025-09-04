# Gossip Event Sourcing

A framework-agnostic Dart library for implementing Event Sourcing and CQRS (Command Query Responsibility Segregation) patterns in distributed applications.

## Features

- **🚀 Event Processing**: Coordinate event processing through multiple projections
- **📊 Projections**: Build and maintain read models from events
- **💾 Projection Store**: Optional persistent storage for projection states (dramatically improves startup performance)
- **🔄 State Restoration**: Automatic state restoration with graceful fallbacks
- **🛡️ Version Compatibility**: Handle projection schema changes safely
- **🎯 Framework Agnostic**: Works with any Dart application, not just Flutter
- **📈 High Performance**: Optimized for large numbers of events

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  gossip_event_sourcing:
    path: ../gossip_event_sourcing  # Update path as needed
```

## Quick Start

### 1. Create a Projection

```dart
import 'package:gossip_event_sourcing/gossip_event_sourcing.dart';

class CounterProjection extends Projection with ProjectionChangeNotifier {
  int _count = 0;
  
  int get count => _count;

  @override
  Future<void> apply(Event event) async {
    if (event.payload['type'] == 'increment') {
      _count++;
      notifyListeners();
    } else if (event.payload['type'] == 'decrement') {
      _count--;
      notifyListeners();
    }
  }

  @override
  Future<void> reset() async {
    _count = 0;
    notifyListeners();
  }

  @override
  Map<String, dynamic> getState() {
    return {'count': _count};
  }

  @override
  Future<bool> restoreState(Map<String, dynamic> state) async {
    try {
      _count = state['count'] as int;
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }
}
```

### 2. Create a Projection Store (Optional)

```dart
class MyProjectionStore implements ProjectionStore {
  final Map<String, ProjectionStateSnapshot> _states = {};

  @override
  Future<void> initialize() async {
    // Initialize your storage backend
  }

  @override
  Future<void> saveProjectionState(
    String projectionType,
    Map<String, dynamic> state,
    String? lastProcessedEventId,
    int eventCount,
  ) async {
    _states[projectionType] = ProjectionStateSnapshot(
      projectionType: projectionType,
      state: state,
      lastProcessedEventId: lastProcessedEventId,
      eventCount: eventCount,
      savedAt: DateTime.now(),
      version: '1.0.0',
    );
  }

  @override
  Future<ProjectionStateSnapshot?> loadProjectionState(String projectionType) async {
    return _states[projectionType];
  }

  // Implement other methods...
}
```

### 3. Set Up Event Processing

```dart
void main() async {
  // Optional: Create projection store for better performance
  final projectionStore = MyProjectionStore();
  await projectionStore.initialize();

  // Create event processor
  final eventProcessor = EventProcessor(
    projectionStore: projectionStore,
    storeConfig: const ProjectionStoreConfig(),
    logger: print, // Optional: for debugging
  );

  // Register projections
  final counterProjection = CounterProjection();
  eventProcessor.registerProjection(counterProjection);

  // Listen to projection changes
  counterProjection.addListener(() {
    print('Counter is now: ${counterProjection.count}');
  });

  // Process events
  await eventProcessor.processEvent(MyEvent(
    id: '1',
    payload: {'type': 'increment'},
  ));
}
```

## Architecture

### Event Sourcing Flow

```
Events → EventProcessor → Projections → UI/API
    ↓
ProjectionStore (optional)
```

1. **Events** are processed through the `EventProcessor`
2. **Projections** build read models by applying events
3. **ProjectionStore** optionally saves projection states for fast startup
4. **UI/API** reads from projections for queries

### Performance Optimization

Without projection store:
```
App Start → Load All Events → Replay All Events → Ready
```

With projection store:
```
App Start → Load Saved States → Process Recent Events → Ready
```

## Configuration

### ProjectionStoreConfig Options

```dart
// Default (recommended)
const ProjectionStoreConfig()

// High performance (less frequent saves)
const ProjectionStoreConfig.highPerformance()

// Maximum durability (frequent saves)
const ProjectionStoreConfig.maxDurability()

// Disabled (no projection store)
const ProjectionStoreConfig.disabled()
```

### Custom Configuration

```dart
const ProjectionStoreConfig(
  autoSaveEnabled: true,
  autoSaveInterval: 100,     // Save every 100 events
  saveAfterBatch: true,      // Save after processing batches
  loadOnRebuild: true,       // Try loading on startup
)
```

## Best Practices

### 1. Projection Versioning

Always increment `stateVersion` when changing your projection's state format:

```dart
class MyProjection extends Projection {
  @override
  String get stateVersion => '2.0.0'; // Increment when breaking changes occur
  
  @override
  bool isStateCompatible(String savedVersion) {
    // Custom compatibility logic if needed
    return savedVersion == stateVersion;
  }
}
```

### 2. Error Handling

Make your `restoreState` method robust:

```dart
@override
Future<bool> restoreState(Map<String, dynamic> state) async {
  try {
    // Restore state logic
    return true;
  } catch (e) {
    // Log error and reset to clean state
    await reset();
    return false; // Falls back to event replay
  }
}
```

### 3. Testing

Test projections with and without saved states:

```dart
test('projection works with saved state', () async {
  final projection = MyProjection();
  
  // Test normal event processing
  await projection.apply(event);
  final state = projection.getState();
  
  // Test state restoration
  final newProjection = MyProjection();
  final restored = await newProjection.restoreState(state);
  
  expect(restored, isTrue);
  expect(newProjection.getState(), equals(state));
});
```

## Framework Integration

### Flutter Integration

```dart
// In your Flutter app
class MyProjection extends Projection with ProjectionChangeNotifier {
  // Your projection implementation
}

// Use with Provider or similar state management
ChangeNotifierProvider(
  create: (_) => counterProjection,
  child: MyApp(),
)
```

### Console Application

```dart
// In a console app
void main() async {
  final eventProcessor = EventProcessor(
    logger: (message) => print('[EventProcessor] $message'),
  );
  
  // Process events from any source
  await eventProcessor.processEvents(eventsFromDatabase);
}
```

## Advanced Usage

### Custom Event Types

Implement your own Event interface:

```dart
class MyEvent implements Event {
  @override
  final String id;
  
  @override
  final String nodeId;
  
  @override
  final int timestamp;
  
  @override
  final int creationTimestamp;
  
  @override
  final Map<String, dynamic> payload;
  
  MyEvent({
    required this.id,
    required this.nodeId,
    required this.timestamp,
    required this.creationTimestamp,
    required this.payload,
  });
}
```

### Multiple Projections

Register multiple projections for different views of the same data:

```dart
eventProcessor.registerProjection(UserListProjection());
eventProcessor.registerProjection(UserStatsProjection());
eventProcessor.registerProjection(AdminDashboardProjection());
```

### Monitoring

Get insights into your event processing:

```dart
final stats = eventProcessor.getProjectionStoreStats();
print('Total states: ${stats?.totalStates}');
print('Last save: ${stats?.lastSaveTime}');

print('Processed events: ${eventProcessor.processedEventCount}');
print('Active projections: ${eventProcessor.projections.length}');
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for your changes
4. Ensure all tests pass
5. Create a pull request

## License

MIT License - see LICENSE file for details.