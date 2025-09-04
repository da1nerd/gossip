# Vector Clock Persistence in Gossip Protocol

## Overview

This document describes the vector clock persistence feature in the Gossip Protocol Library. This feature ensures that vector clocks survive node restarts, maintaining causality guarantees that are fundamental to distributed systems correctness.

## Problem Statement

### Why Vector Clock Persistence is Critical

Vector clocks track the "happens-before" relationship between events in distributed systems. Without persistence:

- **Causality Violations**: Restarted nodes lose their logical time, breaking event ordering
- **Data Inconsistency**: Events may appear to happen in the wrong order
- **Lost History**: Knowledge of other nodes' states is reset
- **Synchronization Issues**: Nodes can't properly determine which events they're missing

### Impact of Vector Clock Loss

When a node restarts without persisting its vector clock:

```
Before Restart: Node A at timestamp 100, knows Node B at timestamp 50
After Restart:  Node A at timestamp 0, knows nothing about other nodes
Result:        Causality chain is broken, sync problems occur
```

## Solution: Vector Clock Persistence

### Core Concept

The solution persists vector clock state across node restarts:

1. **Save on Updates**: Vector clock is saved after each increment or merge
2. **Load on Startup**: Previously saved state is restored when node starts
3. **Maintain Causality**: Logical time continues from where it left off

### Architecture

```
┌─────────────────┐
│   GossipNode    │
│                 │
│ ┌─────────────┐ │    ┌──────────────────┐
│ │ VectorClock │ │───▶│ VectorClockStore │
│ └─────────────┘ │    │                  │
└─────────────────┘    │ - Memory         │
                       │ - File           │
                       │ - Database       │
                       │ - Custom         │
                       └──────────────────┘
```

## Usage

### Basic Setup

```dart
import 'package:gossip/gossip.dart';

// Create a vector clock store (file-based persistence)
final vectorClockStore = FileVectorClockStore('./vector_clocks');

// Create gossip node with persistence
final node = GossipNode(
  config: GossipConfig(nodeId: 'node-1'),
  eventStore: MemoryEventStore(),
  transport: MyTransport(),
  vectorClockStore: vectorClockStore, // Enable persistence
);

await node.start();
// Vector clock state is automatically loaded on startup

await node.createEvent({'data': 'test'});
// Vector clock state is automatically saved after updates
```

### Without Persistence (Optional)

```dart
// Vector clock persistence is optional
final node = GossipNode(
  config: GossipConfig(nodeId: 'node-1'),
  eventStore: MemoryEventStore(),
  transport: MyTransport(),
  // No vectorClockStore - runs without persistence
);
```

### File-Based Persistence

```dart
// Persists vector clocks to JSON files
final fileStore = FileVectorClockStore('./my_vector_clocks');

final node = GossipNode(
  config: GossipConfig(nodeId: 'node-1'),
  eventStore: eventStore,
  transport: transport,
  vectorClockStore: fileStore,
);
```

**File Structure:**
```
my_vector_clocks/
├── node-1.json
├── node-2.json
└── node-3.json
```

**Example JSON Content:**
```json
{
  "node-1": 42,
  "node-2": 15,
  "node-3": 8
}
```

### Memory-Based Persistence

```dart
// In-memory persistence (for testing/development)
final memoryStore = MemoryVectorClockStore();

final node = GossipNode(
  config: GossipConfig(nodeId: 'node-1'),
  eventStore: eventStore,
  transport: transport,
  vectorClockStore: memoryStore,
);
```

**Note**: Memory-based persistence doesn't survive process restarts. Use for testing or single-session scenarios.

## Storage Backends

### Built-in Implementations

#### 1. MemoryVectorClockStore

- **Use Case**: Testing, development, single-session scenarios
- **Persistence**: No (data lost on process exit)
- **Performance**: Very fast
- **Thread Safety**: Yes

```dart
final store = MemoryVectorClockStore();
```

#### 2. FileVectorClockStore

- **Use Case**: Production deployments with file system access
- **Persistence**: Yes (survives restarts)
- **Performance**: Good for moderate update rates
- **Thread Safety**: Yes (file locking)

```dart
final store = FileVectorClockStore('./vector_clocks');
```

### Custom Implementations

Implement the `VectorClockStore` interface for custom backends:

