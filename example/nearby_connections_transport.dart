/// Example implementation of SimpleGossipTransport using nearby connections.
///
/// This demonstrates how to create a transport implementation that uses
/// Android's Nearby Connections API for peer-to-peer communication.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:gossip/gossip.dart';
// Note: In a real implementation, you would add nearby_connections as a dependency
// import 'package:nearby_connections/nearby_connections.dart';

/// Example transport using Android Nearby Connections API.
///
/// This transport provides automatic peer discovery and connection management
/// using Bluetooth and WiFi Direct. It's perfect for mobile applications that
/// need to work without internet connectivity.
class NearbyConnectionsTransport implements SimpleGossipTransport {
  final String serviceId;
  final String userName;

  final Set<String> _connectedPeers = {};
  final StreamController<Event> _incomingEventsController =
      StreamController.broadcast();

  bool _initialized = false;

  NearbyConnectionsTransport({
    required this.serviceId,
    required this.userName,
  });

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Start advertising this device
      await _startAdvertising();

      // Start discovering other devices
      await _startDiscovery();

      _initialized = true;
      print('✅ NearbyConnectionsTransport initialized');
    } catch (e) {
      print('❌ Failed to initialize transport: $e');
      rethrow;
    }
  }

  Future<void> _startAdvertising() async {
    // In a real implementation, this would use nearby_connections:
    /*
    await Nearby().startAdvertising(
      userName,
      Strategy.P2P_CLUSTER,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
      serviceId: serviceId,
    );
    */
    print('📡 Started advertising as: $userName');
  }

  Future<void> _startDiscovery() async {
    // In a real implementation, this would use nearby_connections:
    /*
    await Nearby().startDiscovery(
      userName,
      Strategy.P2P_CLUSTER,
      onEndpointFound: _onEndpointFound,
      onEndpointLost: _onEndpointLost,
      serviceId: serviceId,
    );
    */
    print('🔍 Started discovering nearby devices');
  }

  // Mock connection callbacks for demonstration
  void _onConnectionInitiated(String id, dynamic info) {
    print('🤝 Connection initiated with $id');
    // Auto-accept connections
    _acceptConnection(id);
  }

  void _onConnectionResult(String id, dynamic status) {
    print('🔗 Connection result for $id: $status');
    if (status.toString() == 'CONNECTED') {
      _connectedPeers.add(id);
      print('🎉 Successfully connected to peer $id');
    } else {
      _connectedPeers.remove(id);
      print('❌ Connection failed with $id');
    }
  }

  void _onDisconnected(String id) {
    print('💔 Disconnected from peer $id');
    _connectedPeers.remove(id);
  }

  void _onEndpointFound(String id, String name, String serviceId) {
    print('🎯 Found device: $name ($id)');
    // Automatically request connection
    _requestConnection(id, name);
  }

  void _onEndpointLost(String? id) {
    if (id != null) {
      print('📤 Lost device: $id');
      _connectedPeers.remove(id);
    }
  }

  void _acceptConnection(String id) {
    // In a real implementation:
    /*
    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: _onPayloadReceived,
      onPayloadTransferUpdate: _onPayloadTransferUpdate,
    );
    */
    print('✅ Accepted connection with $id');
  }

  void _requestConnection(String id, String name) {
    // In a real implementation:
    /*
    Nearby().requestConnection(
      userName,
      id,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    );
    */
    print('📞 Requesting connection to $name ($id)');
  }

  void _onPayloadReceived(String endpointId, dynamic payload) {
    // In a real implementation, payload would be of type Payload
    print('📥 Received payload from $endpointId');

    try {
      // Mock payload processing
      final data = payload.bytes as Uint8List;
      final message = utf8.decode(data);
      final json = jsonDecode(message) as Map<String, dynamic>;
      final event = Event.fromJson(json);

      _incomingEventsController.add(event);
    } catch (e) {
      print('❌ Error parsing payload from $endpointId: $e');
    }
  }

  void _onPayloadTransferUpdate(String endpointId, dynamic update) {
    // Handle transfer progress if needed
    print('📊 Transfer update for $endpointId: ${update.status}');
  }

  @override
  Future<void> broadcastEvent(Event event) async {
    if (!_initialized) {
      throw StateError('Transport not initialized');
    }

    final message = jsonEncode(event.toJson());
    final bytes = Uint8List.fromList(utf8.encode(message));

    print('📤 Broadcasting event to ${_connectedPeers.length} peers');

    // Send to all connected peers
    for (final peerId in _connectedPeers) {
      try {
        // In a real implementation:
        // await Nearby().sendBytesPayload(peerId, bytes);
        print('✉️  Sent event to peer $peerId');
      } catch (e) {
        print('❌ Failed to send event to $peerId: $e');
      }
    }
  }

  @override
  Stream<Event> get incomingEvents => _incomingEventsController.stream;

  Future<void> sendEventToPeer(String peerId, Event event) async {
    if (!_initialized) {
      throw StateError('Transport not initialized');
    }

    if (!_connectedPeers.contains(peerId)) {
      print('⚠️ Peer $peerId is not connected, cannot send event');
      return;
    }

    final message = jsonEncode(event.toJson());
    final bytes = Uint8List.fromList(utf8.encode(message));

    try {
      // In a real implementation:
      // await Nearby().sendBytesPayload(peerId, bytes);
      print('✉️ Sent event ${event.id} to peer $peerId');
    } catch (e) {
      print('❌ Failed to send event to $peerId: $e');
      // Remove failed peer from connected list
      _connectedPeers.remove(peerId);
      rethrow;
    }
  }

  @override
  List<String> get connectedPeerIds => _connectedPeers.toList();

  @override
  Future<void> dispose() async {
    if (!_initialized) return;

    try {
      // In a real implementation:
      /*
      await Nearby().stopAdvertising();
      await Nearby().stopDiscovery();
      await Nearby().stopAllEndpoints();
      */
      print('🛑 Stopped nearby connections services');

      await _incomingEventsController.close();
      _connectedPeers.clear();
      _initialized = false;

      print('✅ NearbyConnectionsTransport disposed');
    } catch (e) {
      print('❌ Error disposing transport: $e');
    }
  }

  /// Get connection statistics
  Map<String, dynamic> getStats() {
    return {
      'initialized': _initialized,
      'connectedPeers': _connectedPeers.length,
      'peerIds': _connectedPeers.toList(),
    };
  }
}

