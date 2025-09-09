# Access Control Implementation Plan

## Overview

This document outlines the implementation plan for adding pluggable access control to the Gossip Protocol library. The goal is to allow application-layer control over event permissions while maintaining the core gossip protocol's simplicity and performance.

## AI Implementation Context

### Project Structure Analysis
- **Main Package**: `gossip/packages/gossip/` contains the core gossip protocol
- **Language**: Dart/Flutter project with multiple packages in monorepo
- **Architecture**: Event-driven gossip protocol with vector clocks for causality tracking
- **Key Files to Modify**:
  - `lib/src/event.dart` - Core Event class (currently has id, nodeId, timestamp, creationTimestamp, payload)
  - `lib/src/gossip_config.dart` - Configuration class (currently ~300 lines with validation)
  - `lib/src/gossip_node.dart` - Main GossipNode class (~881 lines, contains _sendRequestedEvents method)
  - `lib/src/access_control.dart` - NEW file to create

### Current Implementation Details
- **Event Class**: Immutable class with fromJson/toJson, copyWith methods already implemented
- **GossipNode**: Uses _sendRequestedEvents method around line 714-717 to send events to peers
- **Transport Layer**: Abstract GossipTransport interface with sendDigest/sendEvents methods
- **Vector Clocks**: Used for causality tracking, stored in _vectorClock field
- **Configuration**: GossipConfig class with factory constructors and validation

### Key Implementation Patterns in Codebase
- Heavy use of async/await patterns
- Extensive parameter validation in constructors
- Factory constructors for common configurations  
- Stream-based event handling (onEventReceived, onEventCreated)
- Exception handling with custom exception types
- Comprehensive toString() and equals/hashCode implementations

### Backward Compatibility Requirements
- All existing Event constructors must continue to work
- Default behavior when no access control configured should be "allow all"
- Existing GossipConfig constructors must remain functional
- No breaking changes to public APIs

### Performance Constraints Identified
- Network efficiency is critical (max message sizes, batch limits)
- Memory usage optimization (duplicate detection, caching)
- Vector clock operations must remain fast
- Transport operations have configurable timeouts

### Testing Strategy Context
- Project uses standard Dart test package
- Existing tests in test/ directory follow naming convention
- Integration tests exist for full gossip protocol flows
- Performance considerations are already present in config (timeouts, limits)

## Design Principles

- **Application Control**: Permission logic remains in the application layer
- **Pluggable Architecture**: Easy to swap different access control implementations
- **Backward Compatibility**: Existing code continues to work without changes
- **Performance**: Minimize overhead for permission checks
- **Flexibility**: Support any permission model (RBAC, ABAC, custom rules)

## Implementation Phases

### Phase 1: Core Infrastructure (Week 1-2)

#### 1.1 Create Access Control Interfaces

**Files to create:**
- `packages/gossip/lib/src/access_control.dart`

**Tasks:**
- [ ] Define `EventAccessControl` abstract class
- [ ] Create `AccessControlContext` class
- [ ] Define `AccessControlOperation` enum
- [ ] Add comprehensive documentation and examples
- [ ] Write unit tests for interfaces

**Implementation Details:**
```dart
// AI Note: This interface must be async to support database/network lookups
// All methods should have comprehensive documentation
// Consider adding default implementations where possible
abstract class EventAccessControl {
  Future<bool> canPeerAccessEvent(Event event, GossipPeer peer, AccessControlContext context);
  Future<Map<String, int>> filterVectorClockForPeer(Map<String, int> vectorClock, GossipPeer peer, AccessControlContext context);
  Future<Map<String, dynamic>> getPeerMetadata(GossipPeer peer);
}

// AI Implementation Note: Place this in lib/src/access_control.dart
// Import dependencies: event.dart, gossip_peer.dart, gossip_node_id.dart
// Follow existing code style: const constructors where possible, comprehensive toString/equals
```

#### 1.2 Extend Event Model

**Files to modify:**
- `packages/gossip/lib/src/event.dart`

**Tasks:**
- [ ] Add `accessMetadata` field to `Event` class
- [ ] Create `Event.withAccessControl()` factory constructor  
- [ ] Update `fromJson`/`toJson` methods to handle access metadata
- [ ] Update `copyWith` method
- [ ] Ensure backward compatibility (empty metadata by default)
- [ ] Write tests for new functionality

