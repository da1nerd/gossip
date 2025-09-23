## 3.2.0

 - **FEAT**(gossip_typed_events): Added utility  methods to EventFactory to deserialize events to typed events.

## 3.1.0

 - fixed bugs

## 3.0.0

 - Included original event in typed event streams

## 2.0.0

 - Separated typed evetnt stream into two streams for created and received events

## 1.0.5

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.3] - 2024-12-30

### Changed
- Version bump for package synchronization

## [1.0.2] - 2024-12-30

### Changed
- Version bump for package synchronization

## [1.0.1] - 2024-12-30

### Added
- Initial stable release
- Type-safe event extensions for the Dart gossip protocol library
- Compile-time validation and serialization for gossip events
- TypedEvent class for strongly-typed event definitions
- TypedEventMixin for adding type safety to existing events
- TypedEventRegistry for managing event type mappings
- TypedEventTransformer for serialization/deserialization
- TypedGossipNode for type-safe event handling
- Integration with base gossip protocol for seamless operation

### Features
- Compile-time type checking for event definitions
- Automatic serialization and deserialization
- Type-safe event creation and handling
- Runtime type validation with graceful error handling
- Support for complex nested data structures
- JSON-based serialization with type preservation
- Comprehensive example implementations
- Extensive test coverage with type safety validation
- Documentation for implementation patterns