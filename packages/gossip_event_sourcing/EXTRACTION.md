# Event Sourcing Library Extraction

This document explains how the event sourcing components were extracted from the gossip-demo into a separate, reusable library.

## What Was Extracted

### Components Moved to `gossip_event_sourcing` Library

- **`EventProcessor`** - Core event processing coordination
- **`Projection`** - Base class for read models with state restoration
- **`ProjectionStore`** - Interface for persistent projection state storage
- **`ProjectionStoreConfig`** - Configuration options for projection store behavior
- **`ProjectionChangeNotifier`** - Framework-agnostic change notification mixin

### Components Kept in `gossip-demo`

- **`ChatProjection`** - Chat-specific projection implementation
- **`HiveProjectionStore`** - Hive-based storage implementation (Flutter-specific)
- **Chat models and events** - Application-specific domain objects

## Benefits of Extraction

### 1. Reusability
- Other projects can now use the event sourcing components
- Clean separation between generic and application-specific code
- Consistent patterns across different applications

### 2. Framework Independence
- Core library works with any Dart application (console, web, mobile)
- Optional Flutter integration through mixins and implementations
- No hard dependencies on Flutter in the core library

### 3. Better Testing
- Core components can be tested independently
- Clear interfaces make mocking easier
- Separation of concerns improves test coverage

### 4. Maintainability
- Focused responsibilities for each package
- Independent versioning and release cycles
- Easier to reason about and modify

## Migration Guide

### For Existing gossip-demo Code

1. **Update pubspec.yaml**:
```yaml
dependencies:
  gossip_event_sourcing:
    path: ../gossip_event_sourcing
```

2. **Update imports**:
```dart
// Old
import 'package:gossip_chat_demo/services/event_sourcing/event_sourcing.dart';

// New
import 'package:gossip_event_sourcing/gossip_event_sourcing.dart';
import 'package:gossip_chat_demo/services/event_sourcing/projections/chat_projection.dart';
```

3. **Use new HiveProjectionStore**:
```dart
// Import the demo-specific Hive implementation
import 'package:gossip_chat_demo/services/hive_projection_store.dart';

// Create and use as before
final projectionStore = HiveProjectionStore();
```

### For New Projects

1. **Add dependency**:
```yaml
dependencies:
  gossip_event_sourcing: ^1.0.0
```

2. **Create custom projections**:
```dart
import 'package:gossip_event_sourcing/gossip_event_sourcing.dart';

class MyProjection extends Projection with ProjectionChangeNotifier {
  // Your projection implementation
}
```

3. **Implement custom projection store** (optional):
```dart
class MyProjectionStore implements ProjectionStore {
  // Your storage implementation
}
```

## Architecture

### Library Structure
```
gossip_event_sourcing/
├── lib/
│   ├── gossip_event_sourcing.dart    # Main exports
│   └── src/
│       ├── event_processor.dart       # Core processing logic
│       ├── projection.dart           # Base projection interface
│       └── projection_store.dart     # Storage interfaces
├── example/
│   └── example.dart                  # Usage examples
└── README.md                         # Documentation
```

### Dependencies
- **gossip**: For Event interface and core functionality
- **No Flutter dependencies** in core library

### Demo Integration
```
gossip-demo/
├── lib/services/
│   ├── hive_projection_store.dart        # Flutter/Hive implementation
│   └── event_sourcing/projections/
│       └── chat_projection.dart          # Chat-specific projection
└── pubspec.yaml                          # Depends on gossip_event_sourcing
```

## Design Decisions

### 1. Framework Agnostic Core
- Core library has no Flutter dependencies
- Uses generic change notification pattern
- Allows for console, web, and mobile applications

### 2. Storage Implementation Separation
- Storage backends are implementation-specific
- Core library provides interfaces only
- Allows for multiple storage options (Hive, SQLite, MongoDB, etc.)

### 3. Event Interface Compatibility
- Uses existing Event interface from gossip library
- No breaking changes to existing event structures
- Backward compatibility with legacy event formats

### 4. Configuration Flexibility
- Multiple configuration presets for different use cases
- Easy to customize behavior without code changes
- Sensible defaults for most applications

## Future Enhancements

### Planned Features
- Additional storage backend implementations
- Enhanced monitoring and metrics
- Performance optimization tools
- Schema migration utilities

### Potential Integrations
- Stream processing frameworks
- Distributed systems support
- Event versioning and migration tools
- Real-time synchronization capabilities

## Contributing

To contribute to the extracted library:

1. **Core Library** (`gossip_event_sourcing`):
   - Focus on framework-agnostic functionality
   - Maintain backward compatibility
   - Add comprehensive tests

2. **Demo Integration** (`gossip-demo`):
   - Provide concrete implementation examples
   - Test real-world usage scenarios
   - Document best practices

## Version History

### v1.0.0 - Initial Extraction
- Extracted core event sourcing components
- Framework-agnostic design
- Comprehensive documentation and examples
- Full backward compatibility with gossip-demo

---

This extraction provides a solid foundation for building event-sourced applications while maintaining the flexibility to use different storage backends and frameworks.