/// CRDT extensions for the gossip protocol library.
///
/// This library provides Conflict-free Replicated Data Type (CRDT) support
/// for the gossip protocol, enabling automatic conflict resolution and
/// convergent state synchronization across distributed nodes.
///
/// ## Features
///
/// - **Seamless Integration**: Extends existing GossipNode instances with CRDT capabilities
/// - **Multiple CRDT Types**: Counters, Sets, Registers, and Maps with conflict-free semantics
/// - **Automatic Synchronization**: CRDTs sync automatically through the gossip protocol
/// - **Type Safety**: Strongly typed CRDT operations with compile-time guarantees
/// - **Pluggable Storage**: Abstract storage interface for different persistence backends
///
/// ## Quick Start
///
/// ```dart
/// import 'package:gossip/gossip.dart';
/// import 'package:gossip_crdts/gossip_crdts.dart';
///
/// // Create a regular gossip node
/// final node = GossipNode(
///   config: GossipConfig(nodeId: 'node1'),
///   eventStore: MemoryEventStore(),
///   transport: MyTransport(),
/// );
///
/// await node.start();
///
/// // Enable CRDT support
/// final crdtManager = node.enableCRDTSupport();
///
/// // Register and use a counter CRDT
/// final counter = GCounter('shared-counter');
/// crdtManager.register(counter);
///
/// await crdtManager.performOperation('shared-counter', 'increment', {'amount': 5});
/// print('Counter value: ${counter.value}'); // Counter value: 5
/// ```
///
/// ## Supported CRDT Types
///
/// ### Counters
/// - **GCounter**: Grow-only counter (increment only)
/// - **PNCounter**: Increment/decrement counter
///
/// ### Sets
/// - **GSet**: Grow-only set (add only)
/// - **ORSet**: Observed-Remove set (add and remove)
///
/// ### Registers
/// - **LWWRegister**: Last-Writer-Wins register
/// - **MVRegister**: Multi-Value register (preserves concurrent updates)
///
/// ### Maps
/// - **ORMap**: Observed-Remove map with CRDT values
/// - **LWWMap**: Last-Writer-Wins map
///
/// ### Sequences
/// - **RGAArray**: Replicated Growable Array (ideal for text editing)
///
/// ### Flags
/// - **EnableWinsFlag**: Boolean flag where enable operations win
library gossip_crdts;

// Core CRDT functionality
export 'src/crdt_manager.dart';
export 'src/crdt_store.dart';

// Base CRDT interface and common types
export 'src/crdts/crdt.dart';

// Specific CRDT implementations
export 'src/crdts/g_counter.dart';
export 'src/crdts/pn_counter.dart';
export 'src/crdts/g_set.dart';
export 'src/crdts/or_set.dart';
export 'src/crdts/lww_register.dart';
export 'src/crdts/mv_register.dart';
export 'src/crdts/or_map.dart';
export 'src/crdts/lww_map.dart';
export 'src/crdts/rga_array.dart';
export 'src/crdts/enable_wins_flag.dart';

// Extensions for existing gossip nodes
export 'src/extensions/gossip_node_crdt_extension.dart';