**AI Implementation Notes:**
- Current Event class is at line ~15-130 in lib/src/event.dart
- Existing constructor: `const Event({required this.id, required this.nodeId, required this.timestamp, required this.creationTimestamp, required this.payload})`
- Add: `this.accessMetadata = const {},` parameter
- Update fromJson: `accessMetadata: Map<String, dynamic>.from(json['accessMetadata'] as Map? ?? {}),`
- Update toJson: `'accessMetadata': accessMetadata,` 
- Update copyWith: `Map<String, dynamic>? accessMetadata,` and `accessMetadata: accessMetadata ?? this.accessMetadata,`
- Follow existing validation pattern from other fields

#### 1.3 Update Gossip Configuration

**Files to modify:**
- `packages/gossip/lib/src/gossip_config.dart`

**Tasks:**
- [ ] Add `EventAccessControl? accessControl` field
- [ ] Add `bool enableDigestFiltering` field  
- [ ] Update constructors (including factory methods)
- [ ] Update `copyWith` method
- [ ] Add validation for access control configuration
- [ ] Update tests

**AI Implementation Notes:**
- GossipConfig class starts around line 20 in lib/src/gossip_config.dart
- Add fields after existing fields (around line 80-90)
- Update main constructor: add `this.accessControl,` and `this.enableDigestFiltering = false,`
- Update factory constructors: `GossipConfig.highThroughput()` and `GossipConfig.lowResource()` 
- Update copyWith method: add both new parameters with null checks
- Update _validate() method: add validation if needed
- Update toString(), equals(), and hashCode methods
- Import: `import 'access_control.dart';` at top

### Phase 2: Core Gossip Node Integration (Week 3-4)

#### 2.1 Modify Event Sending Logic

**Files to modify:**
- `packages/gossip/lib/src/gossip_node.dart`

**Tasks:**
- [ ] Update `_sendRequestedEvents` method to apply access control filtering
- [ ] Add peer metadata caching per exchange
- [ ] Implement efficient batching of access control checks
- [ ] Add error handling for access control failures
- [ ] Add telemetry/logging for access control decisions
- [ ] Write integration tests

**Key Changes:**
```dart
// AI Implementation Note: _sendRequestedEvents is around line 714-717 in gossip_node.dart
// Current signature: Future<int> _sendRequestedEvents(Map<GossipNodeID, int> eventRequests, TransportPeer transportPeer)
// Replace the method body completely - existing implementation gets events and sends all of them
// New implementation must:
// 1. Get peer from transportPeer using existing _getGossipPeerFromTransport method
// 2. Call config.accessControl?.getPeerMetadata(peer) once
// 3. Create AccessControlContext with currentNodeId, peerMetadata, operation
// 4. Loop through events and filter using canPeerAccessEvent
// 5. Respect existing config.maxEventsPerMessage limit
// 6. Use existing transport.sendEvents call
Future<int> _sendRequestedEvents(Map<GossipNodeID, int> eventRequests, TransportPeer transportPeer) async {
  // Get peer metadata once per exchange
  // Apply filtering to events before sending  
  // Handle access control errors gracefully
}
```

#### 2.2 Implement Digest-Level Filtering

**Files to modify:**
- `packages/gossip/lib/src/gossip_node.dart`

**Tasks:**
- [ ] Create `_createDigestForPeer` method
- [ ] Implement vector clock filtering based on access control  
- [ ] Update digest exchange logic to use filtered digests
- [ ] Add configuration flag to enable/disable digest filtering
- [ ] Write performance tests to measure overhead
- [ ] Document performance implications

**AI Implementation Notes:**
- Add new method `_createDigestForPeer` in GossipNode class
- Current digest creation is in `_exchangeDigestsWithTransportPeer` around line 672-674
- Replace the digest creation with call to new method
- New method should check `config.enableDigestFiltering` flag
- If enabled, call `config.accessControl?.filterVectorClockForPeer`  
- Return filtered GossipDigest with same structure as current

#### 2.3 Update Event Creation API

**Files to modify:**
- `packages/gossip/lib/src/gossip_node.dart`

**Tasks:**
- [ ] Add optional `accessMetadata` parameter to `createEvent`
- [ ] Create convenience methods for common access patterns
- [ ] Ensure backward compatibility
- [ ] Update documentation with examples
- [ ] Write tests for new API

