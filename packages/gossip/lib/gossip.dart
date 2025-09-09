/// A Dart library for implementing gossip-based distributed event synchronization.
///
/// This library provides the core logic for gossip protocols, allowing nodes
/// to exchange and synchronize events in a distributed system. The library
/// is designed to be transport-agnostic, leaving networking and persistence
/// implementations to the application layer.
///
/// ## Features
///
/// - Event-based gossip protocol with vector clock causality tracking
/// - Pluggable storage backends via abstract interfaces
/// - Transport-agnostic design for flexible network implementations
/// - Configurable gossip behavior and timing
/// - Built-in duplicate detection and event ordering
///
/// ## Usage
///
/// ```dart
/// import 'package:gossip/gossip.dart';
///
/// // Create a gossip node with custom configuration
/// final config = GossipConfig(
///   nodeId: 'node-1',
///   gossipInterval: Duration(seconds: 1),
/// );
///
/// final node = GossipNode(
///   config: config,
///   eventStore: MyCustomEventStore(),
///   transport: MyNetworkTransport(),
/// );
///
/// // Create and broadcast events
/// await node.createEvent({'type': 'user_action', 'data': 'hello'});
///
/// // Start gossiping
/// await node.startGossiping();
/// ```
library gossip;

// Core exports
export 'src/event.dart';
export 'src/vector_clock.dart';
export 'src/event_store.dart';
export 'src/gossip_node.dart';
export 'src/gossip_config.dart';
export 'src/gossip_node_id.dart';
export 'src/gossip_peer.dart';
export 'src/transport.dart';
export 'src/exceptions.dart';

// Implementations
export 'src/stores/memory_event_store.dart';

// Vector clock persistence
export 'src/vector_clock_store.dart';
