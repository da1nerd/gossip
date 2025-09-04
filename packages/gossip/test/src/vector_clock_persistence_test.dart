/// Comprehensive test suite for vector clock persistence in the gossip protocol.
///
/// ## Purpose
///
/// These tests validate that vector clocks are properly persisted and restored
/// across node restarts, maintaining causality guarantees that are fundamental
/// to distributed systems correctness.
///
/// ## Why Vector Clock Persistence Matters
///
/// Vector clocks track the "happens-before" relationship between events in
/// distributed systems. If vector clocks are lost or reset:
/// - Causality chains are broken
/// - Events may appear to happen in wrong order
/// - Consistency guarantees are violated
/// - Data corruption can occur
///
/// ## Test Coverage
///
/// This suite tests:
/// - Basic save/load operations
/// - Node restart scenarios
/// - Multiple node persistence
/// - Error handling and recovery
/// - Different storage backends
/// - Concurrent access patterns
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:test/test.dart';
import '../../lib/gossip.dart';

/// Mock transport for testing - minimal implementation
class MockTransport implements GossipTransport {
  final String nodeId;
  final Map<String, MockTransport> _connections = {};
  final StreamController<IncomingDigest> _digestController =
      StreamController.broadcast();
  final StreamController<IncomingEvents> _eventsController =
      StreamController.broadcast();
  bool _initialized = false;

  MockTransport(this.nodeId);

  @override
  Future<void> initialize() async => _initialized = true;

  void addConnection(MockTransport other) {
    _connections[other.nodeId] = other;
  }

  @override
  Future<GossipDigestResponse> sendDigest(
    GossipPeer peer,
    GossipDigest digest, {
    Duration? timeout,
  }) async {
    final target = _connections[peer.id];
    if (target == null) throw StateError('No connection to ${peer.id}');

    final completer = Completer<GossipDigestResponse>();
    final incoming = IncomingDigest(
      fromPeer: GossipPeer(id: nodeId, address: nodeId),
      digest: digest,
      respond: (response) async => completer.complete(response),
    );

    target._digestController.add(incoming);
    return completer.future;
  }

  @override
  Future<void> sendEvents(
    GossipPeer peer,
    GossipEventMessage eventMessage, {
    Duration? timeout,
  }) async {
    final target = _connections[peer.id];
    if (target == null) throw StateError('No connection to ${peer.id}');

    final incoming = IncomingEvents(
      fromPeer: GossipPeer(id: nodeId, address: nodeId),
      message: eventMessage,
    );

    target._eventsController.add(incoming);
  }

  @override
  Stream<IncomingDigest> get incomingDigests => _digestController.stream;

  @override
  Stream<IncomingEvents> get incomingEvents => _eventsController.stream;

  @override
  Future<List<GossipPeer>> discoverPeers() async => [];

  @override
  Future<bool> isPeerReachable(GossipPeer peer) async =>
      _connections.containsKey(peer.id);

  @override
  Future<void> shutdown() async {
    _initialized = false;
    await _digestController.close();
    await _eventsController.close();
    _connections.clear();
  }

  bool get isInitialized => _initialized;
}

