import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:gossip/gossip.dart';
import 'package:nearby_connections/nearby_connections.dart';

/// Realization of [GossipTransport] using Nearby Connections API.
///
/// This transport provides automatic peer discovery and connection management
/// using Android's Nearby Connections API with Bluetooth and Wi-Fi Direct.
///
/// ## Architecture
///
/// This transport uses a two-tier peer management approach:
///
/// 1. **Transport Level**: Manages [TransportPeer] objects that represent
///    connections at the transport layer using nearby connections endpoint IDs.
///    These are temporary identifiers that change between sessions.
///
/// 2. **Gossip Level**: Creates temporary [GossipPeer] objects for interface
///    compatibility. The actual stable node IDs are revealed through the
///    gossip protocol handshake and managed by the [GossipNode].
///
/// This separation allows the transport to handle connection mechanics while
/// keeping node identity management at the application layer where it belongs.
///
/// Implements the full 3-phase gossip protocol:
/// 1. Digest phase: Exchange vector clocks to determine what events are missing
/// 2. Response phase: Send missing events and request needed events
/// 3. Events phase: Send the requested events
class NearbyConnectionsTransport implements GossipTransport {
  final String serviceId;
  final String userName;

  // Connection management - transport level peers
  final Map<TransportPeerAddress, TransportPeer> _connectedTransportPeers = {};
  final Map<TransportPeerAddress, String> _transportIdToDisplayName = {};
  final Set<String> _pendingConnections = {};
  final Map<String, int> _connectionAttempts = {};

  // Message handling
  final StreamController<IncomingDigest> _incomingDigestsController =
      StreamController.broadcast();
  final StreamController<IncomingEvents> _incomingEventsController =
      StreamController.broadcast();

  // Pending requests for the gossip protocol
  final Map<String, Completer<GossipDigestResponse>> _pendingDigestRequests =
      {};
  final Map<String, Completer<void>> _pendingEventRequests = {};

  bool _initialized = false;

  // Connection settings
  static const int _maxConnectionAttempts = 3;
  static const Duration _connectionRetryDelay = Duration(seconds: 2);
  static const int _maxConcurrentConnections = 8;
  static const Duration _defaultTimeout = Duration(seconds: 10);
  static const Duration _connectionThrottleDelay = Duration(milliseconds: 500);

  final Strategy _connectionStrategy;

  NearbyConnectionsTransport({
    required this.serviceId,
    required this.userName,
    Strategy connectionStrategy = Strategy.P2P_CLUSTER,
  }) : _connectionStrategy = connectionStrategy;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      debugPrint('🚀 Initializing NearbyConnectionsTransport for $userName');

      // Start advertising this device
      await _startAdvertising();
      debugPrint('📡 Started advertising successfully');

      // Start discovering other devices
      await _startDiscovery();
      debugPrint('🔍 Started discovery successfully');

