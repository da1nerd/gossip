# Gossip Typed Events Implementation

This document provides a technical overview of the `gossip_typed_events` library implementation, which extracts type-safe event functionality from the core gossip protocol library.

## Architecture Overview

The library provides a type-safe layer on top of the core gossip protocol while maintaining full backward compatibility:

```
┌─────────────────────────────────────────┐
│           Your Application              │
├─────────────────────────────────────────┤
│      Typed Events (this library)       │
│  ┌─────────────┐  ┌─────────────────┐   │
│  │ TypedEvent  │  │ TypedGossipNode │   │
│  └─────────────┘  └─────────────────┘   │
├─────────────────────────────────────────┤
│         Core Gossip Protocol            │
│  ┌─────────────┐  ┌─────────────────┐   │
│  │    Event    │  │   GossipNode    │   │
│  └─────────────┘  └─────────────────┘   │
└─────────────────────────────────────────┘
```

## Core Components

### 1. TypedEvent (`src/typed_event.dart`)

**Purpose**: Abstract base class for all typed events

**Key Features**:
- Type identifier system for event classification
- JSON serialization/deserialization interface
- Deep equality comparison with proper hash codes
- Extensible design for custom event types

**Implementation Details**:
```dart
abstract class TypedEvent {
  String get type;
  Map<String, dynamic> toJson();
  static TypedEvent fromJson(Map<String, dynamic> json);
}
```

### 2. TypedEventMixin (`src/typed_event_mixin.dart`)

**Purpose**: Provides common functionality for typed events

**Key Features**:
- Automatic timestamp tracking
- Metadata management system
- Event validation framework
- Enhanced serialization with metadata

**Implementation Details**:
- Uses lazy initialization for timestamps
- Provides metadata CRUD operations
- Implements validation chain pattern
- Combines base data with metadata in serialization

### 3. TypedEventRegistry (`src/typed_event_registry.dart`)

**Purpose**: Central registry for managing event type factories

**Key Features**:
- Singleton pattern for global access
- Type-safe factory registration
- Dynamic event deserialization
- Comprehensive error handling

**Implementation Details**:
- Maps type strings to factory functions
- Maintains bidirectional type mappings
- Thread-safe operations
- Provides introspection capabilities

### 4. TypedGossipNode Extension (`src/typed_gossip_node.dart`)

**Purpose**: Adds type-safe methods to GossipNode

**Key Features**:
- Type-safe event broadcasting
- Filtered event streams by type
- Registry-based automatic deserialization
- Batch event operations

**Implementation Details**:
- Uses Dart extension syntax
- Wraps events in standard gossip format
- Provides multiple stream filtering options
- Maintains compatibility with core gossip protocol

### 5. Stream Transformers (`src/typed_event_transformer.dart`)

**Purpose**: Convert raw event streams to typed event streams

**Key Features**:
- Single-type event transformers
- Multi-type event transformers
- Registry-based transformers
- Comprehensive error handling

**Implementation Details**:
- Extends `StreamTransformerBase`
- Provides filtering and deserialization
- Supports custom error handling
- Includes convenience factory functions

## Event Flow

### 1. Event Creation and Broadcasting

```
Application → TypedEvent → TypedGossipNode → GossipNode → Network
```

1. User creates typed event with validation
2. TypedGossipNode wraps in gossip format:
   ```json
   {
     "type": "user_login",
     "data": { ... event data ... },
     "version": "1.0"
   }
   ```
3. GossipNode handles network distribution

### 2. Event Reception and Processing

```
Network → GossipNode → TypedGossipNode → Stream Transformers → Application
```

1. GossipNode receives raw events
2. TypedGossipNode filters by format
3. Stream transformers deserialize to typed events
4. Application receives strongly-typed events

## Serialization Format

### Standard Format
```json
{
  "type": "event_type_identifier",
  "data": {
    // Event-specific data
  },
  "version": "1.0"
}
```

### With Metadata (using TypedEventMixin)
```json
{
  "type": "event_type_identifier",
  "data": {
    "createdAt": 1640995200000,
    "metadata": {
      "source": "mobile_app",
      "version": "1.2.3"
    },
    // Event-specific data
  },
  "version": "1.0"
}
```

## Type Safety Implementation

### Compile-Time Safety
- Generic type parameters enforce type constraints
- Factory pattern ensures proper deserialization
- Extension methods provide type-safe APIs

### Runtime Safety
- Registry validates type registrations
- Stream transformers handle deserialization errors
- Validation framework prevents invalid events

## Error Handling Strategy

### Exception Hierarchy
- `TypedEventException`: General typed event errors
- `TypedEventRegistryException`: Registry-specific errors
- `TypedEventTransformerException`: Stream transformer errors

### Error Recovery
- Graceful degradation for deserialization failures
- Optional error handlers in stream transformers
- Validation errors prevent invalid event creation

## Performance Considerations

### Memory Usage
- Lazy initialization of timestamps and metadata
- Efficient JSON serialization
- Stream-based processing to avoid loading all events

### Network Efficiency
- Standard gossip format maintains compatibility
- Minimal serialization overhead
- Batch operations for multiple events

### CPU Usage
- Registry lookups are O(1)
- Stream filtering at gossip level
- Lazy deserialization only when needed

## Testing Strategy

### Unit Tests
- Individual component testing
- Error condition coverage
- Edge case validation

### Integration Tests
- Multi-node gossip scenarios
- Event propagation validation
- Type safety verification

### Example Coverage
- Real-world usage patterns
- Complete feature demonstration
- Error handling scenarios

## Design Decisions

### Why Extensions Over Inheritance
- Maintains compatibility with existing GossipNode
- Allows optional adoption
- Cleaner separation of concerns

### Why Registry Pattern
- Centralized type management
- Dynamic deserialization capability
- Type introspection support

### Why Stream Transformers
- Composable event processing
- Efficient filtering
- Framework-agnostic design

## Migration Path

### From Raw Events
1. Define typed event classes
2. Register types in registry
3. Replace `createEvent()` with `broadcastTypedEvent()`
4. Replace event listeners with typed streams

### Gradual Adoption
- Library works alongside raw events
- Can migrate event types incrementally
- No breaking changes to existing code

## Future Enhancements

### Potential Additions
- Event versioning system
- Schema validation
- Event sourcing patterns
- Performance monitoring hooks

### Backward Compatibility
- All changes maintain existing API
- Optional features don't break core functionality
- Clear deprecation path for old features

## Dependencies

### Core Dependencies
- `gossip`: Core gossip protocol library
- `meta`: Dart annotations

### Development Dependencies
- `test`: Testing framework
- `lints`: Code quality analysis

## File Structure

```
lib/
├── src/
│   ├── typed_event.dart              # Base TypedEvent class
│   ├── typed_event_mixin.dart        # Common functionality mixin
│   ├── typed_event_registry.dart     # Type registry system
│   ├── typed_gossip_node.dart        # GossipNode extensions
│   └── typed_event_transformer.dart  # Stream transformers
└── gossip_typed_events.dart          # Main library export

example/
└── typed_events_example.dart         # Complete usage example

test/
└── typed_events_test.dart            # Comprehensive test suite
```

This implementation successfully extracts the typed events functionality into a separate, optional library while maintaining full compatibility with the core gossip protocol.