![Alt text](images/logo.png)

  # Gossip Protocol Library for Dart

  A Dart library for implementing gossip-based distributed event synchronization. This library provides the core logic for gossip protocols, allowing nodes to exchange and synchronize events in a distributed system while remaining transport-agnostic.
</div>

## Features

- 🔄 **Event-based gossip protocol** with vector clock causality tracking
- 🔌 **Transport-agnostic design** - bring your own networking layer
- 💾 **Pluggable storage backends** via abstract interfaces
- ⚙️ **Configurable gossip behavior** and timing parameters
- 🛡️ **Built-in duplicate detection** and event ordering
- 📊 **Event statistics** and monitoring capabilities
- 🎯 **Peer selection strategies** (random, round-robin, least-recent, most-reliable)
- 🔧 **Anti-entropy mechanisms** for enhanced consistency

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  gossip:
    git: https://github.com/da1nerd/gossip.git
```

Then run:

```bash
dart pub get
```

## Quick Start

### Basic Usage

```dart
import 'package:gossip/gossip.dart';

// Create a gossip node with configuration
final config = GossipConfig(
  nodeId: 'node-1',
  gossipInterval: Duration(seconds: 1),
  fanout: 3,
);

final node = GossipNode(
  config: config,
  eventStore: MemoryEventStore(),
  transport: YourTransportImplementation(),
);

// Start the node
await node.start();

// Create and broadcast events
await node.createEvent({
  'type': 'user_action',
  'action': 'login',
  'user': 'alice',
});

// Add peers
node.addPeer(GossipPeer(
  id: 'node-2',
  address: 'http://node2.example.com:8080',
));

// Listen to events
node.onEventReceived.listen((event) {
  print('Received: ${event.payload} from ${event.nodeId}');
});
```

### Transport Implementation

The library is transport-agnostic. You need to implement the `GossipTransport` interface:

```dart
class HttpTransport implements GossipTransport {
  @override
  Future<void> initialize() async {
    // Set up HTTP server/client
  }

  @override
  Future<GossipDigestResponse> sendDigest(
    GossipPeer peer,
    GossipDigest digest, {
    Duration? timeout,
  }) async {
    // Send HTTP request with digest
    // Return peer's response
  }

  // Implement other methods...
}
```

### Custom Event Store

Implement your own storage backend:

```dart
class DatabaseEventStore implements EventStore {
  @override
  Future<void> saveEvent(Event event) async {
    // Save to your database
  }

  @override
  Future<List<Event>> getEventsSince(
    String nodeId,
    int afterTimestamp, {
    int? limit,
  }) async {
    // Query your database
  }

  // Implement other methods...
}
```

## Core Concepts

### Events

Events are the fundamental unit of data synchronized across nodes:

```dart
final event = Event(
  id: 'unique-event-id',
  nodeId: 'originating-node',
  timestamp: 42,  // Logical timestamp from vector clock
  creationTimestamp: 1640995200000,  // Wall-clock time
  payload: {'user': 'alice', 'action': 'login'},
);
```

### Vector Clocks

Vector clocks track causality between events across distributed nodes:

```dart
final clock = VectorClock();
clock.increment('node-1');  // Increment local timestamp
clock.merge(otherClock);    // Merge knowledge from another node

// Compare clocks for causality
final relationship = clock.compareTo(otherClock);
// Returns: ClockComparison.before, .after, .concurrent, or .equal
```

### Gossip Protocol

The library implements a 3-phase gossip protocol:

1. **Digest Exchange**: Node A sends its vector clock summary to Node B
2. **Event Exchange**: Node B responds with missing events and requests
3. **Final Sync**: Node A sends the requested events to Node B

## Configuration Options

### Basic Configuration

```dart
final config = GossipConfig(
  nodeId: 'my-node',
  gossipInterval: Duration(seconds: 1),    // How often to gossip
  fanout: 3,                               // Number of peers per round
  gossipTimeout: Duration(seconds: 10),    // Timeout for exchanges
  maxEventsPerMessage: 100,                // Batch size limit
  maxMessageSizeBytes: 1024 * 1024,        // 1MB message limit
);
```

### Preset Configurations

```dart
// High-throughput configuration
final config = GossipConfig.highThroughput(
  nodeId: 'fast-node',
  gossipInterval: Duration(milliseconds: 500),
  fanout: 5,
);

