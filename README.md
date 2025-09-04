# Gossip Monorepo

A monorepo containing the Gossip distributed event synchronization library and related packages.

## Overview

This repository contains:

- **Core Library**: The main Gossip protocol implementation
- **Extensions**: CRDTs, Event Sourcing, and Typed Events
- **Demo App**: A Flutter chat application showcasing the Gossip protocol

## Repository Structure

```
gossip-mono/
├── apps/
│   └── gossip_chat/          # Flutter chat demo app
├── packages/
│   ├── gossip/               # Core Gossip protocol library
│   ├── gossip_crdts/         # CRDT extensions for Gossip
│   ├── gossip_event_sourcing/ # Event sourcing utilities
│   └── gossip_typed_events/  # Typed event system
├── melos.yaml               # Melos configuration
└── pubspec.yaml            # Workspace configuration
```

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (latest stable)
- [Dart SDK](https://dart.dev/get-dart) (>= 3.0.0)

### Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/da1nerd/gossip-mono.git
   cd gossip-mono
   ```

2. **Install Melos globally**
   ```bash
   dart pub global activate melos
   ```

3. **Bootstrap the workspace**
   ```bash
   melos bootstrap
   ```

   This will:
   - Install dependencies for all packages
   - Link local package dependencies
   - Generate IDE files

## Development Commands

### Workspace Management

```bash
# List all packages
melos list

# Get dependencies for all packages
melos bootstrap

# Clean all packages
melos clean
```

### Code Quality

```bash
# Run static analysis on all packages
melos run analyze

# Format code in all packages
melos run format

# Run tests in all packages
melos run test
```

### Package-Specific Commands

```bash
# Run commands in specific packages
melos exec --scope="gossip" -- dart test
melos exec --scope="gossip_chat_demo" -- flutter run
```

## Packages

### Core Library

#### `gossip`
The main Gossip protocol implementation for distributed event synchronization.

- **Location**: `packages/gossip/`
- **Purpose**: Core gossip protocol and event synchronization
- **Dependencies**: None (pure Dart)

### Extensions

#### `gossip_crdts`
Conflict-free Replicated Data Types (CRDTs) built on top of the Gossip protocol.

- **Location**: `packages/gossip_crdts/`
- **Purpose**: CRDT implementations for distributed data structures
- **Dependencies**: `gossip`

#### `gossip_event_sourcing`
Event sourcing utilities and patterns for use with Gossip.

- **Location**: `packages/gossip_event_sourcing/`
- **Purpose**: Event sourcing infrastructure
- **Dependencies**: `gossip`

#### `gossip_typed_events`
Type-safe event system built on Gossip protocol.

- **Location**: `packages/gossip_typed_events/`
- **Purpose**: Strongly-typed event broadcasting and handling
- **Dependencies**: `gossip`

### Applications

#### `gossip_chat_demo`
A Flutter demonstration app showing peer-to-peer chat using Gossip protocol with Nearby Connections.

- **Location**: `apps/gossip_chat/`
- **Purpose**: Demo application showcasing Gossip protocol
- **Platform**: Flutter (iOS/Android)
- **Dependencies**: All Gossip packages, `nearby_connections`, etc.

## Running the Demo App

```bash
cd apps/gossip_chat
flutter run
```

Or using Melos:
```bash
melos exec --scope="gossip_chat_demo" -- flutter run
```

## Contributing

1. Make sure all tests pass: `melos run test`
2. Ensure code is properly formatted: `melos run format`
3. Run static analysis: `melos run analyze`
4. Update documentation as needed

## Architecture

The Gossip protocol enables decentralized event synchronization between peers without requiring a central server. Each package in this monorepo extends the core protocol for specific use cases:

- **CRDTs** for conflict-free distributed data structures
- **Event Sourcing** for rebuilding state from events
- **Typed Events** for type-safe event handling
- **Chat Demo** as a real-world implementation example

## License

[Add your license information here]