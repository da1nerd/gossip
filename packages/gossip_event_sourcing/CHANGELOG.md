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
- Event sourcing extensions for the gossip protocol library
- Event processor for handling event streams and building projections
- Projection system for creating read models from event streams
- Projection store interface for persistence abstraction
- Memory-based projection store implementation
- Type-safe event processing with compile-time validation
- Support for stateful projections with automatic state management

### Features
- Event stream processing with automatic replay capabilities
- Projection rebuilding and state recovery
- Integration with gossip protocol for distributed event sourcing
- Comprehensive event handling and validation
- Memory-efficient event processing
- Example implementations for common event sourcing patterns
- Comprehensive test coverage