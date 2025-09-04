# CRDT Extensions for Gossip Protocol Library

[![Pub Version](https://img.shields.io/pub/v/gossip_crdts.svg)](https://pub.dev/packages/gossip_crdts)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Dart library that extends the [gossip protocol library](https://github.com/da1nerd/gossip) with Conflict-free Replicated Data Types (CRDTs), enabling automatic conflict resolution and convergent state synchronization across distributed nodes.

## Features

- 🔀 **Seamless Integration**: Extends existing GossipNode instances with CRDT capabilities
- 🧮 **Multiple CRDT Types**: Counters, Sets, Registers, and Maps with conflict-free semantics
- 🔄 **Automatic Synchronization**: CRDTs sync automatically through the gossip protocol
- 🛡️ **Type Safety**: Strongly typed CRDT operations with compile-time guarantees
- 💾 **Pluggable Storage**: Abstract storage interface for different persistence backends
- 📊 **Event Streams**: Real-time notifications for CRDT operations and updates

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  gossip:
    git: https://github.com/da1nerd/gossip.git
  gossip_crdts:
    git: https://github.com/da1nerd/gossip-crdts.git
```

Then run:

```bash
dart pub get
```

## Quick Start

### Basic Usage with GossipNode

```dart
import 'package:gossip/gossip.dart';
import 'package:gossip_crdts/gossip_crdts.dart';

void main() async {
  // Create a regular gossip node
  final node = GossipNode(
    config: GossipConfig(nodeId: 'node1'),
    eventStore: MemoryEventStore(),
    transport: MyTransport(),
  );

  await node.start();

  // Enable CRDT support
  final crdtManager = await node.enableCRDTSupport();

  // Register and use a counter CRDT
  final counter = GCounter('page-views');
  await crdtManager.register(counter);

  await crdtManager.performOperation('page-views', 'increment', {'amount': 5});
  print('Counter value: ${counter.value}'); // Counter value: 5

  await node.stop();
}
```

### Using the Unified Interface

```dart
import 'package:gossip/gossip.dart';
import 'package:gossip_crdts/gossip_crdts.dart';

void main() async {
  // Create a gossip node with CRDT support
  final gossipNode = GossipNode(/* ... */);
  final crdtNode = await gossipNode.withCRDTSupport();

  await crdtNode.start();

  // Use both gossip and CRDT functionality
  await crdtNode.createEvent({'type': 'message', 'content': 'hello'});
  
  final counter = GCounter('likes');
  await crdtNode.registerCRDT(counter);
  await crdtNode.performCRDTOperation('likes', 'increment', {'amount': 1});

  await crdtNode.close();
}
```

### Simple Gossip Node Integration

```dart
import 'package:gossip/gossip.dart';
import 'package:gossip_crdts/gossip_crdts.dart';

void main() async {
  final gossipNode = GossipNode(/* ... */);
  final crdtNode = await gossipNode.withCRDTSupport();

  await crdtNode.initialize();
  await crdtNode.startGossiping();

  // Use CRDTs with gossip protocol
  final set = GSet<String>('user-tags');
  await crdtNode.registerCRDT(set);
  await crdtNode.performCRDTOperation('user-tags', 'add', {'element': 'music'});

  await crdtNode.close();
}
```

## Supported CRDT Types

### Counters

#### G-Counter (Grow-only Counter)
Perfect for metrics that only increase:

```dart
final counter = GCounter('page-views');
await crdtManager.register(counter);

// Only increment operations are supported
await crdtManager.performOperation('page-views', 'increment', {'amount': 1});
print(counter.value); // Always positive, monotonically increasing
```

#### PN-Counter (Increment/Decrement Counter)
Supports both increment and decrement operations:

```dart
final votes = PNCounter('vote-tally');
await crdtManager.register(votes);

// Both increment and decrement are supported
await crdtManager.performOperation('vote-tally', 'increment', {'amount': 5});
await crdtManager.performOperation('vote-tally', 'decrement', {'amount': 2});
print(votes.value); // 3
print('Upvotes: ${votes.totalPositive}, Downvotes: ${votes.totalNegative}');
```

### Sets

#### G-Set (Grow-only Set)
A set that can only have elements added:

```dart
final tags = GSet<String>('user-tags');
await crdtManager.register(tags);

await crdtManager.performOperation('user-tags', 'add', {'element': 'music'});
await crdtManager.performOperation('user-tags', 'add', {'element': 'sports'});

print(tags.value); // {'music', 'sports'}
print('Contains music: ${tags.contains('music')}'); // true
```

#### OR-Set (Observed-Remove Set)
A set that supports both add and remove operations:

```dart
final items = ORSet<String>('shopping-cart');
await crdtManager.register(items);

await crdtManager.performOperation('shopping-cart', 'add', {'element': 'apple'});
await crdtManager.performOperation('shopping-cart', 'add', {'element': 'banana'});
await crdtManager.performOperation('shopping-cart', 'remove', {'element': 'apple'});

print(items.value); // {'banana'}
```

### Registers

#### LWW-Register (Last-Writer-Wins Register)
A single-value register where the most recent update wins:

```dart
final status = LWWRegister<String>('user-status');
await crdtManager.register(status);

await crdtManager.performOperation('user-status', 'set', {
  'value': 'online',
  'timestamp': DateTime.now().millisecondsSinceEpoch,
});
print(status.value); // 'online'
```

#### MV-Register (Multi-Value Register)
A register that preserves concurrent updates:

```dart
final config = MVRegister<String>('app-theme');
await crdtManager.register(config);

// Concurrent updates are preserved
await crdtManager.performOperation('app-theme', 'set', {
  'value': 'dark',
  'vectorClock': {'node1': 1},
});
print(config.hasConflict); // true if concurrent updates exist
print(config.values); // Set of all concurrent values
```

### Maps

#### LWW-Map (Last-Writer-Wins Map)
A map where the most recent update wins for each key:

```dart
final settings = LWWMap<String, String>('user-settings');
await crdtManager.register(settings);

await crdtManager.performOperation('user-settings', 'put', {
  'key': 'theme',
  'value': 'dark',
  'timestamp': DateTime.now().millisecondsSinceEpoch,
});
print(settings['theme']); // 'dark'
```

#### OR-Map (Observed-Remove Map)
A map that supports both add and remove operations with CRDT values:

```dart
final counters = ORMap<String, GCounter>('user-counters', 
  crdtFactory: (id, type) => GCounter(id));
await crdtManager.register(counters);

await crdtManager.performOperation('user-counters', 'add', {
  'key': 'user1',
  'crdtType': 'GCounter',
  'crdtId': 'user1-counter'
});
```

### Sequences

#### RGA Array (Replicated Growable Array)
Perfect for collaborative text editing and ordered sequences:

```dart
final text = RGAArray<String>('shared-document');
await crdtManager.register(text);

// Insert characters for collaborative text editing
await crdtManager.performOperation('shared-document', 'insert', {
  'index': 0,
  'element': 'H',
});
await crdtManager.performOperation('shared-document', 'insert', {
  'index': 1,
  'element': 'i',
});

print(text.getText()); // 'Hi'
print(text.length); // 2

// Delete characters
await crdtManager.performOperation('shared-document', 'delete', {
  'index': 1,
});
print(text.getText()); // 'H'
```

### Flags

#### Enable-Wins Flag
A boolean flag where enable operations always win over disable operations:

```dart
final feature = EnableWinsFlag('feature-x-enabled');
await crdtManager.register(feature);

await crdtManager.performOperation('feature-x-enabled', 'enable', {});
print(feature.isEnabled); // true

// Even if another node disables concurrently, enable wins
await crdtManager.performOperation('feature-x-enabled', 'disable', {});
// After merge, flag remains enabled if any replica enabled it
```

## Event Streams and Monitoring

Subscribe to CRDT events for real-time updates:

```dart
// Listen to all CRDT operations
crdtManager.onOperation.listen((operationEvent) {
  print('Operation: ${operationEvent.operation.operation} '
        'on ${operationEvent.operation.crdtId} '
        'from ${operationEvent.source}');
});

// Listen to CRDT updates
crdtManager.onUpdate.listen((updateEvent) {
  print('CRDT ${updateEvent.crdtId} updated: ${updateEvent.type}');
});

// Listen to synchronization events
crdtManager.onSync.listen((syncEvent) {
  print('Sync ${syncEvent.type} with peer ${syncEvent.peerId}: '
        '${syncEvent.crdtCount} CRDTs');
});
```

## Custom Storage Backends

Implement custom storage for production use:

```dart
class DatabaseCRDTStore implements CRDTStore {
  final Database db;
  
  DatabaseCRDTStore(this.db);
  
  @override
  Future<void> saveCRDT(CRDT crdt) async {
    final state = crdt.getState();
    await db.execute('''
      INSERT OR REPLACE INTO crdts (id, type, state) 
      VALUES (?, ?, ?)
    ''', [crdt.id, crdt.type, jsonEncode(state)]);
  }
  
  @override
  Future<Map<String, dynamic>?> loadCRDTState(String crdtId) async {
    final result = await db.query('SELECT state FROM crdts WHERE id = ?', [crdtId]);
    if (result.isEmpty) return null;
    return jsonDecode(result.first['state']);
  }
  
  // Implement other methods...
}

// Use custom storage
final customStore = DatabaseCRDTStore(myDatabase);
final crdtManager = await node.enableCRDTSupport(crdtStore: customStore);
```

## Distributed Counter Example

Here's a complete example of multiple nodes collaborating on shared counters:

```dart
import 'package:gossip/gossip.dart';
import 'package:gossip_crdts/gossip_crdts.dart';

void main() async {
  // Create multiple nodes
  final nodes = <CRDTEnabledGossipNode>[];
  
  for (int i = 1; i <= 3; i++) {
    final gossipNode = GossipNode(
      config: GossipConfig(nodeId: 'node-$i'),
      eventStore: MemoryEventStore(),
      transport: MyTransport(),
    );
    
    final crdtNode = await gossipNode.withCRDTSupport();
    nodes.add(crdtNode);
    await crdtNode.start();
  }

  // Register shared counter on all nodes
  for (final node in nodes) {
    final counter = GCounter('shared-counter');
    await node.registerCRDT(counter);
  }

  // Each node increments the counter
  for (int i = 0; i < nodes.length; i++) {
    await nodes[i].performCRDTOperation(
      'shared-counter', 
      'increment', 
      {'amount': (i + 1) * 10}
    );
  }

  // Wait for synchronization
  await Future.delayed(Duration(seconds: 2));

  // All nodes should show the same total: 60 (10 + 20 + 30)
  for (final node in nodes) {
    final counter = node.getCRDT<GCounter>('shared-counter');
    print('${node.config.nodeId}: ${counter?.value}'); // All show 60
  }

  // Clean up
  for (final node in nodes) {
    await node.close();
  }
}
```

## Architecture

The CRDT extension follows a clean architecture that integrates seamlessly with the gossip protocol:

```
┌─────────────────────┐
│    Application      │
├─────────────────────┤
│  CRDTManager /      │
│  CRDTEnabledNode    │  ← CRDT coordination layer
├─────────────────────┤
│   GossipNode        │  ← Existing gossip protocol
├─────────────────────┤
│  CRDT Implementations │
│  - GCounter         │
│  - PNCounter        │  ← Individual CRDT types
│  - GSet             │
│  - ...              │
├─────────────────────┤
│   CRDTStore         │  ← Pluggable storage
└─────────────────────┘
```

## Best Practices

### Choosing CRDT Types

- **G-Counter**: Use for metrics that only increase (views, downloads, likes)
- **PN-Counter**: Use for values that can go up or down (votes, scores, inventory)
- **G-Set**: Use for collections that only grow (tags, features, flags)
- **OR-Set**: Use for collections that need both add and remove (shopping carts, user lists)
- **LWW-Register**: Use for single values where latest update should win (user status, configuration)
- **MV-Register**: Use when you need to detect and handle concurrent updates manually
- **LWW-Map**: Use for key-value storage where latest update per key should win
- **OR-Map**: Use for maps with CRDT values that need add/remove operations
- **RGA Array**: Use for collaborative text editing and ordered sequences
- **Enable-Wins Flag**: Use for boolean flags where "enabled" should dominate

### Performance Considerations

- **Operation Frequency**: Higher operation frequency requires more network bandwidth
- **CRDT Size**: Large CRDTs take more time to synchronize
- **Network Partitions**: CRDTs handle partitions gracefully but may have temporary inconsistencies

### Error Handling

```dart
try {
  await crdtManager.performOperation('my-counter', 'increment', {'amount': 5});
} on CRDTException catch (e) {
  print('CRDT operation failed: ${e.message}');
  // Handle CRDT-specific errors
} on GossipException catch (e) {
  print('Gossip operation failed: ${e.message}');
  // Handle gossip protocol errors
}
```

### Storage Recommendations

- **Development**: Use `MemoryCRDTStore` (no persistence)
- **Testing**: Use `MemoryCRDTStore` for clean test isolation
- **Production**: Implement custom storage backend with proper persistence

## Testing

Run the test suite:

```bash
dart test
```

The test suite includes:
- Unit tests for all CRDT implementations
- Integration tests with the gossip protocol
- Storage backend tests
- Convergence property tests

## Examples

See the `/example` directory for complete working examples:

- **Collaborative Counter**: Multiple nodes incrementing shared counters
- **Distributed Set**: Nodes adding elements to shared sets
- **Chat Application**: Real-time chat using CRDTs for message ordering

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-crdt-type`)
3. Add tests for your changes
4. Ensure all tests pass (`dart test`)
5. Commit your changes (`git commit -am 'Add new CRDT type'`)
6. Push to the branch (`git push origin feature/new-crdt-type`)
7. Create a Pull Request

## Roadmap

- [x] **OR-Set**: Observed-Remove Set with add and remove operations ✓
- [x] **LWW-Register**: Last-Writer-Wins Register for single values ✓
- [x] **MV-Register**: Multi-Value Register preserving concurrent updates ✓
- [x] **OR-Map**: Observed-Remove Map with CRDT values ✓
- [x] **LWW-Map**: Last-Writer-Wins Map for key-value storage ✓
- [x] **RGA Array**: Replicated Growable Array for collaborative text editing ✓
- [x] **Enable-Wins Flag**: Boolean flag CRDT for feature toggles ✓
- [ ] **Sequence CRDT**: Generic ordered sequence operations
- [ ] **Causal Tree**: Alternative text editing CRDT
- [ ] **File-based Storage**: Built-in file system storage backend
- [ ] **Compression**: Optional compression for large CRDT states
- [ ] **Delta Synchronization**: Send only changes instead of full state
- [ ] **CRDT Factory Registry**: Automatic CRDT reconstruction from state

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## References

- [A comprehensive study of CRDTs](https://hal.inria.fr/inria-00555588/document)
- [Conflict-Free Replicated Data Types](https://en.wikipedia.org/wiki/Conflict-free_replicated_data_type)
- [The gossip protocol library](https://github.com/da1nerd/gossip)
- [Strong Eventual Consistency and CRDTs](https://queue.acm.org/detail.cfm?id=2462076)