**AI Implementation Notes:**
- Current `createEvent` method is around line 175 in gossip_node.dart
- Current signature: `Future<void> createEvent(Map<String, dynamic> payload)`
- Update to: `Future<void> createEvent(Map<String, dynamic> payload, {Map<String, dynamic> accessMetadata = const {}})`
- Pass accessMetadata to Event constructor when creating new event
- Consider adding convenience methods like `createPublicEvent`, `createRestrictedEvent`

### Phase 3: Reference Implementations (Week 5)

#### 3.1 Create Basic Access Control Implementations

**Files to create:**
- `packages/gossip/lib/src/access_control/no_access_control.dart`
- `packages/gossip/lib/src/access_control/simple_access_control.dart`
- `packages/gossip/lib/src/access_control/role_based_access_control.dart`

**Tasks:**
- [ ] `NoAccessControl`: Default implementation (all events public)
- [ ] `SimpleAccessControl`: Basic allow/deny list implementation
- [ ] `RoleBasedAccessControl`: Role-based permissions
- [ ] Include comprehensive documentation and examples
- [ ] Write unit tests for each implementation
- [ ] Add performance benchmarks

#### 3.2 Create Access Control Examples

**Files to create:**
- `packages/gossip/example/access_control_example.dart`
- `packages/gossip/example/group_based_access_control.dart`
- `packages/gossip/example/dynamic_access_control.dart`

**Tasks:**
- [ ] Simple access control example
- [ ] Group membership-based example
- [ ] Dynamic rule-based example
- [ ] Performance comparison examples
- [ ] Integration with different storage backends

### Phase 4: Advanced Features (Week 6-7)

#### 4.1 Performance Optimizations

**Tasks:**
- [ ] Implement metadata caching with TTL
- [ ] Add batch permission checking
- [ ] Optimize vector clock filtering
- [ ] Add lazy loading for peer metadata
- [ ] Create performance monitoring hooks
- [ ] Write performance benchmarks

#### 4.2 Enhanced Digest Filtering

**Files to modify:**
- `packages/gossip/lib/src/gossip_digest.dart`
- `packages/gossip/lib/src/gossip_digest_response.dart`

**Tasks:**
- [ ] Add access level hints to digests
- [ ] Implement hierarchical filtering (public < group < private)
- [ ] Add peer capability negotiation
- [ ] Create filtered digest statistics
- [ ] Write integration tests

#### 4.3 Access Control Events and Monitoring

**Files to create:**
- `packages/gossip/lib/src/access_control_events.dart`

**Tasks:**
- [ ] Create access control event streams
- [ ] Add metrics for permission checks
- [ ] Implement access denial logging
- [ ] Create debug/troubleshooting tools
- [ ] Add performance monitoring

### Phase 5: Testing and Documentation (Week 8)

#### 5.1 Comprehensive Testing

**Files to create:**
- `packages/gossip/test/access_control_test.dart`
- `packages/gossip/test/integration/access_control_integration_test.dart`
- `packages/gossip/test/performance/access_control_performance_test.dart`

**Tasks:**
- [ ] Unit tests for all access control interfaces
- [ ] Integration tests with various access control implementations
- [ ] Performance tests measuring overhead
- [ ] Network partition and failure scenario tests
- [ ] Backward compatibility tests
- [ ] Memory leak and resource usage tests

#### 5.2 Documentation

**Files to create/update:**
- `packages/gossip/ACCESS_CONTROL.md`
- Update `packages/gossip/README.md`

**Tasks:**
- [ ] Comprehensive access control guide
- [ ] API documentation with examples
- [ ] Performance tuning guide
- [ ] Migration guide for existing applications
- [ ] Troubleshooting guide
- [ ] Best practices documentation

### Phase 6: Extension Package (Week 9-10)

#### 6.1 Create Gossip Access Control Extension Package

**Files to create:**
- `packages/gossip_access_control/`
- `packages/gossip_access_control/lib/src/group_access_control.dart`
- `packages/gossip_access_control/lib/src/abac_access_control.dart`
- `packages/gossip_access_control/lib/src/jwt_access_control.dart`

**Tasks:**
- [ ] Group-based access control implementation
- [ ] Attribute-based access control (ABAC)
- [ ] JWT token-based access control
- [ ] Database-backed permission store
- [ ] Redis-backed permission caching
- [ ] Create package documentation and examples

## Implementation Checklist

### Core Library Changes

- [ ] `EventAccessControl` interface created
- [ ] `Event` class extended with `accessMetadata`
- [ ] `GossipConfig` updated with access control options
- [ ] `GossipNode` modified to use access control
- [ ] Digest filtering implemented
- [ ] Event creation API updated

