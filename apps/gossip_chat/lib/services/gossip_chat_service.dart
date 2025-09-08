import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gossip/gossip.dart';
import 'package:gossip_chat_demo/models/chat_message.dart';
import 'package:gossip_chat_demo/models/chat_peer.dart';
import 'package:gossip_chat_demo/services/shared_prefs_vector_clock_store.dart';
import 'package:gossip_chat_demo/services/hive_event_store.dart';
import 'package:gossip_chat_demo/services/hive_projection_store.dart';
import 'package:gossip_chat_demo/services/event_sourcing/projections/chat_projection.dart';
import 'package:gossip_chat_demo/models/chat_events.dart';
import 'package:gossip_event_sourcing/gossip_event_sourcing.dart';
import 'package:gossip_typed_events/gossip_typed_events.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'nearby_connections_transport.dart';
import 'permissions_service.dart';

/// Chat service using the GossipNode.
///
/// This service provides a clean, type-safe interface for chat functionality
/// using the gossip protocol for event synchronization across devices.
class GossipChatService extends ChangeNotifier {
  static const String _userNameKey = 'user_name';
  static const String _userIdKey = 'user_id';
  static const String _serviceId = 'gossip_chat_demo';

  String? _nodeId;
  String? _nodeName;
  late final NearbyConnectionsTransport _transport;
  late final GossipNode _gossipNode;
  late final HiveEventStore _eventStore;
  late final HiveProjectionStore _projectionStore;

  // Event Sourcing components
  late final EventProcessor _eventProcessor;
  final ChatProjection _chatProjection = ChatProjection();

  StreamSubscription<Event>? _eventCreatedSubscription;
  StreamSubscription<ReceivedEvent>? _eventReceivedSubscription;
  StreamSubscription<GossipPeer>? _peerAddedSubscription;
  StreamSubscription<GossipPeer>? _peerRemovedSubscription;

  bool _isInitialized = false;
  bool _isStarted = false;
  String? _error;

  GossipChatService() {
    _setupEventSourcing();
    _registerTypedEvents();
  }

  void _setupEventSourcing() {
    // Listen to projection changes and notify UI
    _chatProjection.addListener(() {
      notifyListeners();
    });

    debugPrint('✅ Event Sourcing architecture initialized');
  }

  void _registerTypedEvents() {
    // Register all chat event types in the global registry
    ChatEventRegistry.registerAll();
    debugPrint('✅ Typed events registered');
  }

  Future<void> _initializeComponents() async {
    if (_nodeId == null || _nodeName == null) {
      throw StateError(
        'User ID and name must be set before initializing components',
      );
    }

    // Create transport
    _transport = NearbyConnectionsTransport(
      serviceId: _serviceId,
      userName: _nodeName!,
    );

    // Create event store
    _eventStore = HiveEventStore();

    // Create projection store (optional performance optimization)
    _projectionStore = HiveProjectionStore();
    await _projectionStore.initialize();

    // Create event processor with projection store support
    _eventProcessor = EventProcessor(
      projectionStore: _projectionStore,
      storeConfig: const ProjectionStoreConfig(
        autoSaveEnabled: true,
        autoSaveInterval: 1, // Save every 100 events
        saveAfterBatch: true,
        loadOnRebuild: true,
      ),
      logger: debugPrint,
    );

    // Register projections
    _eventProcessor.registerProjection(_chatProjection);

    // Create gossip node with chat-optimized configuration
    final config = GossipConfig(
      nodeId: _nodeId!,
      gossipInterval: const Duration(seconds: 2),
      fanout: 3,
      gossipTimeout: const Duration(seconds: 8),
      maxEventsPerMessage: 50,
      enableAntiEntropy: true,
      antiEntropyInterval: const Duration(minutes: 2),
      peerDiscoveryInterval: const Duration(seconds: 1),
    );

    _gossipNode = GossipNode(
      config: config,
      eventStore: _eventStore,
      transport: _transport,
      vectorClockStore: SharedPrefsVectorClockStore(),
    );

    // Note: User will be added through presence announcement events
  }

  /// Set the user ID for this chat service.
  void setUserId(String userId) {
    if (_isInitialized) {
      throw StateError('Cannot change user ID after service is initialized');
    }
    _nodeId = userId;
    notifyListeners();
  }

  /// Set the user name for this chat service.
  Future<void> setUserName(String userName) async {
    if (_isInitialized) {
      throw StateError('Cannot change user name after service is initialized');
    }

    _nodeName = userName.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userNameKey, _nodeName!);

