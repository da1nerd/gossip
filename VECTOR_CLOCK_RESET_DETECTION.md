# Vector Clock Reset Detection in Gossip Protocol

## Overview

This document describes the vector clock reset detection feature implemented in the Gossip Protocol Library. This feature solves a critical synchronization problem that occurs when nodes in a distributed system lose their vector clock state and restart with fresh clocks.

## Problem Statement

### The Vector Clock Reset Problem

In distributed gossip protocols, vector clocks track the logical ordering of events across nodes. However, when a node experiences certain failures, its vector clock can be reset, leading to synchronization issues:

1. **Normal Operation**: Node A creates events with timestamps 1, 2, 3, ..., 100
2. **Node Goes Offline**: Node A becomes unavailable (crash, network partition, etc.)
3. **State Loss**: Node A loses its vector clock state (storage failure, restart without persistence)
4. **Vector Clock Reset**: Node A restarts with a fresh vector clock (timestamp starts at 0)
5. **New Events Created**: Node A creates new events with timestamps 1, 2, 3
6. **Synchronization Failure**: Other nodes think Node A is at timestamp 100, so they won't request the new events with lower timestamps 1, 2, 3

### Impact Without Detection

- **Data Loss**: New events created after a reset are never synchronized to other nodes
- **Inconsistent State**: Different nodes have different views of the distributed state
- **Silent Failures**: The problem is not immediately apparent, making it difficult to detect

## Solution: Vector Clock Reset Detection

### Detection Strategy

The solution detects vector clock resets by identifying **timestamp regression**:

```
Before Reset: Other nodes think Node A is at timestamp 100
After Reset:  Node A reports timestamp 3 (after creating 3 new events)
Detection:    3 < 100 → Reset detected
```

### Implementation Details

#### 1. Timestamp Regression Detection

When processing a gossip digest from a peer:

```dart
if (peerReportedTimestamp < ourKnownTimestamp) {
  // Reset detected - request ALL events from timestamp 0
  eventRequests[peerId] = 0;
}
```

#### 2. Selective Vector Clock Merging

Vector clocks are only updated with advancing timestamps:

```dart
// Only merge higher timestamps, ignore lower ones
for (final entry in theirClock.summary.entries) {
  final ourTimestamp = _vectorClock.getTimestampFor(entry.key);
  if (entry.value > ourTimestamp) {
    _vectorClock.setTimestampFor(entry.key, entry.value);
  }
  // Note: Lower timestamps are ignored (potential resets)
}
```

#### 3. Bidirectional Protection

The implementation also handles the reverse case where we might have reset:

```dart
if (ourTimestamp < peerReportedTimestamp) {
  // We might have reset - send our recent events
  final recentEvents = await getRecentEvents(nodeId);
  eventsToSend.addAll(recentEvents);
}
```

### Algorithm Flow

```
1. Receive gossip digest from Peer X
2. For each node Y in digest:
   a. Compare their timestamp vs our known timestamp for Y
   b. If their_timestamp > our_timestamp:
      → Normal case: Request events after our_timestamp
   c. If their_timestamp < our_timestamp:
      → Reset detected: Request ALL events from timestamp 0
   d. If their_timestamp == our_timestamp:
      → No action needed
3. Send appropriate event requests
4. Merge vector clock selectively (only advancing timestamps)
```

## Key Benefits

### 1. **Automatic Recovery**
- No manual intervention required
- Self-healing distributed system
- Graceful handling of node failures

### 2. **Safety First**
- False positives are safe (requesting extra events is harmless)
- Gossip protocol handles duplicates gracefully
- No risk of data corruption

### 3. **Minimal Overhead**
- Detection happens during normal gossip exchanges
- No additional network round trips
- Efficient duplicate filtering in event stores

### 4. **Comprehensive Coverage**
- Handles complete resets (timestamp 0)
- Handles partial resets (some state preserved)
- Works with multiple simultaneous resets

## Usage Examples

### Basic Reset Detection

```dart
// Node setup
final node = GossipNode(
  config: GossipConfig(nodeId: 'node-1'),
  eventStore: MemoryEventStore(),
  transport: MyTransport(),
);

// Reset detection happens automatically during gossip exchanges
// No additional configuration required
```

