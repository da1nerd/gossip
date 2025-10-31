# Domain Layer Tests

This directory contains comprehensive tests for the domain layer of the gossip protocol implementation. The domain layer represents the core business logic and rules of the gossip system, independent of infrastructure concerns.

## Test Structure

### Entity Tests
- **`entities/internal_gossip_peer_test.dart`** - Tests for the `InternalGossipPeer` domain entity
  - Peer reliability scoring logic
  - Contact time tracking
  - Active/inactive state transitions
  - Domain behavior and invariants

### Service Tests
- **`services/peer_selection_service_test.dart`** - Tests for the `PeerSelectionService` domain service
  - Random peer selection strategy
  - Round-robin peer selection strategy
  - Least recently contacted strategy
  - Most reliable peers strategy
  - Edge cases and performance tests

### Integration Tests
- **`domain_integration_test.dart`** - Integration tests across domain components
  - Peer lifecycle and selection integration
  - Strategy comparison and consistency
  - Scalability and performance integration
  - Domain invariant enforcement
  - Real-world scenario simulation

## Test Utilities

### Helper Files
- **`test_helpers.dart`** - Common utilities and fixtures for domain tests
  - Test peer creation utilities
  - Network simulation helpers
  - Validation and assertion utilities
  - Performance measurement tools

### Configuration
- **`../test_config.dart`** - Global test configuration and custom matchers
  - Test timeouts and performance limits
  - Custom matchers for domain-specific assertions
  - Test environment setup utilities

## Running Tests

### Run All Domain Tests
```bash
cd packages/gossip
dart test test/domain/
```

### Run Specific Test Suites
```bash
# Entity tests only
dart test test/domain/entities/

# Service tests only  
dart test test/domain/services/

# Integration tests only
dart test test/domain/domain_integration_test.dart
```

### Run with Different Reporters
```bash
# Compact output
dart test test/domain/ --reporter=compact

# Verbose output with timing
dart test test/domain/ --reporter=expanded

# JSON output for CI/CD
dart test test/domain/ --reporter=json
```

## Test Coverage

The domain layer tests provide comprehensive coverage of:

### Core Business Logic
- ✅ Peer reliability scoring algorithms
- ✅ Active/inactive state management
- ✅ Contact time tracking and comparison
- ✅ Peer selection strategy implementations
- ✅ Domain invariant enforcement

### Edge Cases and Error Handling
- ✅ Boundary value testing (0.0-1.0 reliability scores)
- ✅ Negative and zero input handling
- ✅ Empty peer list scenarios
- ✅ Rapid state transition scenarios
- ✅ High-frequency update handling

### Performance and Scalability
- ✅ Large peer list handling (1000+ peers)
- ✅ High-frequency operation performance
- ✅ Algorithm time complexity validation
- ✅ Memory usage patterns

### Real-World Scenarios
- ✅ Network partition and recovery simulation
- ✅ Mixed reliability peer networks
- ✅ Gradual peer degradation and recovery
- ✅ Strategy adaptation over time

## Key Test Patterns

### Property-Based Testing
Tests verify that domain properties hold across various input combinations:
```dart
// Reliability scores always stay within bounds
expect(peer.reliabilityScore, isValidReliabilityScore());

// Selection strategies respect peer activity status
expect(selected.every((p) => p.isActive), isTrue);
```

### Behavioral Testing
Tests focus on business behavior rather than implementation:
```dart
// Test the behavior, not the internal calculation
peer.recordFailedContact();
expect(peer.isLessReliableThanBefore(), isTrue);
```

### Simulation Testing
Tests use realistic scenarios to validate domain logic:
```dart
// Simulate network partition and recovery
simulateNetworkPartition(peers, 
  partitionRounds: 10, 
  recoveryRounds: 5
);
```

## Test Data and Fixtures

### Test Peer Creation
The test helpers provide various utilities for creating test data:
- `createTestPeer()` - Single peer with optional parameters
- `createTestPeers(count)` - List of basic test peers
- `createPeerWithReliability()` - Peer with specific reliability history
- `createMixedScenarioPeers()` - Realistic peer mix for integration tests

### Performance Benchmarks
Performance tests establish baseline expectations:
- Peer selection: < 100ms for 1000 peers
- Reliability calculation: < 1s for 10,000 updates
- Memory usage: Linear growth with peer count

## Continuous Integration

### Test Quality Gates
All tests must pass these quality criteria:
- **Coverage**: 100% line coverage of domain layer
- **Performance**: All operations under defined time limits
- **Reliability**: No flaky tests (>99.9% success rate)
- **Maintainability**: Clear test names and documentation

### Test Categories
Tests are categorized for different CI/CD stages:
- **Unit Tests**: Fast, isolated tests (< 1s each)
- **Integration Tests**: Cross-component tests (< 5s each)  
- **Performance Tests**: Scalability validation (< 30s each)
- **Stress Tests**: High-load scenarios (< 2min each)

## Contributing

When adding new domain functionality:

1. **Write tests first** - Follow TDD principles
2. **Cover edge cases** - Include boundary value and error cases
3. **Add integration tests** - Verify interaction with other components
4. **Document behavior** - Clear test names and comments
5. **Update helpers** - Add reusable test utilities when appropriate

### Test Naming Convention
```dart
// Pattern: [Component] [Scenario] [ExpectedBehavior]
test('peer recordSuccessfulContact resets consecutive failures', () {});
test('selection service random strategy distributes fairly over time', () {});
test('domain integration handles network partition recovery', () {});
```

## Architecture Benefits

This comprehensive test suite enables:

- **Confident refactoring** - Domain logic changes are safe
- **Performance monitoring** - Regression detection
- **Documentation** - Tests serve as behavior specifications  
- **Quality assurance** - High reliability in production
- **Developer productivity** - Fast feedback on changes

The domain layer tests form the foundation for reliable, maintainable gossip protocol implementation.