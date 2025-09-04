# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial release of gossip_typed_events library
- TypedEvent abstract base class for defining custom event types
- TypedEventMixin for common functionality like timestamps and metadata
- TypedEventRegistry for managing event type factories and deserialization
- TypedGossipNode extension providing type-safe methods for GossipNode
- Stream transformers for converting raw events to typed events
- Comprehensive documentation and examples
- Full test coverage with unit and integration tests

### Features
- **Type-safe events** - Define custom event types with compile-time safety
- **Automatic serialization** - Events are automatically serialized/deserialized
- **Event filtering** - Stream-based filtering by event type
- **Event registry** - Central registry for managing event types
- **Stream transformers** - Powerful stream processing capabilities
- **Validation support** - Built-in validation framework for events
- **Metadata support** - Attach metadata to events for additional context
- **Error handling** - Comprehensive error handling with custom exceptions
- **Batch operations** - Efficiently broadcast multiple events
- **Registry-based deserialization** - Automatic event creation from registry

### Components
- `TypedEvent` - Abstract base class for all typed events
- `TypedEventMixin` - Provides timestamps, metadata, and validation
- `TypedEventRegistry` - Singleton registry for event type management
- `TypedGossipNode` - Extension methods for GossipNode with type safety
- `TypedEventTransformer` - Stream transformer for single event types
- `RegistryTypedEventTransformer` - Registry-based stream transformer
- `MultiTypeEventTransformer` - Multi-type stream transformer

### Documentation
- Comprehensive README with examples and best practices
- Detailed API documentation with usage examples
- Complete example application demonstrating all features
- Architecture documentation explaining library design

### Testing
- 100% test coverage for all public APIs
- Unit tests for individual components
- Integration tests with real gossip nodes
- Error handling and edge case testing
- Performance and memory usage validation

## [1.0.0] - 2024-01-XX

### Added
- Initial stable release
- Complete type-safe event system for gossip protocol
- Production-ready implementation with comprehensive testing
- Full documentation and examples