    debugPrint('✅ Username set to: $_nodeName');
    notifyListeners();
  }

  /// Initialize the chat service.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('🚀 Initializing GossipChatService...');

      // Request permissions first
      final permissionsService = PermissionsService();
      final hasPermissions = await permissionsService.requestAllPermissions();
      if (!hasPermissions) {
        throw Exception('Required permissions not granted');
      }
      debugPrint('✅ Permissions granted');

      // Load or generate user info first
      await _loadUserInfo();
      debugPrint('📱 Node info loaded: $_nodeName ($_nodeId)');

      _error = null;

      // Initialize components now that we have user info
      await _initializeComponents();

      // Initialize the event store
      await _eventStore.initialize();

      // Set up event listeners before starting the node
      _setupEventListeners();

      // Start the gossip node
      await _gossipNode.start();

      // Rebuild projections from stored events (Event Sourcing!)
      await _rebuildProjectionsFromStore();

      // Send initial presence announcement
      // The gossip library will automatically sync this to all peers (current and future)
      await _announcePresence();

      _isInitialized = true;
      notifyListeners();

      debugPrint('✅ GossipChatService initialized successfully');
    } catch (e, stackTrace) {
      _error = 'Failed to initialize chat service: $e';
      debugPrint('❌ $_error');
      debugPrint(stackTrace.toString());
      notifyListeners();
      rethrow;
    }
  }

  /// Rebuild all projections from stored events
  /// This is the core of Event Sourcing - rebuilds UI state from events
  Future<void> _rebuildProjectionsFromStore() async {
    try {
      debugPrint('🔄 Rebuilding projections from stored events...');

      // Get all events from store
      final allEvents = await _eventStore.getAllEvents();

      // Rebuild all projections
      await _eventProcessor.rebuildProjections(allEvents);

      debugPrint(
        '✅ Rebuilt projections from ${allEvents.length} stored events',
      );
      debugPrint('💬 Messages in projection: ${_chatProjection.messageCount}');
      debugPrint('👥 Users in projection: ${_chatProjection.userCount}');
    } catch (e, stackTrace) {
      debugPrint('❌ Error rebuilding projections: $e');
      debugPrint(stackTrace.toString());
      rethrow; // This should prevent service from starting if projections can't be built
    }
  }

  /// Start the chat service.
  Future<void> start() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_isStarted) return;

    try {
      debugPrint('▶️ Starting GossipChatService');

      _isStarted = true;
      notifyListeners();

      debugPrint('✅ GossipChatService started successfully');
    } catch (e) {
      _error = 'Failed to start chat service: $e';
      debugPrint('❌ $_error');
      notifyListeners();
      rethrow;
    }
  }

  /// Stop the chat service.
  Future<void> stop() async {
    if (!_isStarted) return;

    try {
      debugPrint('⏹️ Stopping GossipChatService');

      // Send presence departure
      await _announcePresence(isLeaving: true);
      // TODO: do we need to trigger an immediate sync before stopping the gossip node?
      //  Otherwise the departure message may not be received by other nodes.

      // Cancel subscriptions
      await _eventCreatedSubscription?.cancel();
      await _eventReceivedSubscription?.cancel();
      await _peerAddedSubscription?.cancel();
      await _peerRemovedSubscription?.cancel();

      // Stop gossip node
      await _gossipNode.stop();

      // Close event store
      await _eventStore.close();

      // Close projection store
      await _projectionStore.close();

      _isStarted = false;
      _isInitialized = false;
      notifyListeners();

      debugPrint('✅ GossipChatService stopped successfully');
    } catch (e) {
      _error = 'Failed to stop chat service: $e';
      debugPrint('❌ $_error');
      notifyListeners();
    }
  }

  void _setupEventListeners() {
    // Listen for events we create
    _eventCreatedSubscription = _gossipNode.onEventCreated.listen(
      _handleEventCreated,
      onError: (error) {
        debugPrint('❌ Error in event created stream: $error');
      },
    );

    // Listen for events from other nodes
    _eventReceivedSubscription = _gossipNode.onEventReceived.listen(
      _handleEventReceived,
      onError: (error) {
        debugPrint('❌ Error in event received stream: $error');
      },
    );

    // Listen for peer connections
    _peerAddedSubscription = _gossipNode.onPeerAdded.listen(
      _handlePeerAdded,
      onError: (error) {
        debugPrint('❌ Error in peer added stream: $error');
      },
    );

    // Listen for peer disconnections
    _peerRemovedSubscription = _gossipNode.onPeerRemoved.listen(
      _handlePeerRemoved,
      onError: (error) {
        debugPrint('❌ Error in peer removed stream: $error');
      },
    );
  }

  void _handleEventCreated(Event event) {
    debugPrint('📝 Local event created: ${event.id}');
    // Process through Event Sourcing pipeline
    _eventProcessor.processEvent(event);
  }

  void _handleEventReceived(ReceivedEvent receivedEvent) {
    final event = receivedEvent.event;
    final fromPeer = receivedEvent.fromPeer;

    debugPrint(
      '📥 Remote event received: ${event.id} from peer: ${fromPeer.id}',
    );

    // Process through Event Sourcing pipeline
    _eventProcessor.processEvent(event);
  }

  void _handlePeerAdded(GossipPeer peer) {
    debugPrint('👋 Peer added: ${peer.id}');
    // Peer information will come through presence events
    // The gossip library will automatically sync all events including presence
    notifyListeners();
  }

  void _handlePeerRemoved(GossipPeer peer) {
    debugPrint('👋 Peer removed: ${peer.id}');

    // Look up user by the peer's stable node ID (which is now peer.id)
    final nodeId = peer.id.value;
    final user = _chatProjection.getUser(nodeId);
    if (user != null) {
      // Create a synthetic user_presence event to mark them offline
      final presenceEvent = Event(
        id: 'presence_offline_${nodeId}_${DateTime.now().millisecondsSinceEpoch}',
        nodeId: _nodeId!,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        creationTimestamp: DateTime.now().millisecondsSinceEpoch,
        payload: {
          'type': 'user_presence',
          'userId': nodeId,
          'userName': user.name,
          'isOnline': false,
        },
      );
      _eventProcessor.processEvent(presenceEvent);
    }

    notifyListeners();
  }

  Future<void> _announcePresence({bool isLeaving = false}) async {
    try {
      // Create typed event for presence
      final presenceEvent = UserPresenceEvent(
        userId: _nodeId!,
        userName: _nodeName!,
        isOnline: !isLeaving,
      );

      // Add metadata for context
      presenceEvent.setMetadata('source', 'gossip_chat_service');
      presenceEvent.setMetadata(
        'action',
        isLeaving ? 'departure' : 'announcement',
      );

      await _gossipNode.createTypedEvent(presenceEvent);
      debugPrint(
        '📢 Announced ${isLeaving ? 'departure' : 'presence'} for $_nodeName (typed event)',
      );
      debugPrint('🌐 Connected gossip peers: $connectedPeerCount');
      debugPrint(
        '👥 Known chat peers: ${peers.length} (${onlinePeers.length} online)',
      );
    } catch (e) {
      debugPrint('❌ Failed to announce presence: $e');
    }
  }

  /// Send a chat message.
  Future<ChatMessage> sendMessage(String content, {String? replyToId}) async {
    if (!_isStarted) {
      throw StateError('Chat service not started');
    }

    if (content.trim().isEmpty) {
      throw ArgumentError('Message content cannot be empty');
    }

    try {
      // Create typed event for the message
      final messageEvent = ChatMessageEvent(
        senderId: _nodeId!,
        senderName: _nodeName!,
        content: content.trim(),
      );

      // Add metadata for context
      messageEvent.setMetadata('source', 'gossip_chat_service');
      if (replyToId != null) {
        messageEvent.setMetadata('replyToId', replyToId);
      }

      // Create typed event through gossip node
      final gossipEvent = await _gossipNode.createTypedEvent(messageEvent);

      // Create ChatMessage for return value
      final message = ChatMessage(
        id: gossipEvent.id,
        senderId: _nodeId!,
        senderName: _nodeName!,
        content: content.trim(),
        timestamp: DateTime.now(),
        replyToId: replyToId,
      );

      debugPrint('📤 Sent typed message: ${message.content}');
      return message;
    } catch (e) {
      debugPrint('❌ Failed to send message: $e');
      rethrow;
    }
  }

  /// Get all chat messages, sorted by timestamp.
  List<ChatMessage> get messages => _chatProjection.messages;

  /// Get all known peers.
  List<ChatPeer> get peers {
    final peers = _chatProjection.users.values.where((peer) {
      // Skip the current user
      return peer.id != _nodeId;
    }).toList();
    return _setCorrectPeerStatus(peers);
  }

  /// Get online peers only.
  List<ChatPeer> get onlinePeers => _chatProjection.onlineUsers.where((peer) {
    // Skip the current user
    return peer.id != _nodeId;
  }).toList();

  /// Peer status is now managed by presence events and projections
  /// This method can be simplified or removed in the future
  List<ChatPeer> _setCorrectPeerStatus(List<ChatPeer> peers) {
    // Status is now handled by presence events in the projection
    // No need to override with transport-level information
    return peers;
  }

  /// Get the current peer.
  ChatPeer get currentPeer {
    return ChatPeer(id: _nodeId!, name: _nodeName!);
  }

  /// Get the current user ID.
  String? get nodeId => _nodeId;

  /// Get the current user name.
  String? get nodeName => _nodeName;

  /// Whether the service is initialized.
  bool get isInitialized => _isInitialized;

  /// Whether the service is started.
  bool get isStarted => _isStarted;

  /// Current error message, if any.
  String? get error => _error;

  /// Number of connected gossip peers.
  int get connectedPeerCount => _gossipNode.peers.length;

  /// Whether we have any connected gossip peers.
  bool get hasConnectedPeers => _gossipNode.peers.isNotEmpty;

  /// Get connection statistics for debugging.
  Future<Map<String, dynamic>> getConnectionStats() async {
    final stats = <String, dynamic>{
      'connectedGossipPeers': _gossipNode.peers.length,
      'gossipPeerIds': _gossipNode.peers.map((p) => p.id.value).toList(),
    };

    // Add transport stats for debugging (but don't expose transport peer count)
    final transportStats = _transport.getStats();
    stats['transportStats'] = transportStats;

    // Add event count to stats
    try {
      if (_isInitialized) {
        stats['totalEvents'] = await _eventStore.getEventCount();
      } else {
        stats['totalEvents'] = 0;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get event count for stats: $e');
      stats['totalEvents'] = 0;
    }

    return stats;
  }

  /// Get detailed connection status for debugging.
  String getConnectionStatus() => _transport.getConnectionStatus();

  /// Get connection statistics for debugging (compatibility with SimpleGossipChatService)
  Future<Map<String, dynamic>> get connectionStats => getConnectionStats();

  /// Clear the current error.
  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  /// Manually trigger peer discovery.
  Future<void> discoverPeers() async {
    if (!_isStarted) return;

    try {
      await _gossipNode.discoverPeers();
      debugPrint('🔍 Triggered peer discovery');
    } catch (e) {
      debugPrint('❌ Peer discovery failed: $e');
    }
  }

  /// Manually trigger gossip exchange.
  Future<void> gossip() async {
    if (!_isStarted) return;

    try {
      await _gossipNode.gossip();
      debugPrint('🗣️ Triggered gossip exchange');
    } catch (e) {
      debugPrint('❌ Gossip exchange failed: $e');
    }
  }

  /// Get a message by ID.
  ChatMessage? getMessageById(String messageId) {
    return _chatProjection.getMessageById(messageId);
  }

  /// Get messages from a specific user.
  List<ChatMessage> getMessagesFromUser(String userId) {
    return _chatProjection.getMessagesFromUser(userId);
  }

  /// Get messages that are replies to a specific message.
  List<ChatMessage> getRepliesTo(String messageId) {
    return _chatProjection.getRepliesTo(messageId);
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();

    _nodeName = prefs.getString(_userNameKey);
    _nodeId = prefs.getString(_userIdKey);

    // Generate new node ID if none exists
    if (_nodeId == null) {
      _nodeId = const Uuid().v4();
      await prefs.setString(_userIdKey, _nodeId!);
      debugPrint('🆔 Generated new node ID: $_nodeId');
    }

    debugPrint('📱 Loaded node: $_nodeName ($_nodeId)');
  }

  /// Save current projection states to persistent storage
  /// This can improve startup performance for future app launches
  Future<void> saveProjectionStates() async {
    if (!_isInitialized) {
      throw StateError(
        'Service must be initialized before saving projection states',
      );
    }

    try {
      await _eventProcessor.saveAllProjectionStates();
      debugPrint('✅ Projection states saved successfully');
    } catch (e) {
      debugPrint('❌ Error saving projection states: $e');
      rethrow;
    }
  }

  /// Clear all saved projection states
  /// Forces full event replay on next startup
  Future<void> clearSavedProjectionStates() async {
    if (!_isInitialized) {
      throw StateError(
        'Service must be initialized before clearing projection states',
      );
    }

    try {
      await _eventProcessor.clearSavedProjectionStates();
      debugPrint('✅ Saved projection states cleared');
    } catch (e) {
      debugPrint('❌ Error clearing saved projection states: $e');
      rethrow;
    }
  }

  /// Get statistics about the projection store
  ProjectionStoreStats? getProjectionStoreStats() {
    if (!_isInitialized) {
      return null;
    }
    return _eventProcessor.getProjectionStoreStats();
  }

  /// Check if projection store is available and enabled
  bool get hasProjectionStore => _eventProcessor.hasProjectionStore;

  @override
  void dispose() {
    stop();

    // Clean up event sourcing components
    _chatProjection.dispose();
    _eventProcessor.dispose();

    super.dispose();
  }
}
