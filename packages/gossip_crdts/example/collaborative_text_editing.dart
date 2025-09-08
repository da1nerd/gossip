/// Collaborative Text Editing Example
///
/// This example demonstrates how to use the RGAArray CRDT for collaborative
/// text editing across multiple nodes. It shows how concurrent insertions
/// and deletions are handled consistently across all replicas.

import 'dart:async';
import 'dart:math';

import 'package:gossip/gossip.dart';
import 'package:gossip_crdts/gossip_crdts.dart';

/// Simple in-memory transport for the example
class TextEditingTransport implements GossipTransport {
  final String nodeId;
  final Map<String, TextEditingTransport> _network;

  final StreamController<IncomingDigest> _digestController =
      StreamController<IncomingDigest>.broadcast();
  final StreamController<IncomingEvents> _eventsController =
      StreamController<IncomingEvents>.broadcast();

  TextEditingTransport(this.nodeId, this._network);

  @override
  Future<void> initialize() async {
    _network[nodeId] = this;
  }

  @override
  Future<void> shutdown() async {
    _network.remove(nodeId);
    await _digestController.close();
    await _eventsController.close();
  }

  @override
  Future<GossipDigestResponse> sendDigest(
    TransportPeer transportPeer,
    GossipDigest digest, {
    Duration? timeout,
  }) async {
    final targetTransport = _network[transportPeer.transportId.value];
    if (targetTransport == null) {
      throw TransportException('Peer ${transportPeer.transportId} not found');
    }

    final completer = Completer<GossipDigestResponse>();
    final incomingDigest = IncomingDigest(
      fromTransportPeer: TransportPeer(
        transportId: TransportPeerAddress(nodeId),
        displayName: nodeId,
        connectedAt: DateTime.now(),
      ),
      digest: digest,
      respond: (response) async {
        completer.complete(response);
      },
    );

    targetTransport._digestController.add(incomingDigest);
    return completer.future;
  }

  @override
  Future<void> sendEvents(
    TransportPeer transportPeer,
    GossipEventMessage message, {
    Duration? timeout,
  }) async {
    final targetTransport = _network[transportPeer.transportId.value];
    if (targetTransport == null) {
      throw TransportException('Peer ${transportPeer.transportId} not found');
    }

    final incomingEvents = IncomingEvents(
      fromTransportPeer: TransportPeer(
        transportId: TransportPeerAddress(nodeId),
        displayName: nodeId,
        connectedAt: DateTime.now(),
      ),
      message: message,
    );

    targetTransport._eventsController.add(incomingEvents);
  }

  @override
  Stream<IncomingDigest> get incomingDigests => _digestController.stream;

  @override
  Stream<IncomingEvents> get incomingEvents => _eventsController.stream;

  @override
  Future<List<TransportPeer>> discoverPeers() async {
    return _network.keys
        .where((id) => id != nodeId)
        .map(
          (id) => TransportPeer(
            transportId: TransportPeerAddress(id),
            displayName: id,
            connectedAt: DateTime.now(),
          ),
        )
        .toList();
  }

  @override
  Future<bool> isPeerReachable(TransportPeer transportPeer) async {
    return _network.containsKey(transportPeer.transportId.value);
  }
}

/// Simulates a user editing text
class TextEditor {
  final String name;
  final CRDTEnabledGossipNode node;
  final RGAArray<String> textArray;
  final Random _random = Random();

  TextEditor({required this.name, required this.node, required this.textArray});

  /// Insert text at a random position
  Future<void> insertRandomText() async {
    final words = [
      'hello',
      'world',
      'collaborative',
      'text',
      'editing',
      'is',
      'cool',
    ];
    final word = words[_random.nextInt(words.length)];
    final currentLength = textArray.length;
    final position = currentLength > 0 ? _random.nextInt(currentLength + 1) : 0;

    print('📝 $name: Inserting "$word" at position $position');

    // Insert each character of the word
    for (int i = 0; i < word.length; i++) {
      await node.performCRDTOperation('shared-document', 'insert', {
        'index': position + i,
        'element': word[i],
      });
    }

    // Add a space after the word
    if (currentLength > 0) {
      await node.performCRDTOperation('shared-document', 'insert', {
        'index': position + word.length,
        'element': ' ',
      });
    }
  }

