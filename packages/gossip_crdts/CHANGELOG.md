## 1.0.4

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
- CRDT (Conflict-free Replicated Data Types) extensions for the gossip protocol
- Support for distributed data structures with automatic conflict resolution
- G-Counter (Grow-only Counter) implementation
- PN-Counter (Positive-Negative Counter) implementation
- G-Set (Grow-only Set) implementation
- OR-Set (Observed-Remove Set) implementation
- LWW-Register (Last-Write-Wins Register) implementation
- MV-Register (Multi-Value Register) implementation
- LWW-Map (Last-Write-Wins Map) implementation
- OR-Map (Observed-Remove Map) implementation
- RGA-Array (Replicated Growable Array) implementation
- Enable-Wins Flag implementation
- CRDT Manager for coordinating multiple CRDTs
- CRDT Store for persistence and retrieval
- Extensions for integrating CRDTs with GossipNode

### Features
- Type-safe CRDT operations with compile-time validation
- Automatic conflict resolution using CRDT semantics
- Vector clock integration for causal ordering
- Serialization and deserialization support
- Memory-efficient implementations
- Collaborative editing examples (counter and text editing)
- Comprehensive test coverage