### Monitoring Reset Detection

```dart
// Listen for gossip exchange results to monitor reset recovery
node.onGossipExchange.listen((result) {
  if (result.eventsExchanged > 0) {
    print('Exchanged ${result.eventsExchanged} events with ${result.peer.id}');
    // High event counts might indicate reset recovery
  }
});
```

## Testing

### Unit Tests

The feature includes comprehensive unit tests covering:

- Basic reset detection scenarios
- Normal advancement cases (no false positives)
- Multiple peer scenarios
- Edge cases (zero timestamps, unknown peers)
- Vector clock merge behavior

### Test File Location

```
gossip/test/src/simple_vector_clock_reset_test.dart
```

### Running Tests

```bash
dart test test/src/simple_vector_clock_reset_test.dart
```

## Configuration

### No Additional Configuration Required

Vector clock reset detection is:
- **Enabled by default** in all GossipNode instances
- **Zero-configuration** - works automatically
- **Transparent** to application code

### Customization Options

While the feature works automatically, you can customize related behavior:

```dart
final config = GossipConfig(
  nodeId: 'my-node',
  maxEventsPerMessage: 100,    // Limits events sent during reset recovery
  gossipInterval: Duration(seconds: 1),  // Affects recovery speed
);
```

## Performance Considerations

### Network Impact

- **Minimal**: Detection uses existing gossip messages
- **Recovery**: May send more events during reset recovery
- **One-time**: Recovery cost is paid once per reset

### Memory Impact

- **Negligible**: No additional data structures required
- **Temporary**: Event batches during recovery are processed and released

### CPU Impact

- **Low**: Simple timestamp comparisons
- **Efficient**: Reuses existing gossip processing logic

## Limitations and Edge Cases

### Known Limitations

1. **Clock Skew**: System clock differences between nodes don't affect logical timestamps
2. **Partial State Loss**: Detection works even with partial vector clock corruption
3. **Multiple Resets**: Handles cascading resets across multiple nodes

### Edge Cases Handled

- **Zero Timestamps**: Properly detected as resets
- **Unknown Peers**: Treated as new peers (request from 0)
- **Equal Timestamps**: No false positive detection
- **Concurrent Resets**: Multiple peers resetting simultaneously

## Troubleshooting

### Common Issues

**Q: High network traffic after node restart**
A: Normal during reset recovery. Traffic reduces after synchronization completes.

**Q: Duplicate events in event store**
A: Event stores should handle duplicates idempotently (covered by interface contract).

**Q: Reset not detected**
A: Ensure gossip exchanges are happening. Check peer connectivity and gossip intervals.

### Debugging

Enable detailed logging to observe reset detection:

```dart
// Log gossip exchange results
node.onGossipExchange.listen((result) {
  print('Gossip with ${result.peer.id}: '
        '${result.eventsExchanged} events, '
        'success: ${result.success}');
});
```

## Implementation Files

### Core Implementation
- `lib/src/gossip_node.dart` - Main detection logic in `_handleIncomingDigest`
- `lib/src/vector_clock.dart` - Vector clock operations
- `lib/src/event_store.dart` - Event storage interface with `getLatestEvent` method

### Test Files
- `test/src/simple_vector_clock_reset_test.dart` - Comprehensive unit tests
- `test/src/vector_clock_reset_test.dart` - Integration tests (complex scenarios)

## Future Enhancements

### Potential Improvements

1. **Reset Metrics**: Track reset detection frequency for monitoring
2. **Configurable Thresholds**: Allow tuning of what constitutes a "recent" event
3. **Reset Notifications**: Events/callbacks when resets are detected
4. **Graceful Degradation**: Partial recovery strategies for very large resets

### Backward Compatibility

The implementation is fully backward compatible:
- No breaking changes to existing APIs
- Works with existing event stores and transports
- Transparent to application code

---

*This feature significantly improves the robustness of the gossip protocol by automatically handling vector clock reset scenarios that previously required manual intervention or resulted in permanent data loss.*