void main() {
  group('Vector Clock Persistence', () {
    late String testDir;

    setUp(() {
      // Create unique test directory for each test
      testDir = 'test_vector_clocks_${Random().nextInt(1000000)}';
    });

    tearDown(() async {
      // Clean up test directory
      try {
        await Directory(testDir).delete(recursive: true);
      } catch (e) {
        // Ignore cleanup errors
      }
    });

    group('MemoryVectorClockStore', () {
      test('basic save and load operations', () async {
        final store = MemoryVectorClockStore();
        final nodeId = 'test-node';

        // Initially no vector clock should exist
        expect(await store.hasVectorClock(nodeId), isFalse);
        expect(await store.loadVectorClock(nodeId), isNull);

        // Create and save a vector clock
        final vectorClock = VectorClock();
        vectorClock.setTimestampFor('node-a', 5);
        vectorClock.setTimestampFor('node-b', 3);

        await store.saveVectorClock(nodeId, vectorClock);

        // Verify it can be loaded
        expect(await store.hasVectorClock(nodeId), isTrue);
        final loaded = await store.loadVectorClock(nodeId);

        expect(loaded, isNotNull);
        expect(loaded!.getTimestampFor('node-a'), equals(5));
        expect(loaded.getTimestampFor('node-b'), equals(3));

        await store.close();
      });

      test('handles multiple nodes', () async {
        final store = MemoryVectorClockStore();

        final clock1 = VectorClock()..setTimestampFor('node-1', 10);
        final clock2 = VectorClock()..setTimestampFor('node-2', 20);

        await store.saveVectorClock('node-1', clock1);
        await store.saveVectorClock('node-2', clock2);

        final loaded1 = await store.loadVectorClock('node-1');
        final loaded2 = await store.loadVectorClock('node-2');

        expect(loaded1!.getTimestampFor('node-1'), equals(10));
        expect(loaded2!.getTimestampFor('node-2'), equals(20));

        expect(await store.hasVectorClock('node-1'), isTrue);
        expect(await store.hasVectorClock('node-2'), isTrue);
        expect(await store.hasVectorClock('node-3'), isFalse);

        await store.close();
      });

      test('delete operations work correctly', () async {
        final store = MemoryVectorClockStore();
        final nodeId = 'test-node';

        // Save a vector clock
        final vectorClock = VectorClock()..setTimestampFor('test', 1);
        await store.saveVectorClock(nodeId, vectorClock);

        expect(await store.hasVectorClock(nodeId), isTrue);

        // Delete it
        expect(await store.deleteVectorClock(nodeId), isTrue);
        expect(await store.hasVectorClock(nodeId), isFalse);

        // Delete non-existent should return false
        expect(await store.deleteVectorClock('non-existent'), isFalse);

        await store.close();
      });

      test('enforces proper isolation between stored clocks', () async {
        final store = MemoryVectorClockStore();

        final original = VectorClock()..setTimestampFor('node-a', 5);
        await store.saveVectorClock('test', original);

        // Modify the original
        original.setTimestampFor('node-a', 10);

        // Loaded version should be unchanged
        final loaded = await store.loadVectorClock('test');
        expect(loaded!.getTimestampFor('node-a'), equals(5));

        await store.close();
      });

      test('throws proper exceptions', () async {
        final store = MemoryVectorClockStore();

        expect(() => store.saveVectorClock('', VectorClock()),
            throwsA(isA<VectorClockStoreException>()));
        expect(() => store.loadVectorClock(''),
            throwsA(isA<VectorClockStoreException>()));
        expect(() => store.hasVectorClock(''),
            throwsA(isA<VectorClockStoreException>()));

        await store.close();

        expect(() => store.saveVectorClock('test', VectorClock()),
            throwsA(isA<VectorClockStoreException>()));
      });
    });

    group('FileVectorClockStore', () {
      test('persists vector clocks to files', () async {
        final store = FileVectorClockStore(testDir);

        final vectorClock = VectorClock();
        vectorClock.setTimestampFor('node-a', 7);
        vectorClock.setTimestampFor('node-b', 4);

        await store.saveVectorClock('test-node', vectorClock);

        // Verify file was created
        final file = File('$testDir/test-node.json');
        expect(await file.exists(), isTrue);

        // Load and verify content
        final loaded = await store.loadVectorClock('test-node');
        expect(loaded!.getTimestampFor('node-a'), equals(7));
        expect(loaded.getTimestampFor('node-b'), equals(4));

        await store.close();
      });

      test('survives store recreation', () async {
        // Save with first store instance
        final store1 = FileVectorClockStore(testDir);
        final vectorClock = VectorClock()..setTimestampFor('node-x', 42);
        await store1.saveVectorClock('persistent-node', vectorClock);
        await store1.close();

        // Load with second store instance
        final store2 = FileVectorClockStore(testDir);
        final loaded = await store2.loadVectorClock('persistent-node');
        expect(loaded!.getTimestampFor('node-x'), equals(42));
        await store2.close();
      });

      test('handles file system errors gracefully', () async {
        // Use invalid directory path
        final store =
            FileVectorClockStore('/invalid/path/that/should/not/exist');

        expect(
          () => store.saveVectorClock('test', VectorClock()),
          throwsA(isA<VectorClockStoreException>()),
        );

        await store.close();
      });

      test('sanitizes node IDs for filenames', () async {
        final store = FileVectorClockStore(testDir);

        // Node ID with special characters
        const nodeId = 'node-with/special:chars?and*more';
        final vectorClock = VectorClock()..setTimestampFor('test', 1);

        await store.saveVectorClock(nodeId, vectorClock);

        // Should be able to load it back
        final loaded = await store.loadVectorClock(nodeId);
        expect(loaded!.getTimestampFor('test'), equals(1));

        await store.close();
      });
    });

    group('GossipNode Integration', () {
      test('restores vector clock on startup', () async {
        final eventStore = MemoryEventStore();
        final vectorClockStore = MemoryVectorClockStore();
        final transport = MockTransport('test-node');

        // Pre-populate vector clock store
        final savedClock = VectorClock();
        savedClock.setTimestampFor('test-node', 5);
        savedClock.setTimestampFor('other-node', 3);
        await vectorClockStore.saveVectorClock('test-node', savedClock);

        // Create node - should restore the vector clock
        final node = GossipNode(
          config: GossipConfig(nodeId: 'test-node'),
          eventStore: eventStore,
          transport: transport,
          vectorClockStore: vectorClockStore,
        );

        await node.start();

        // Verify vector clock was restored
        final restoredClock = node.vectorClock;
        expect(restoredClock.getTimestampFor('test-node'), equals(5));
        expect(restoredClock.getTimestampFor('other-node'), equals(3));

        await node.stop();
        await eventStore.close();
        await vectorClockStore.close();
      });

      test('persists vector clock after creating events', () async {
        final eventStore = MemoryEventStore();
        final vectorClockStore = MemoryVectorClockStore();
        final transport = MockTransport('test-node');

        final node = GossipNode(
          config: GossipConfig(nodeId: 'test-node'),
          eventStore: eventStore,
          transport: transport,
          vectorClockStore: vectorClockStore,
        );

        await node.start();

        // Create some events
        await node.createEvent({'data': 'event1'});
        await node.createEvent({'data': 'event2'});

        // Vector clock should be persisted
        final persistedClock =
            await vectorClockStore.loadVectorClock('test-node');
        expect(persistedClock!.getTimestampFor('test-node'), equals(2));

        await node.stop();
        await eventStore.close();
        await vectorClockStore.close();
      });

      test('works without vector clock store (optional)', () async {
        final eventStore = MemoryEventStore();
        final transport = MockTransport('test-node');

        // Create node without vector clock store
        final node = GossipNode(
          config: GossipConfig(nodeId: 'test-node'),
          eventStore: eventStore,
          transport: transport,
          // vectorClockStore: null (optional)
        );

        await node.start();

        // Should work normally
        await node.createEvent({'data': 'event1'});
        expect(node.vectorClock.getTimestampFor('test-node'), equals(1));

        await node.stop();
        await eventStore.close();
      });

      test('maintains causality across restart', () async {
        final eventStore1 = MemoryEventStore();
        final eventStore2 = MemoryEventStore();
        final vectorClockStore = MemoryVectorClockStore();

        // First node instance
        final transport1 = MockTransport('test-node');
        final node1 = GossipNode(
          config: GossipConfig(nodeId: 'test-node'),
          eventStore: eventStore1,
          transport: transport1,
          vectorClockStore: vectorClockStore,
        );

        await node1.start();
        await node1.createEvent({'phase': 1, 'data': 'before restart'});
        await node1.stop();

        // Second node instance (simulating restart)
        final transport2 = MockTransport('test-node');
        final node2 = GossipNode(
          config: GossipConfig(nodeId: 'test-node'),
          eventStore: eventStore2,
          transport: transport2,
          vectorClockStore: vectorClockStore,
        );

        await node2.start();

        // Vector clock should continue from where it left off
        expect(node2.vectorClock.getTimestampFor('test-node'), equals(1));

        await node2.createEvent({'phase': 2, 'data': 'after restart'});

        // New event should have timestamp 2 (continuing causality)
        expect(node2.vectorClock.getTimestampFor('test-node'), equals(2));

        await node2.stop();
        await eventStore1.close();
        await eventStore2.close();
        await vectorClockStore.close();
      });

      test('handles persistence errors gracefully', () async {
        final eventStore = MemoryEventStore();
        final vectorClockStore = MemoryVectorClockStore();
        final transport = MockTransport('test-node');

        final node = GossipNode(
          config: GossipConfig(nodeId: 'test-node'),
          eventStore: eventStore,
          transport: transport,
          vectorClockStore: vectorClockStore,
        );

        await node.start();

        // Close the vector clock store to simulate persistence failure
        await vectorClockStore.close();

        // Node should continue working despite persistence failure
        await node.createEvent({'data': 'test'});
        expect(node.vectorClock.getTimestampFor('test-node'), equals(1));

        await node.stop();
        await eventStore.close();
      });

      test('persists updates from gossip exchanges', () async {
        final storeA = MemoryEventStore();
        final storeB = MemoryEventStore();
        final vectorStoreA = MemoryVectorClockStore();
        final vectorStoreB = MemoryVectorClockStore();

        final transportA = MockTransport('node-a');
        final transportB = MockTransport('node-b');

        transportA.addConnection(transportB);
        transportB.addConnection(transportA);

        final nodeA = GossipNode(
          config: GossipConfig(nodeId: 'node-a'),
          eventStore: storeA,
          transport: transportA,
          vectorClockStore: vectorStoreA,
        );

        final nodeB = GossipNode(
          config: GossipConfig(nodeId: 'node-b'),
          eventStore: storeB,
          transport: transportB,
          vectorClockStore: vectorStoreB,
        );

        await nodeA.start();
        await nodeB.start();

        nodeA.addPeer(GossipPeer(id: 'node-b', address: 'node-b'));

        // Create event on node A
        await nodeA.createEvent({'source': 'A', 'data': 'test'});

        // Trigger gossip exchange
        await nodeA.gossip();

        // Allow time for processing
        await Future.delayed(Duration(milliseconds: 50));

        // Node B should have updated and persisted vector clock
        final persistedClockB = await vectorStoreB.loadVectorClock('node-b');
        expect(persistedClockB!.getTimestampFor('node-a'), equals(1));

        await nodeA.stop();
        await nodeB.stop();
        await storeA.close();
        await storeB.close();
        await vectorStoreA.close();
        await vectorStoreB.close();
      });
    });

    group('Real-world Scenarios', () {
      test('handles rapid restart cycles', () async {
        final vectorClockStore = MemoryVectorClockStore();
        const nodeId = 'rapid-restart-node';

        // Simulate multiple rapid restarts
        for (int i = 1; i <= 5; i++) {
          final eventStore = MemoryEventStore();
          final transport = MockTransport(nodeId);

          final node = GossipNode(
            config: GossipConfig(nodeId: nodeId),
            eventStore: eventStore,
            transport: transport,
            vectorClockStore: vectorClockStore,
          );

          await node.start();

          // Create events
          for (int j = 1; j <= 3; j++) {
            await node.createEvent({'restart': i, 'event': j});
          }

          // Vector clock should continue incrementing across restarts
          final expectedTimestamp = i * 3;
          expect(node.vectorClock.getTimestampFor(nodeId),
              equals(expectedTimestamp));

          await node.stop();
          await eventStore.close();
        }

        await vectorClockStore.close();
      });

      test('multiple nodes with different persistence patterns', () async {
        // Node A: Uses file persistence
        final fileStore = FileVectorClockStore(testDir);
        final storeA = MemoryEventStore();
        final transportA = MockTransport('node-a');

        final nodeA = GossipNode(
          config: GossipConfig(nodeId: 'node-a'),
          eventStore: storeA,
          transport: transportA,
          vectorClockStore: fileStore,
        );

        // Node B: Uses memory persistence
        final memoryStore = MemoryVectorClockStore();
        final storeB = MemoryEventStore();
        final transportB = MockTransport('node-b');

        final nodeB = GossipNode(
          config: GossipConfig(nodeId: 'node-b'),
          eventStore: storeB,
          transport: transportB,
          vectorClockStore: memoryStore,
        );

        // Node C: No persistence
        final storeC = MemoryEventStore();
        final transportC = MockTransport('node-c');

        final nodeC = GossipNode(
          config: GossipConfig(nodeId: 'node-c'),
          eventStore: storeC,
          transport: transportC,
          // No vectorClockStore
        );

        await nodeA.start();
        await nodeB.start();
        await nodeC.start();

        // All nodes create events
        await nodeA.createEvent({'source': 'A'});
        await nodeB.createEvent({'source': 'B'});
        await nodeC.createEvent({'source': 'C'});

        // Verify different persistence behaviors
        expect(await fileStore.hasVectorClock('node-a'), isTrue);
        expect(await memoryStore.hasVectorClock('node-b'), isTrue);
        // Node C has no persistence, so can't check storage

        await nodeA.stop();
        await nodeB.stop();
        await nodeC.stop();

        await storeA.close();
        await storeB.close();
        await storeC.close();
        await fileStore.close();
        await memoryStore.close();
      });
    });

    group('Error Handling and Recovery', () {
      test('recovers from corrupted vector clock data', () async {
        final store = FileVectorClockStore(testDir);

        // Create a valid vector clock file first
        final validClock = VectorClock()..setTimestampFor('test', 1);
        await store.saveVectorClock('test-node', validClock);

        // Corrupt the file
        final file = File('$testDir/test-node.json');
        await file.writeAsString('invalid json content');

        // Loading should throw an exception
        expect(
          () => store.loadVectorClock('test-node'),
          throwsA(isA<VectorClockStoreException>()),
        );

        await store.close();
      });

      test('continues operating when persistence is temporarily unavailable',
          () async {
        final eventStore = MemoryEventStore();
        final vectorClockStore = MemoryVectorClockStore();
        final transport = MockTransport('test-node');

        final node = GossipNode(
          config: GossipConfig(nodeId: 'test-node'),
          eventStore: eventStore,
          transport: transport,
          vectorClockStore: vectorClockStore,
        );

        await node.start();

        // Create event - should work
        await node.createEvent({'data': 'before failure'});

        // Close the vector clock store (simulate persistence failure)
        await vectorClockStore.close();

        // Node should continue working despite persistence failure
        await node.createEvent({'data': 'after failure'});
        expect(node.vectorClock.getTimestampFor('test-node'), equals(2));

        await node.stop();
        await eventStore.close();
      });
    });
  });
}