```dart
class DatabaseVectorClockStore implements VectorClockStore {
  final DatabaseConnection db;
  
  DatabaseVectorClockStore(this.db);
  
  @override
  Future<void> saveVectorClock(String nodeId, VectorClock vectorClock) async {
    await db.execute('''
      INSERT OR REPLACE INTO vector_clocks (node_id, clock_data) 
      VALUES (?, ?)
    ''', [nodeId, jsonEncode(vectorClock.toJson())]);
  }
  
  @override
  Future<VectorClock?> loadVectorClock(String nodeId) async {
    final result = await db.query('''
      SELECT clock_data FROM vector_clocks WHERE node_id = ?
    ''', [nodeId]);
    
    if (result.isEmpty) return null;
    
    final json = jsonDecode(result.first['clock_data']);
    return VectorClock.fromJson(json);
  }
  
  // Implement other required methods...
}
```

## API Reference

### VectorClockStore Interface

```dart
abstract class VectorClockStore {
  /// Saves vector clock state for a node
  Future<void> saveVectorClock(String nodeId, VectorClock vectorClock);
  
  /// Loads vector clock state for a node (returns null if not found)
  Future<VectorClock?> loadVectorClock(String nodeId);
  
  /// Checks if vector clock state exists for a node
  Future<bool> hasVectorClock(String nodeId);
  
  /// Deletes vector clock state for a node
  Future<bool> deleteVectorClock(String nodeId);
  
  /// Closes the store and releases resources
  Future<void> close();
}
```

### Error Handling

```dart
try {
  await vectorClockStore.saveVectorClock('node-1', vectorClock);
} on VectorClockStoreException catch (e) {
  print('Persistence failed: ${e.message}');
  // Handle error appropriately
}
```

## Best Practices

### 1. Choose Appropriate Storage Backend

**For Production:**
- Use `FileVectorClockStore` or custom database implementation
- Ensure storage location is persistent and backed up
- Consider performance requirements for your update rate

**For Development:**
- `MemoryVectorClockStore` is fine for testing
- Use file-based for integration testing

**For Testing:**
- `MemoryVectorClockStore` provides clean isolation between tests
- Easy setup and teardown

### 2. Error Handling Strategy

```dart
final node = GossipNode(
  config: config,
  eventStore: eventStore,
  transport: transport,
  vectorClockStore: reliableStore, // Implement retry logic
);

class ReliableVectorClockStore implements VectorClockStore {
  final VectorClockStore _delegate;
  final int _maxRetries;
  
  ReliableVectorClockStore(this._delegate, this._maxRetries);
  
  @override
  Future<void> saveVectorClock(String nodeId, VectorClock vectorClock) async {
    for (int i = 0; i < _maxRetries; i++) {
      try {
        await _delegate.saveVectorClock(nodeId, vectorClock);
        return;
      } catch (e) {
        if (i == _maxRetries - 1) rethrow;
        await Future.delayed(Duration(milliseconds: 100 * (i + 1)));
      }
    }
  }
  
  // Implement other methods with similar retry logic...
}
```

### 3. Storage Location Planning

```dart
// Good: Persistent, backed up location
final store = FileVectorClockStore('/var/lib/myapp/vector_clocks');

// Bad: Temporary directory that may be cleaned up
final store = FileVectorClockStore('/tmp/vector_clocks');
```

### 4. Monitoring and Observability

```dart
class InstrumentedVectorClockStore implements VectorClockStore {
  final VectorClockStore _delegate;
  final Metrics _metrics;
  
  InstrumentedVectorClockStore(this._delegate, this._metrics);
  
  @override
  Future<void> saveVectorClock(String nodeId, VectorClock vectorClock) async {
    final stopwatch = Stopwatch()..start();
    try {
      await _delegate.saveVectorClock(nodeId, vectorClock);
      _metrics.recordSuccess('vector_clock_save', stopwatch.elapsed);
    } catch (e) {
      _metrics.recordError('vector_clock_save', e);
      rethrow;
    }
  }
  
  // Similar instrumentation for other methods...
}
```

## Migration Guide

### Upgrading Existing Deployments

1. **Add Vector Clock Store**: Update node configuration to include persistence
2. **Gradual Rollout**: Deploy to nodes one at a time
3. **Monitor**: Watch for any persistence-related errors
4. **Validate**: Verify vector clocks are being saved and loaded correctly