/// Example usage of the NearbyConnectionsTransport
void main() async {
  print('🚀 Starting Nearby Connections Gossip Example\n');

  // Create transport
  final transport = NearbyConnectionsTransport(
    serviceId: 'com.example.gossip_demo',
    userName: 'TestDevice',
  );

  // Create simple gossip node
  final node = SimpleGossipNode(
    nodeId: 'device-1',
    transport: transport,
    eventStore: MemoryEventStore(),
  );

  // Set up event listeners
  node.onEventCreated.listen((event) {
    print('📝 Created event: ${event.payload}');
  });

  node.onEventReceived.listen((event) {
    print('📨 Received event: ${event.payload} from ${event.nodeId}');
  });

  node.onPeerJoined.listen((peerId) {
    print('👋 Peer joined: $peerId');
  });

  node.onPeerLeft.listen((peerId) {
    print('👋 Peer left: $peerId');
  });

  try {
    // Start the node
    await node.start();
    print('✅ Gossip node started successfully\n');

    // Create some test events
    await node.createEvent({
      'type': 'test_message',
      'content': 'Hello from device-1!',
      'timestamp': DateTime.now().toIso8601String(),
    });

    await node.createEvent({
      'type': 'user_action',
      'action': 'login',
      'user': 'alice',
    });

    print('\n📊 Transport Stats: ${transport.getStats()}');

    // In a real app, you would keep the node running
    print('\n⏳ Node running... (In a real app, this would continue)');

    // Simulate running for a bit
    await Future.delayed(Duration(seconds: 5));

    // Clean shutdown
    print('\n🛑 Shutting down...');
    await node.stop();
    print('✅ Example completed successfully!');
  } catch (e) {
    print('❌ Error: $e');
  }
}

/// Example typed events for use with the transport

class ChatMessage extends TypedEvent {
  final String senderId;
  final String senderName;
  final String content;
  final DateTime timestamp;

  ChatMessage({
    required this.senderId,
    required this.senderName,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String get type => 'chat_message';

  @override
  Map<String, dynamic> toJson() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'content': content,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  static ChatMessage fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String,
      content: json['content'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
    );
  }

  @override
  String toString() {
    return '[$senderName]: $content';
  }
}

class UserJoinedEvent extends TypedEvent {
  final String userId;
  final String userName;
  final DateTime timestamp;

  UserJoinedEvent({
    required this.userId,
    required this.userName,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String get type => 'user_joined';

  @override
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'userName': userName,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  static UserJoinedEvent fromJson(Map<String, dynamic> json) {
    return UserJoinedEvent(
      userId: json['userId'] as String,
      userName: json['userName'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
    );
  }

  @override
  String toString() {
    return '$userName joined the chat';
  }
}