### Reference Implementations

- [ ] `NoAccessControl` (default)
- [ ] `SimpleAccessControl` (allow/deny lists)
- [ ] `RoleBasedAccessControl` (role-based permissions)

### Testing

- [ ] Unit tests for all new interfaces
- [ ] Integration tests with access control
- [ ] Performance benchmarks
- [ ] Backward compatibility tests

### Documentation

- [ ] Access control guide
- [ ] API documentation
- [ ] Migration guide
- [ ] Examples and best practices

### Extension Package

- [ ] Group-based access control
- [ ] ABAC implementation
- [ ] JWT-based access control
- [ ] Database integrations

## Performance Considerations

### Optimization Strategies

1. **Metadata Caching**: Cache peer metadata for the duration of gossip exchanges
2. **Batch Processing**: Check permissions for multiple events at once
3. **Lazy Loading**: Only load permission data when needed
4. **Digest Optimization**: Filter at vector clock level to reduce network traffic

### Performance Targets

- **Access Control Overhead**: < 5% additional latency for event exchanges
- **Memory Usage**: < 10% increase in memory footprint
- **Network Traffic**: Digest filtering should reduce traffic by 20-50% for restricted events

## Migration Strategy

### Backward Compatibility

- All existing code continues to work without changes
- Events without `accessMetadata` are treated as public
- Default `NoAccessControl` implementation when no access control configured

### Migration Steps

1. Update to new version (access control optional)
2. Add access control implementation to configuration
3. Gradually add access metadata to new events
4. Optionally migrate existing events with access metadata

## Testing Strategy

### Test Categories

1. **Unit Tests**: Individual component testing
2. **Integration Tests**: Full gossip protocol with access control
3. **Performance Tests**: Overhead and scalability testing
4. **Compatibility Tests**: Ensure backward compatibility
5. **Network Tests**: Behavior under various network conditions

### Test Environments

- Single node testing
- Multi-node gossip networks (3, 5, 10 nodes)
- Network partition scenarios
- High-throughput scenarios
- Resource-constrained environments

## Success Criteria

### Functional Requirements

- [ ] Events can be filtered based on application-defined permissions
- [ ] Multiple access control implementations work seamlessly
- [ ] Digest-level filtering reduces network traffic
- [ ] Backward compatibility maintained
- [ ] Performance overhead is minimal

### Non-Functional Requirements

- [ ] < 5% performance overhead for permission checks
- [ ] Memory usage increase < 10%
- [ ] All existing tests continue to pass
- [ ] Comprehensive documentation available
- [ ] Production-ready extension implementations

## Future Enhancements

### Potential Future Features

1. **Encrypted Events**: Event-level encryption based on access control
2. **Audit Logging**: Comprehensive access control audit trails
3. **Dynamic Permissions**: Real-time permission updates
4. **Federation**: Cross-network access control
5. **Machine Learning**: Anomaly detection for access patterns

### Extension Points

- Custom permission resolvers
- Pluggable metadata storage
- External permission services integration
- Custom digest filtering strategies

## AI Implementation Quick Reference

### Key File Locations
- **Event class**: `gossip/packages/gossip/lib/src/event.dart` (line ~15-130)
- **GossipConfig**: `gossip/packages/gossip/lib/src/gossip_config.dart` (line ~20-400) 
- **GossipNode**: `gossip/packages/gossip/lib/src/gossip_node.dart` (line ~38-881)
- **Main export**: `gossip/packages/gossip/lib/gossip.dart` (add new exports here)

### Critical Methods to Modify
- `Event` constructor (add accessMetadata parameter)
- `Event.fromJson/toJson` (handle accessMetadata field)
- `GossipConfig` constructor (add accessControl and enableDigestFiltering)
- `GossipNode._sendRequestedEvents` (line ~714-717, add filtering logic)
- `GossipNode.createEvent` (line ~175, add accessMetadata parameter)

### Implementation Order
1. Create access_control.dart with interfaces first
2. Modify Event class (simple addition)
3. Modify GossipConfig (simple addition)  
4. Modify GossipNode methods (complex logic)
5. Add tests and examples
6. Create extension package

### Common Patterns in Codebase
- Use `const` constructors where possible
- Always implement toString(), equals(), hashCode()
- Add comprehensive parameter validation
- Use factory constructors for common configurations
- Follow async/await patterns consistently
- Handle exceptions with try/catch blocks
- Use stream controllers for event emissions