```dart
// Before (no persistence)
final node = GossipNode(
  config: config,
  eventStore: eventStore,
  transport: transport,
);

// After (with persistence)
final node = GossipNode(
  config: config,
  eventStore: eventStore,
  transport: transport,
  vectorClockStore: FileVectorClockStore('./vector_clocks'), // Added
);
```

### Backward Compatibility

- Vector clock persistence is **optional** - existing code continues to work
- No breaking changes to existing APIs
- Gradual adoption possible

## Performance Considerations

### Persistence Frequency

Vector clocks are persisted:
- After creating new events
- After receiving events from other nodes
- After gossip digest exchanges

### Optimization Strategies

1. **Batch Updates**: Group multiple vector clock updates
2. **Async Persistence**: Don't block event processing on persistence
3. **Compression**: Use compact JSON encoding for large vector clocks
4. **Caching**: Keep recently accessed vector clocks in memory

### Storage Size Estimation

For a network with N nodes, each creating E events:
- Vector clock size: ~8 bytes per node entry
- Storage per node: N × 8 bytes + JSON overhead
- Example: 100 nodes = ~1KB per vector clock file

## Troubleshooting

### Common Issues

**Q: Vector clock not restored on restart**
A: Check file permissions and storage location accessibility

**Q: Performance degradation with file storage**
A: Consider using faster storage or implementing custom database backend

**Q: Persistence errors during operation**
A: Implement retry logic and monitor disk space/permissions

**Q: Vector clock files growing too large**
A: Implement cleanup strategies for nodes that permanently leave the network

### Debugging

Enable detailed logging:

```dart
// Custom store with logging
class LoggingVectorClockStore implements VectorClockStore {
  final VectorClockStore _delegate;
  final Logger _logger;
  
  LoggingVectorClockStore(this._delegate, this._logger);
  
  @override
  Future<void> saveVectorClock(String nodeId, VectorClock vectorClock) async {
    _logger.info('Saving vector clock for $nodeId: $vectorClock');
    await _delegate.saveVectorClock(nodeId, vectorClock);
    _logger.info('Successfully saved vector clock for $nodeId');
  }
  
  // Similar logging for other methods...
}
```

### Validation Commands

Check vector clock files:

```bash
# List all vector clock files
ls -la ./vector_clocks/

# Check file content
cat ./vector_clocks/node-1.json

# Validate JSON format
python -m json.tool ./vector_clocks/node-1.json
```

## Testing

### Unit Tests

Test vector clock persistence in isolation:

```dart
test('vector clock survives node restart', () async {
  final store = MemoryVectorClockStore();
  
  // Create and save vector clock
  final originalClock = VectorClock()..setTimestampFor('node-1', 5);
  await store.saveVectorClock('node-1', originalClock);
  
  // Load and verify
  final loadedClock = await store.loadVectorClock('node-1');
  expect(loadedClock!.getTimestampFor('node-1'), equals(5));
});
```

### Integration Tests

Test with real gossip nodes:

```dart
test('causality maintained across restart', () async {
  final store = FileVectorClockStore('./test_clocks');
  
  // First node instance
  final node1 = GossipNode(
    config: GossipConfig(nodeId: 'test'),
    eventStore: MemoryEventStore(),
    transport: MockTransport(),
    vectorClockStore: store,
  );
  
  await node1.start();
  await node1.createEvent({'phase': 1});
  await node1.stop();
  
  // Second node instance (restart simulation)
  final node2 = GossipNode(
    config: GossipConfig(nodeId: 'test'),
    eventStore: MemoryEventStore(),
    transport: MockTransport(),
    vectorClockStore: store,
  );
  
  await node2.start();
  
  // Vector clock should continue from previous state
  expect(node2.vectorClock.getTimestampFor('test'), equals(1));
});
```

## Security Considerations

### File Storage Security

- **Permissions**: Ensure vector clock files are not world-readable
- **Location**: Store in secure directory with appropriate access controls
- **Backup**: Include vector clock state in backup/recovery procedures

### Data Integrity

- **Checksums**: Consider adding integrity checks to detect corruption
- **Validation**: Validate loaded vector clock data before use
- **Recovery**: Implement fallback strategies for corrupted data

---

*Vector clock persistence is essential for maintaining causality guarantees in production distributed systems. This feature ensures that the logical time relationships between events are preserved across node restarts, preventing synchronization issues and maintaining system consistency.*