      _initialized = true;
      debugPrint('✅ NearbyConnectionsTransport initialized successfully');
    } catch (e) {
      debugPrint('❌ Failed to initialize NearbyConnectionsTransport: $e');
      rethrow;
    }
  }

  Future<void> _startAdvertising() async {
    debugPrint('📡 Starting advertising with strategy: $_connectionStrategy');
    await Nearby().startAdvertising(
      userName,
      _connectionStrategy,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
      serviceId: serviceId,
    );
  }

  Future<void> _startDiscovery() async {
    debugPrint('🔍 Starting discovery with strategy: $_connectionStrategy');
    await Nearby().startDiscovery(
      userName,
      _connectionStrategy,
      onEndpointFound: _onEndpointFound,
      onEndpointLost: _onEndpointLost,
      serviceId: serviceId,
    );
  }

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    debugPrint('🤝 Connection initiated with $id: ${info.endpointName}');

    // Check connection limits before accepting
    if (_connectedTransportPeers.length >= _maxConcurrentConnections) {
      debugPrint('❌ Connection limit reached, rejecting connection from $id');
      try {
        Nearby().rejectConnection(id);
      } catch (e) {
        debugPrint('❌ Failed to reject connection with $id: $e');
      }
      return;
    }

    // Auto-accept all connections
    try {
      Nearby().acceptConnection(
        id,
        onPayLoadRecieved: _onPayloadReceived,
        onPayloadTransferUpdate: _onPayloadTransferUpdate,
      );
      debugPrint('✅ Auto-accepted connection with $id');
    } catch (e) {
      debugPrint('❌ Failed to accept connection with $id: $e');
    }
  }

  void _onConnectionResult(String id, Status status) {
    debugPrint('🔗 Connection result for $id: $status');

    _pendingConnections.remove(id);

    if (status == Status.CONNECTED) {
      final transportAddress = TransportPeerAddress(id);
      final displayName =
          _transportIdToDisplayName[transportAddress] ?? 'Unknown';
      final transportPeer = TransportPeer(
        transportId: transportAddress,
        displayName: displayName,
        connectedAt: DateTime.now(),
        isActive: true,
      );
      _connectedTransportPeers[transportAddress] = transportPeer;
      _connectionAttempts.remove(id);
      debugPrint(
        '🎉 Successfully connected to transport peer $id ($displayName) (Total: ${_connectedTransportPeers.length})',
      );
    } else {
      _connectedTransportPeers.remove(TransportPeerAddress(id));
      debugPrint('❌ Connection failed with $id: $status');
    }
  }

  void _onDisconnected(String id) {
    debugPrint('💔 Disconnected from transport peer $id');

    final transportAddress = TransportPeerAddress(id);
    _connectedTransportPeers.remove(transportAddress);
    _transportIdToDisplayName.remove(transportAddress);
    _pendingConnections.remove(id);
    _connectionAttempts.remove(id);

    // Cancel any pending requests for this peer
    _cancelPendingRequestsForPeer(id);

    debugPrint(
      '📊 Remaining transport peers: ${_connectedTransportPeers.length}',
    );
  }

  void _onEndpointFound(String id, String name, String serviceId) {
    debugPrint('🎯 FOUND DEVICE! ID: $id, Name: $name, Service: $serviceId');

    // Store display name for later use
    _transportIdToDisplayName[TransportPeerAddress(id)] = name;

    // Check connection limits before attempting connection
    if (_connectedTransportPeers.length + _pendingConnections.length >=
        _maxConcurrentConnections) {
      debugPrint(
        '⚠️ Connection limit reached, skipping connection to $name ($id)',
      );
      return;
    }

    // Skip if we've already tried too many times
    if ((_connectionAttempts[id] ?? 0) >= _maxConnectionAttempts) {
      debugPrint('⚠️ Max attempts reached for $name ($id), skipping');
      return;
    }

    // Throttle connection attempts
    Future.delayed(_connectionThrottleDelay, () {
      if (!_connectedTransportPeers.containsKey(id) &&
          !_pendingConnections.contains(id)) {
        _requestConnection(id, name);
      }
    });
  }

  void _onEndpointLost(String? id) {
    if (id != null) {
      debugPrint('📤 Lost device: $id');
      final transportAddress = TransportPeerAddress(id);
      _connectedTransportPeers.remove(transportAddress);
      _transportIdToDisplayName.remove(transportAddress);
    }
  }

  void _requestConnection(String id, String name) async {
    // Check if already connected or pending
    if (_connectedTransportPeers.containsKey(TransportPeerAddress(id)) ||
        _pendingConnections.contains(id)) {
      debugPrint('⚠️ Connection to $name ($id) already exists or is pending');
      return;
    }

    // Check connection attempts
    final attempts = _connectionAttempts[id] ?? 0;
    if (attempts >= _maxConnectionAttempts) {
      debugPrint('❌ Max connection attempts reached for $name ($id)');
      return;
    }

    _pendingConnections.add(id);
    _connectionAttempts[id] = attempts + 1;

    debugPrint(
      '📞 Requesting connection to $name ($id) (attempt ${attempts + 1}/$_maxConnectionAttempts)',
    );

    try {
      await Nearby().requestConnection(
        userName,
        id,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      debugPrint('❌ Failed to request connection to $id: $e');
      _pendingConnections.remove(id);

      if (attempts + 1 < _maxConnectionAttempts) {
        Timer(_connectionRetryDelay, () {
          _requestConnection(id, name);
        });
      }
    }
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type == PayloadType.BYTES) {
      final data = payload.bytes!;
      final message = utf8.decode(data);

      try {
        final json = jsonDecode(message) as Map<String, dynamic>;
        final messageType = json['type'] as String;

        debugPrint('📥 Received $messageType from $endpointId');

        switch (messageType) {
          case 'digest':
            _handleIncomingDigest(endpointId, json);
            break;
          case 'digest_response':
            _handleIncomingDigestResponse(endpointId, json);
            break;
          case 'events':
            _handleIncomingEvents(endpointId, json);
            break;
          case 'events_ack':
            _handleEventsAcknowledgment(endpointId, json);
            break;
          default:
            debugPrint('❌ Unknown message type: $messageType');
        }
      } catch (e) {
        debugPrint('❌ Error parsing message from $endpointId: $e');
      }
    }
  }

  void _onPayloadTransferUpdate(
    String endpointId,
    PayloadTransferUpdate update,
  ) {
    if (update.status == PayloadStatus.SUCCESS) {
      debugPrint('✅ Payload transfer successful to $endpointId');
    } else if (update.status == PayloadStatus.FAILURE) {
      debugPrint('❌ Payload transfer failed to $endpointId');
    }
  }

  void _handleIncomingDigest(String endpointId, Map<String, dynamic> json) {
    try {
      final digest = GossipDigest.fromJson(json['digest']);
      final requestId = json['requestId'] as String?;
      final transportPeer =
          _connectedTransportPeers[TransportPeerAddress(endpointId)];

      if (transportPeer == null) {
        debugPrint(
          '❌ Received digest from unknown transport peer: $endpointId',
        );
        return;
      }

      final incomingDigest = IncomingDigest(
        fromTransportPeer: transportPeer,
        digest: digest,
        respond: (response) =>
            _sendDigestResponse(endpointId, response, requestId),
      );

      _incomingDigestsController.add(incomingDigest);
    } catch (e) {
      debugPrint('❌ Error handling incoming digest from $endpointId: $e');
    }
  }

  void _handleIncomingDigestResponse(
    String endpointId,
    Map<String, dynamic> json,
  ) {
    try {
      final response = GossipDigestResponse.fromJson(json['response']);
      final requestId = json['requestId'] as String?;

      if (requestId != null && _pendingDigestRequests.containsKey(requestId)) {
        _pendingDigestRequests[requestId]!.complete(response);
        _pendingDigestRequests.remove(requestId);
      } else {
        debugPrint(
          '❌ Received digest response for unknown request: $requestId',
        );
      }
    } catch (e) {
      debugPrint('❌ Error handling digest response from $endpointId: $e');
    }
  }

  void _handleIncomingEvents(String endpointId, Map<String, dynamic> json) {
    try {
      final eventMessage = GossipEventMessage.fromJson(json['message']);
      final transportPeer =
          _connectedTransportPeers[TransportPeerAddress(endpointId)];

      if (transportPeer == null) {
        debugPrint(
          '❌ Received events from unknown transport peer: $endpointId',
        );
        return;
      }

      // Send acknowledgment
      _sendEventsAcknowledgment(endpointId, json['requestId'] as String?);

      final incomingEvents = IncomingEvents(
        fromTransportPeer: transportPeer,
        message: eventMessage,
      );

      _incomingEventsController.add(incomingEvents);
    } catch (e) {
      debugPrint('❌ Error handling incoming events from $endpointId: $e');
    }
  }

  void _handleEventsAcknowledgment(
    String endpointId,
    Map<String, dynamic> json,
  ) {
    try {
      final requestId = json['requestId'] as String?;

      if (requestId != null && _pendingEventRequests.containsKey(requestId)) {
        _pendingEventRequests[requestId]!.complete();
        _pendingEventRequests.remove(requestId);
      }
    } catch (e) {
      debugPrint('❌ Error handling events acknowledgment from $endpointId: $e');
    }
  }

  Future<void> _sendDigestResponse(
    String endpointId,
    GossipDigestResponse response,
    String? requestId,
  ) async {
    try {
      final message = {
        'type': 'digest_response',
        'response': response.toJson(),
        'requestId': requestId,
      };

      await _sendMessage(endpointId, message);
      debugPrint(
        '📤 Sent digest response to $endpointId for request $requestId',
      );
    } catch (e) {
      debugPrint('❌ Failed to send digest response to $endpointId: $e');
      rethrow;
    }
  }

  Future<void> _sendEventsAcknowledgment(
    String endpointId,
    String? requestId,
  ) async {
    try {
      final message = {
        'type': 'events_ack',
        'requestId': requestId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await _sendMessage(endpointId, message);
      debugPrint('📤 Sent events acknowledgment to $endpointId');
    } catch (e) {
      debugPrint('❌ Failed to send events acknowledgment to $endpointId: $e');
    }
  }

  Future<void> _sendMessage(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    final json = jsonEncode(message);
    final bytes = Uint8List.fromList(utf8.encode(json));

    await Nearby().sendBytesPayload(endpointId, bytes);
  }

  String _generateRequestId() {
    return '${serviceId}_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  }

  void _cancelPendingRequestsForPeer(String peerId) {
    // Cancel digest requests
    final digestKeysToRemove = <String>[];
    _pendingDigestRequests.forEach((key, completer) {
      if (key.startsWith(peerId)) {
        completer.completeError(
          TransportException('Peer disconnected: $peerId'),
        );
        digestKeysToRemove.add(key);
      }
    });
    for (final key in digestKeysToRemove) {
      _pendingDigestRequests.remove(key);
    }

    // Cancel event requests
    final eventKeysToRemove = <String>[];
    _pendingEventRequests.forEach((key, completer) {
      if (key.startsWith(peerId)) {
        completer.completeError(
          TransportException('Peer disconnected: $peerId'),
        );
        eventKeysToRemove.add(key);
      }
    });
    for (final key in eventKeysToRemove) {
      _pendingEventRequests.remove(key);
    }
  }

  @override
  Stream<IncomingDigest> get incomingDigests =>
      _incomingDigestsController.stream;

  @override
  Stream<IncomingEvents> get incomingEvents => _incomingEventsController.stream;

  @override
  Future<List<TransportPeer>> discoverPeers() async {
    if (!_initialized) {
      throw StateError('Transport not initialized');
    }

    return _connectedTransportPeers.values.toList();
  }

  @override
  Future<bool> isPeerReachable(TransportPeer transportPeer) async {
    if (!_initialized) {
      return false;
    }

    return _connectedTransportPeers.containsKey(transportPeer.transportId);
  }

  @override
  Future<GossipDigestResponse> sendDigest(
    TransportPeer transportPeer,
    GossipDigest digest, {
    Duration? timeout,
  }) async {
    if (!_initialized) {
      throw StateError('Transport not initialized');
    }

    if (!_connectedTransportPeers.containsKey(transportPeer.transportId)) {
      throw TransportException(
        'Transport peer ${transportPeer.transportId} is not connected',
      );
    }

    final requestId = _generateRequestId();
    final message = {
      'type': 'digest',
      'digest': digest.toJson(),
      'requestId': requestId,
    };

    final completer = Completer<GossipDigestResponse>();
    _pendingDigestRequests[requestId] = completer;

    try {
      await _sendMessage(transportPeer.transportId.value, message);
      debugPrint('📤 Sent digest to ${transportPeer.transportId}');

      // Wait for response with timeout
      final response = await completer.future.timeout(
        timeout ?? _defaultTimeout,
        onTimeout: () {
          _pendingDigestRequests.remove(requestId);
          throw TransportException(
            'Digest request to ${transportPeer.transportId} timed out',
          );
        },
      );

      return response;
    } catch (e) {
      _pendingDigestRequests.remove(requestId);
      rethrow;
    }
  }

  @override
  Future<void> sendEvents(
    TransportPeer transportPeer,
    GossipEventMessage message, {
    Duration? timeout,
  }) async {
    if (!_initialized) {
      throw StateError('Transport not initialized');
    }

    if (!_connectedTransportPeers.containsKey(transportPeer.transportId)) {
      throw TransportException(
        'Transport peer ${transportPeer.transportId} is not connected',
      );
    }

    final requestId = _generateRequestId();
    final messagePayload = {
      'type': 'events',
      'message': message.toJson(),
      'requestId': requestId,
    };

    final completer = Completer<void>();
    _pendingEventRequests[requestId] = completer;

    try {
      await _sendMessage(transportPeer.transportId.value, messagePayload);
      debugPrint('📤 Sent events to ${transportPeer.transportId}');

      // Wait for acknowledgment with timeout
      await completer.future.timeout(
        timeout ?? _defaultTimeout,
        onTimeout: () {
          _pendingEventRequests.remove(requestId);
          throw TransportException(
            'Events request to ${transportPeer.transportId} timed out',
          );
        },
      );
    } catch (e) {
      _pendingEventRequests.remove(requestId);
      rethrow;
    }
  }

  @override
  Future<void> shutdown() async {
    if (!_initialized) return;

    try {
      debugPrint('🛑 Shutting down NearbyConnectionsTransport...');

      // Cancel all pending requests
      for (final completer in _pendingDigestRequests.values) {
        completer.completeError(
          const TransportException('Transport shutting down'),
        );
      }
      _pendingDigestRequests.clear();

      for (final completer in _pendingEventRequests.values) {
        completer.completeError(
          const TransportException('Transport shutting down'),
        );
      }
      _pendingEventRequests.clear();

      // Stop Nearby Connections services
      await Nearby().stopAdvertising();
      debugPrint('⏹️ Stopped advertising');

      await Nearby().stopDiscovery();
      debugPrint('⏹️ Stopped discovery');

      await Nearby().stopAllEndpoints();
      debugPrint('⏹️ Stopped all endpoints');

      // Close streams
      await _incomingDigestsController.close();
      await _incomingEventsController.close();

      // Clear state
      _connectedTransportPeers.clear();
      _transportIdToDisplayName.clear();
      _pendingConnections.clear();
      _connectionAttempts.clear();
      _initialized = false;

      debugPrint('✅ NearbyConnectionsTransport shut down successfully');
    } catch (e) {
      debugPrint('❌ Error shutting down transport: $e');
    }
  }

  /// Get connection statistics for debugging
  Map<String, dynamic> getStats() {
    return {
      'initialized': _initialized,
      'connectedTransportPeers': _connectedTransportPeers.length,
      'pendingConnections': _pendingConnections.length,
      'connectionAttempts': _connectionAttempts.length,
      'pendingDigestRequests': _pendingDigestRequests.length,
      'pendingEventRequests': _pendingEventRequests.length,
      'transportIds': _connectedTransportPeers.keys.toList(),
      'pendingIds': _pendingConnections.toList(),
      'userName': userName,
      'serviceId': serviceId,
      'connectionStrategy': _connectionStrategy.toString(),
    };
  }

  /// Get the number of connected transport peers
  int get peerCount => _connectedTransportPeers.length;

  /// Check if we have any connected transport peers
  bool get hasConnectedPeers => _connectedTransportPeers.isNotEmpty;

  /// Get list of connected transport IDs
  List<String> get connectedPeerIds =>
      _connectedTransportPeers.keys.map((addr) => addr.value).toList();

  /// Get detailed connection status for debugging
  String getConnectionStatus() {
    final buffer = StringBuffer();
    buffer.writeln('=== Nearby Connections Transport Status ===');
    buffer.writeln('User Name: $userName');
    buffer.writeln('Service ID: $serviceId');
    buffer.writeln('Initialized: $_initialized');
    buffer.writeln('Strategy: $_connectionStrategy');
    buffer.writeln(
      'Connected Transport Peers: ${_connectedTransportPeers.length}',
    );
    buffer.writeln('Pending Connections: ${_pendingConnections.length}');
    buffer.writeln('Connection Attempts: ${_connectionAttempts.length}');
    buffer.writeln('Pending Digest Requests: ${_pendingDigestRequests.length}');
    buffer.writeln('Pending Event Requests: ${_pendingEventRequests.length}');

    if (_connectedTransportPeers.isNotEmpty) {
      buffer.writeln('\nConnected Transport Peers:');
      for (var transportPeer in _connectedTransportPeers.values) {
        buffer.writeln(
          '  • ${transportPeer.transportId} (${transportPeer.displayName}) - ${transportPeer.isActive ? "active" : "inactive"}',
        );
      }
    }

    if (_pendingConnections.isNotEmpty) {
      buffer.writeln('\nPending Connections:');
      for (final peerId in _pendingConnections) {
        buffer.writeln('  • $peerId');
      }
    }

    return buffer.toString();
  }
}