  /// Delete a random character
  Future<void> deleteRandomCharacter() async {
    final currentLength = textArray.length;
    if (currentLength == 0) return;

    final position = _random.nextInt(currentLength);
    final charToDelete = textArray[position];

    print('🗑️  $name: Deleting "$charToDelete" at position $position');

    await node.performCRDTOperation('shared-document', 'delete', {
      'index': position,
    });
  }

  /// Insert a new line
  Future<void> insertNewLine() async {
    final currentLength = textArray.length;
    final position = currentLength > 0 ? _random.nextInt(currentLength + 1) : 0;

    print('↵  $name: Inserting new line at position $position');

    await node.performCRDTOperation('shared-document', 'insert', {
      'index': position,
      'element': '\n',
    });
  }

  /// Perform a random editing operation
  Future<void> performRandomEdit() async {
    final weights = [0.6, 0.3, 0.1]; // 60% insert, 30% delete, 10% newline

    final rand = _random.nextDouble();
    if (rand < weights[0]) {
      await insertRandomText();
    } else if (rand < weights[0] + weights[1]) {
      await deleteRandomCharacter();
    } else {
      await insertNewLine();
    }
  }
}

void main() async {
  print('🚀 Starting Collaborative Text Editing Example\n');

  // Shared transport registry
  final transportRegistry = <String, TextEditingTransport>{};

  // Create multiple editor nodes
  final editors = <TextEditor>[];
  final editorNames = ['Alice', 'Bob', 'Charlie'];

  for (final name in editorNames) {
    final nodeId = name.toLowerCase();

    // Create gossip node with CRDT support
    final gossipNode = GossipNode(
      config: GossipConfig(
        nodeId: nodeId,
        gossipInterval: Duration(milliseconds: 200),
        fanout: 2,
      ),
      eventStore: MemoryEventStore(),
      transport: TextEditingTransport(nodeId, transportRegistry),
    );

    final crdtNode = await gossipNode.withCRDTSupport();
    await crdtNode.start();

    // Create shared text document
    final textArray = RGAArray<String>('shared-document');
    await crdtNode.registerCRDT(textArray);

    final editor = TextEditor(name: name, node: crdtNode, textArray: textArray);

    editors.add(editor);
    print('✅ Created editor for $name');
  }

  // Connect all nodes to each other
  print('\n🌐 Connecting editors...');
  for (int i = 0; i < editors.length; i++) {
    for (int j = 0; j < editors.length; j++) {
      if (i != j) {
        final peerName = editorNames[j].toLowerCase();
        editors[i].node.gossipNode.addPeer(
          GossipPeer(
            id: GossipPeerID(peerName),
            address: TransportPeerAddress('memory://$peerName'),
          ),
        );
      }
    }
  }

  // Allow time for peer discovery
  await Future.delayed(Duration(milliseconds: 500));

  // Set up event listeners for each editor
  for (final editor in editors) {
    editor.node.onCRDTOperation.listen((operationEvent) {
      final op = operationEvent.operation;
      final isLocal = operationEvent.source == CRDTOperationSource.local;
      final icon = isLocal ? '📤' : '📥';

      if (op.operation == 'insert') {
        final char = op.data['element'] as String;
        final index = op.data['index'] as int;
        print(
          '$icon ${editor.name}: ${op.operation} "$char" at $index from ${op.nodeId}',
        );
      } else if (op.operation == 'delete') {
        final index = op.data['index'] as int;
        print(
          '$icon ${editor.name}: ${op.operation} at $index from ${op.nodeId}',
        );
      }
    });
  }

  // Start with some initial text
  print('\n📄 Setting up initial document...');
  await editors[0].node.performCRDTOperation('shared-document', 'insert', {
    'index': 0,
    'element': 'C',
  });
  await editors[0].node.performCRDTOperation('shared-document', 'insert', {
    'index': 1,
    'element': 'o',
  });
  await editors[0].node.performCRDTOperation('shared-document', 'insert', {
    'index': 2,
    'element': 'l',
  });
  await editors[0].node.performCRDTOperation('shared-document', 'insert', {
    'index': 3,
    'element': 'l',
  });
  await editors[0].node.performCRDTOperation('shared-document', 'insert', {
    'index': 4,
    'element': 'a',
  });
  await editors[0].node.performCRDTOperation('shared-document', 'insert', {
    'index': 5,
    'element': 'b',
  });
  await editors[0].node.performCRDTOperation('shared-document', 'insert', {
    'index': 6,
    'element': ' ',
  });

  await Future.delayed(Duration(milliseconds: 300));

  // Display initial state
  print('\n📋 Initial document state:');
  for (final editor in editors) {
    print('${editor.name}: "${editor.textArray.getText()}"');
  }

  print('\n🎯 Starting collaborative editing session...\n');

  // Simulate collaborative editing for 15 seconds
  final editingTasks = <Future>[];

  for (final editor in editors) {
    editingTasks.add(_simulateEditing(editor, Duration(seconds: 15)));
  }

  // Wait for all editing to complete
  await Future.wait(editingTasks);

  print('\n⏳ Waiting for final synchronization...');
  await Future.delayed(Duration(seconds: 3));

  // Display final state
  print('\n📄 Final document state:');
  print('=' * 50);

  for (final editor in editors) {
    final text = editor.textArray.getText();
    final stats = {
      'length': editor.textArray.length,
      'total_elements': editor.textArray.totalElements,
      'deleted_elements': editor.textArray.deletedCount,
    };

    print('${editor.name}: "${text}"');
    print('  Stats: $stats');
    print('');
  }

  // Verify consistency
  print('🔍 Verifying consistency...');
  final firstText = editors[0].textArray.getText();
  bool isConsistent = true;

  for (int i = 1; i < editors.length; i++) {
    final currentText = editors[i].textArray.getText();
    if (currentText != firstText) {
      print('❌ Inconsistency detected!');
      print('  ${editors[0].name}: "$firstText"');
      print('  ${editors[i].name}: "$currentText"');
      isConsistent = false;
    }
  }

  if (isConsistent) {
    print('✅ All editors have consistent document state!');
    print('📊 Final document: "${firstText}"');
    print('📏 Length: ${firstText.length} characters');
    print('🧮 Total operations: ${editors[0].textArray.totalElements}');
    print('🗑️  Deleted elements: ${editors[0].textArray.deletedCount}');
  }

  // Display CRDT statistics
  print('\n📈 CRDT Statistics:');
  for (final editor in editors) {
    final stats = editor.node.getCRDTStats();
    print(
      '${editor.name}: ${stats.totalCRDTs} CRDTs, types: ${stats.crdtTypes}',
    );
  }

  // Demonstrate text editing features
  print('\n🧪 Demonstrating text editing features...');

  final testText = editors[0].textArray;
  print('Current text: "${testText.getText()}"');

  // Insert text at specific position
  await editors[0].node.performCRDTOperation('shared-document', 'insert', {
    'index': 0,
    'element': '[',
  });
  await editors[0].node.performCRDTOperation('shared-document', 'insert', {
    'index': testText.length + 1,
    'element': ']',
  });

  await Future.delayed(Duration(milliseconds: 300));

  print('After adding brackets: "${testText.getText()}"');

  // Clean shutdown
  print('\n🛑 Shutting down editors...');
  for (final editor in editors) {
    await editor.node.close();
  }

  print('✅ Collaborative Text Editing Example completed successfully!');
}

/// Simulate editing operations for a given duration
Future<void> _simulateEditing(TextEditor editor, Duration duration) async {
  final endTime = DateTime.now().add(duration);

  while (DateTime.now().isBefore(endTime)) {
    try {
      await editor.performRandomEdit();

      // Random delay between operations (50ms to 500ms)
      final delay = Duration(milliseconds: 50 + Random().nextInt(450));
      await Future.delayed(delay);
    } catch (e) {
      // Continue editing even if some operations fail
      print('⚠️  ${editor.name}: Edit operation failed: $e');
    }
  }

  print('⏹️  ${editor.name}: Finished editing session');
}
