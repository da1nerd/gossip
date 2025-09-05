# 🗣️ Gossip Protocol Monorepo

[![CI/CD Pipeline](https://github.com/da1nerd/gossip-mono/actions/workflows/ci.yml/badge.svg)](https://github.com/da1nerd/gossip-mono/actions/workflows/ci.yml)
[![Publish Packages](https://github.com/da1nerd/gossip-mono/actions/workflows/publish-packages.yml/badge.svg)](https://github.com/da1nerd/gossip-mono/actions/workflows/publish-packages.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A comprehensive monorepo containing the Gossip distributed event synchronization protocol and related packages, plus a fully-functional Flutter peer-to-peer chat demonstration app.

## 🌟 Overview

The Gossip Protocol enables **decentralized event synchronization** between peers without requiring a central server. This monorepo provides:

- 🔄 **Core Protocol**: Vector clock-based event synchronization
- 🏗️ **Extensions**: CRDTs, Event Sourcing, and Type-safe Events
- 📱 **Demo App**: Real-world P2P chat using Android Nearby Connections
- 🚀 **CI/CD**: Automated publishing to pub.dev and Google Play Store

## 📦 Packages

### Core Library

| Package | Version | Description |
|---------|---------|-------------|
| [`gossip`](./packages/gossip/) | [![pub package](https://img.shields.io/pub/v/gossip.svg)](https://pub.dev/packages/gossip) | Core gossip protocol with vector clocks and anti-entropy |

### Extensions

| Package | Version | Description |
|---------|---------|-------------|
| [`gossip_crdts`](./packages/gossip_crdts/) | [![pub package](https://img.shields.io/pub/v/gossip_crdts.svg)](https://pub.dev/packages/gossip_crdts) | Conflict-free Replicated Data Types (CRDTs) |
| [`gossip_event_sourcing`](./packages/gossip_event_sourcing/) | [![pub package](https://img.shields.io/pub/v/gossip_event_sourcing.svg)](https://pub.dev/packages/gossip_event_sourcing) | Event Sourcing and CQRS patterns |
| [`gossip_typed_events`](./packages/gossip_typed_events/) | [![pub package](https://img.shields.io/pub/v/gossip_typed_events.svg)](https://pub.dev/packages/gossip_typed_events) | Type-safe event system |

### Demo Application

| App | Platform | Description |
|-----|----------|-------------|
| [**Gossip Chat**](./apps/gossip_chat/) | 📱 Android | P2P chat using Nearby Connections |

## 🏗️ Repository Structure

```
gossip-mono/
├── 📦 packages/
│   ├── gossip/                    # Core protocol library
│   ├── gossip_crdts/             # CRDT extensions
│   ├── gossip_event_sourcing/    # Event sourcing utilities
│   └── gossip_typed_events/      # Type-safe events
├── 📱 apps/
│   └── gossip_chat/              # Flutter P2P chat demo
├── 🔄 .github/workflows/         # CI/CD automation
│   ├── ci.yml                    # Test and build validation
│   ├── publish-packages.yml      # Auto-publish to pub.dev
│   └── release.yml               # Release management
├── 📋 scripts/
│   └── release.sh                # Release management script
├── 📖 DEPLOYMENT.md              # Comprehensive deployment guide
├── ⚙️ codemagic.yaml             # Play Store deployment config
└── 🎯 melos.yaml                 # Monorepo management
```

## 🚀 Quick Start

### Prerequisites

- **Flutter SDK** (stable channel) - [Install Guide](https://flutter.dev/docs/get-started/install)
- **Dart SDK** (>=3.0.0)
- **Git** for version control

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/da1nerd/gossip-mono.git
cd gossip-mono

# 2. Install Melos (monorepo management)
dart pub global activate melos

# 3. Bootstrap the workspace
melos bootstrap

# 4. Verify setup
melos run test
```

### Run the Demo App

```bash
# Option 1: Using Flutter directly
cd apps/gossip_chat
flutter run

# Option 2: Using Melos
melos run app-test    # Run app tests
melos exec --scope="gossip_chat_demo" -- flutter run
```

## 🛠️ Development Commands

### Workspace Management

```bash
# List all packages
melos list

# Bootstrap dependencies
melos bootstrap

# Clean all packages
melos clean

# Check for outdated dependencies
melos run outdated
```

### Code Quality & Testing

```bash
# Run all tests
melos run test

# Static analysis
melos run analyze

# Code formatting
melos run format

# Pre-publish checks
melos run pre-publish-check
```

### Package Management & Versioning

The monorepo uses **centralized version management** - all packages follow the version in the root `pubspec.yaml` as the single source of truth.

```bash
# Version all packages (patch increment)
melos run version-patch

# Version all packages (minor increment) 
melos run version-minor

# Version all packages (major increment)
melos run version-major

# Test version update locally (with backup/restore)
melos run version-test

# Dry run publishing
melos run publish-dry-run

# Publish packages to pub.dev
melos run publish-packages
```

**How Version Management Works:**
1. The root `pubspec.yaml` version is the single source of truth
2. All packages in `/packages/` are updated to match this version
3. Internal package dependencies are automatically updated to use consistent versions
4. The app (`gossip_chat`) uses independent versioning for Play Store deployment
5. GitHub releases are tagged with the package version

**Local Testing:**
```bash
# Version all packages with automatic dependency updates
dart run melos run version-patch

# Version all packages to same version (alternative)
dart run melos run version-all-patch

# View current versions
dart run melos list
```

### App Development

```bash
# Run app tests
melos run app-test

# Build debug APK
melos run app-build-apk

# Build release AAB
melos run app-build-aab
```

### Release Management

The release process uses **GitHub Actions** with centralized version management:

**Automated Release (Recommended):**
```bash
# Trigger release via GitHub CLI
gh workflow run release.yml \
  -f release_type=patch \
  -f publish_packages=true \
  -f create_release=true

# Or use the GitHub web interface:
# Actions → Release Management → Run workflow
```

**Manual Local Testing:**
```bash
# Update versions with automatic dependency management
dart run melos run version-minor

# No need for melos bootstrap - workspace handles dependencies automatically!
```

**Release Process Overview:**
1. **Version Update**: Root version is incremented, all packages updated to match
2. **Dependency Update**: Internal package dependencies synchronized  
3. **App Versioning**: App version updated with incremented build number
4. **Publishing**: All packages published to pub.dev with consistent versions
5. **Release Creation**: GitHub release created with the package version
6. **App Deployment**: Codemagic automatically deploys app to Play Store

## 🏗️ Architecture

### Core Gossip Protocol

The Gossip protocol implements **eventual consistency** through:

- **Vector Clocks**: Track causal relationships between events
- **Anti-Entropy**: Periodic synchronization to resolve inconsistencies
- **Peer Discovery**: Automatic discovery of nearby nodes
- **Event Propagation**: Efficient rumor spreading algorithm

```dart
// Basic usage example
final node = GossipNode(
  config: GossipConfig(nodeId: 'node1'),
  eventStore: MyEventStore(),
  transport: MyTransport(),
);

await node.start();
await node.createEvent({'type': 'message', 'content': 'Hello World!'});
```

### Extension Libraries

- **🔀 CRDTs**: Last-Writer-Wins, G-Counters, PN-Counters, G-Sets, etc.
- **📚 Event Sourcing**: Projections, Event Processors, CQRS patterns
- **🛡️ Typed Events**: Compile-time type safety with validation

### Demo Application

The [Gossip Chat app](./apps/gossip_chat/) demonstrates:

- **Offline P2P Messaging**: No internet required
- **Automatic Discovery**: Find nearby devices via Bluetooth/WiFi
- **Real-time Sync**: Messages appear instantly on all devices
- **Event Sourcing UI**: Reactive state management from events

## 📱 Demo App Features

### Core Functionality
- ✅ **Offline P2P Chat** - No internet connection required
- ✅ **Auto Device Discovery** - Finds nearby devices automatically  
- ✅ **Real-time Messaging** - Messages sync instantly across devices
- ✅ **User Management** - Join/leave notifications with avatars
- ✅ **Modern UI** - Material Design 3 with message bubbles
- ✅ **Smart Permissions** - Intelligent Android permission handling

### Technical Features
- ✅ **Event Sourcing Architecture** - Reactive state from events
- ✅ **Type-safe Events** - Compile-time validation
- ✅ **Persistent Storage** - Messages and state persist locally
- ✅ **Network Resilience** - Handles disconnections gracefully
- ✅ **Multi-device Support** - Connect multiple devices simultaneously

## 🚀 Deployment & CI/CD

### Automated Deployments

**📦 Packages to pub.dev**: Triggered automatically when packages change in `main` branch
- ✅ Pre-publish validation (tests, analysis, formatting)
- ✅ Automatic version detection and publishing
- ✅ Release notes and documentation updates

**📱 App to Play Store**: Triggered automatically on `main` branch pushes via Codemagic
- ✅ Automated builds with proper signing
- ✅ Internal track deployment for testing
- ✅ Production release when ready

### Manual Operations

```bash
# Trigger manual package release
gh workflow run release.yml -f release_type=patch -f publish_packages=true

# Check deployment status
./scripts/release.sh check

# Full release process
./scripts/release.sh full
```

### Setup Instructions

For complete deployment setup, see **[📖 DEPLOYMENT.md](./DEPLOYMENT.md)** which covers:

- 🔐 Android signing and keystore setup
- ☁️ Google Play Console configuration  
- 🤖 Codemagic CI/CD setup
- 📦 pub.dev publishing credentials
- 🔧 GitHub Actions configuration

## 🧪 Testing

### Package Tests
```bash
# Run all package tests
melos run test

# Test specific package
melos exec --scope="gossip" -- dart test
```

### App Tests
```bash
# Run app unit tests
cd apps/gossip_chat && flutter test

# Run integration tests
melos run app-test
```

### Manual Testing
The P2P chat app requires **physical Android devices** for testing:

1. Install APK on 2+ devices
2. Enable Bluetooth and Location
3. Open app and enter different names
4. Wait for automatic discovery (10-30 seconds)
5. Start chatting!

## 🤝 Contributing

### Development Workflow

1. **Fork and Clone**
   ```bash
   git clone https://github.com/yourusername/gossip-mono.git
   cd gossip-mono
   melos bootstrap
   ```

2. **Create Feature Branch**
   ```bash
   git checkout -b feature/amazing-feature
   ```

3. **Make Changes**
   ```bash
   # Ensure quality
   melos run test
   melos run analyze
   melos run format
   ```

4. **Submit PR**
   - All checks must pass
   - Include tests for new features
   - Update documentation as needed

### Code Standards

- ✅ Follow Dart/Flutter style guide
- ✅ Write comprehensive tests
- ✅ Document public APIs
- ✅ Use semantic commit messages
- ✅ Maintain backward compatibility

## 📊 Project Status

### Current State
- 🟢 **Packages**: Production ready, published to pub.dev
- 🟢 **Demo App**: Fully functional, Play Store ready
- 🟢 **CI/CD**: Automated publishing and deployment
- 🟢 **Documentation**: Comprehensive guides and examples

### Roadmap
- [ ] **iOS Support** - MultipeerConnectivity transport
- [ ] **Web Support** - WebRTC transport layer
- [ ] **Performance Optimization** - Large network scalability
- [ ] **Security Features** - End-to-end encryption
- [ ] **Monitoring** - Metrics and observability

## 📚 Documentation

- **[📖 Deployment Guide](./DEPLOYMENT.md)** - Complete setup and deployment instructions
- **[📱 App Documentation](./apps/gossip_chat/README.md)** - Chat app features and architecture
- **[🔄 Gossip Protocol](./packages/gossip/README.md)** - Core protocol documentation
- **[🏗️ Event Sourcing](./packages/gossip_event_sourcing/README.md)** - Event sourcing patterns
- **[🛡️ Typed Events](./packages/gossip_typed_events/README.md)** - Type-safe event system

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Flutter Team** - For the amazing cross-platform framework
- **Dart Team** - For the excellent language and tooling
- **Melos** - For monorepo management capabilities
- **Codemagic** - For seamless CI/CD automation

## 💬 Support & Community

- **🐛 Issues**: [GitHub Issues](https://github.com/da1nerd/gossip-mono/issues)
- **💡 Discussions**: [GitHub Discussions](https://github.com/da1nerd/gossip-mono/discussions)
- **📧 Contact**: Create an issue for questions and support

---

<div align="center">

**Made with ❤️ by the Gossip Protocol team**

[⭐ Star this repo](https://github.com/da1nerd/gossip-mono/stargazers) • [🔄 Fork it](https://github.com/da1nerd/gossip-mono/fork) • [📖 Read the docs](./DEPLOYMENT.md)

</div>