// Low-resource configuration
final config = GossipConfig.lowResource(
  nodeId: 'resource-constrained',
  gossipInterval: Duration(seconds: 5),
  fanout: 2,
);
```

### Peer Selection Strategies

```dart
final config = GossipConfig(
  nodeId: 'my-node',
  peerSelectionStrategy: PeerSelectionStrategy.random,
  // Options: random, roundRobin, leastRecentlyContacted, mostReliable
);
```

## Advanced Features

### Event Streams

Subscribe to various event streams for monitoring and integration:

```dart
// Events created by this node
node.onEventCreated.listen((event) {
  print('Created: ${event.payload}');
});

// Events received from other nodes
node.onEventReceived.listen((event) {
  print('Received: ${event.payload} from ${event.nodeId}');
});

// Peer management
node.onPeerAdded.listen((peer) {
  print('Peer added: ${peer.id}');
});

// Gossip exchange results
node.onGossipExchange.listen((result) {
  print('Exchange with ${result.peer.id}: '
        '${result.success ? 'SUCCESS' : 'FAILED'}');
});
```

### Manual Gossip Triggers

```dart
// Trigger gossip with random peers
await node.gossip();

// Gossip with specific peer
final peer = GossipPeer(id: 'node-2', address: 'http://node2:8080');
final result = await node.gossipWith(peer);

print('Exchanged ${result.eventsExchanged} events in ${result.duration}');
```

### Event Store Statistics

```dart
final stats = await eventStore.getStats();
print('Total events: ${stats.totalEvents}');
print('Unique nodes: ${stats.uniqueNodes}');
print('Size: ${stats.sizeInBytes} bytes');
```

## Examples

See the `/example` directory for complete working examples:

- **Simple Example**: Basic three-node gossip network with in-memory transport
- **HTTP Transport**: RESTful HTTP-based transport implementation
- **Database Storage**: PostgreSQL-backed event storage
- **Monitoring**: Integration with metrics and logging systems

## Architecture

The library follows a modular architecture:

```
┌─────────────────┐
│   Application   │
├─────────────────┤
│   GossipNode    │  ← Main coordination logic
├─────────────────┤
│ EventStore │ Transport │  ← Pluggable backends
├─────────────────┤
│ VectorClock │ Event │  ← Core data structures
└─────────────────┘
```

## Best Practices

### Network Transport

- Implement proper timeout handling
- Use connection pooling for HTTP transports
- Handle network partitions gracefully
- Implement exponential backoff for retries

### Storage Backend

- Use transactions for consistency
- Implement proper indexing for timestamp queries
- Consider event retention policies
- Monitor storage growth

### Configuration

- Tune `gossipInterval` based on network conditions
- Set `fanout` to 3-5 for optimal convergence
- Configure `maxEventsPerMessage` based on network MTU
- Enable anti-entropy for critical consistency requirements

### Error Handling

```dart
try {
  await node.createEvent({'data': 'important'});
} on InvalidEventException catch (e) {
  print('Event creation failed: ${e.message}');
} on NodeNotInitializedException catch (e) {
  print('Node not ready: ${e.message}');
}
```

## Testing

Run tests with:

```bash
dart test
```

The test suite includes:
- Unit tests for all core components
- Integration tests with mock transport
- Property-based tests for vector clock operations
- Performance benchmarks

## Performance Characteristics

- **Convergence Time**: O(log N) rounds for N nodes
- **Message Complexity**: O(fanout) messages per round per node
- **Memory Usage**: O(events × nodes) for vector clocks
- **Network Bandwidth**: Configurable via message size limits

## Contributing

1. Fork the repository at https://github.com/da1nerd/gossip
2. Create a feature branch (`git checkout -b feature/awesome-feature`)
3. Add tests for your changes
4. Ensure all tests pass (`dart test`)
5. Commit your changes (`git commit -am 'Add awesome feature'`)
6. Push to the branch (`git push origin feature/awesome-feature`)
7. Create a Pull Request on GitHub

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## References

- [Epidemic Algorithms for Replicated Database Maintenance](https://dl.acm.org/doi/10.1145/41840.41841)
- [Vector Clocks](https://en.wikipedia.org/wiki/Vector_clock)
- [Gossip Protocols](https://en.wikipedia.org/wiki/Gossip_protocol)
- [Amazon's Dynamo Paper](https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf)
