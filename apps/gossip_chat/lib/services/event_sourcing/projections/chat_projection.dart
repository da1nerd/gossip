import 'package:flutter/foundation.dart';
import 'package:gossip/gossip.dart';
import 'package:gossip_typed_events/gossip_typed_events.dart';
import 'package:gossip_event_sourcing/gossip_event_sourcing.dart';
import '../../../models/chat_message.dart';
import '../../../models/chat_peer.dart';
import '../../../models/chat_events.dart';

/// Projection that maintains the chat state (messages and users)
/// This is the main read model for the chat UI
class ChatProjection extends Projection with ChangeNotifier {
  final List<ChatMessage> _messages = [];
  final Map<String, ChatPeer> _users = {};

  /// Get all messages in chronological order
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Get all users
  Map<String, ChatPeer> get users => Map.unmodifiable(_users);

  /// Get online users only
  List<ChatPeer> get onlineUsers =>
      _users.values.where((user) => user.isOnline).toList();

  /// Get user count
  int get userCount => _users.length;

  /// Get online user count
  int get onlineUserCount => onlineUsers.length;

  /// Get message count
  int get messageCount => _messages.length;

  @override
  Future<void> apply(Event event) async {
    // Check if this is a typed event
    if (!_isTypedEvent(event)) {
      // Handle legacy events
      await _applyLegacyEvent(event);
      return;
    }

    // Handle typed events
    await _applyTypedEvent(event);
  }

  /// Checks if an event is a typed event
  bool _isTypedEvent(Event event) {
    final payload = event.payload;
    return payload.containsKey('type') &&
        payload.containsKey('data') &&
        payload.containsKey('version');
  }

  /// Applies a typed event using the registry
  Future<void> _applyTypedEvent(Event event) async {
    try {
      final eventType = event.payload['type'] as String;
      final eventData = event.payload['data'] as Map<String, dynamic>;

      debugPrint(
        '📋 ChatProjection: Applying typed event ${event.id} of type $eventType',
      );

      final registry = TypedEventRegistry();
      final typedEvent = registry.createFromJson(eventType, eventData);

      if (typedEvent == null) {
        debugPrint('⚠️ ChatProjection: Unknown typed event type: $eventType');
        return;
      }

      // Process the typed event
      if (typedEvent is ChatMessageEvent) {
        await _applyChatMessageTyped(typedEvent, event.id);
      } else if (typedEvent is UserPresenceEvent) {
        await _applyUserPresenceTyped(typedEvent);
      } else if (typedEvent is UserJoinedEvent) {
        await _applyUserJoinedTyped(typedEvent);
      } else if (typedEvent is UserLeftEvent) {
        await _applyUserLeftTyped(typedEvent);
      } else {
        debugPrint(
          '⚠️ ChatProjection: Unhandled typed event: ${typedEvent.type}',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ ChatProjection: Error applying typed event: $e');
      debugPrint(stackTrace.toString());
    }
  }

  /// Applies legacy events (backward compatibility)
  Future<void> _applyLegacyEvent(Event event) async {
    final eventType = event.payload['type'] as String?;

    debugPrint(
      '📋 ChatProjection: Applying legacy event ${event.id} of type $eventType',
    );

    switch (eventType) {
      case 'chat_message':
        await _applyChatMessage(event);
        break;
      case 'user_presence':
        await _applyUserPresence(event);
        break;
      case 'user_joined':
        await _applyUserJoined(event);
        break;
      case 'user_left':
        await _applyUserLeft(event);
        break;
      default:
        debugPrint('⚠️ ChatProjection: Unknown legacy event type: $eventType');
    }
  }

  /// Applies a typed chat message event
  Future<void> _applyChatMessageTyped(
    ChatMessageEvent typedEvent,
    String eventId,
  ) async {
    try {
      // Create ChatMessage from typed event
      final message = ChatMessage(
        id: eventId,
        senderId: typedEvent.senderId,
        senderName: typedEvent.senderName,
        content: typedEvent.content,
        timestamp: typedEvent.timestamp,
        replyToId: null, // Could be extracted from metadata if needed
      );

      // Add message if not already present (idempotency)
      if (!_messages.any((m) => m.id == message.id)) {
        _messages.add(message);
        _sortMessages();

        debugPrint(
          '💬 ChatProjection: Added typed message ${message.id} from ${message.senderName}',
        );
        notifyListeners();
      } else {
        debugPrint(
          '⏭️ ChatProjection: Typed message ${message.id} already exists, skipping',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ ChatProjection: Error processing typed chat message: $e');
      debugPrint(stackTrace.toString());
    }
  }

  /// Legacy method for backward compatibility
  Future<void> _applyChatMessage(Event event) async {
    try {
      final message = ChatMessage.fromEvent(event);

      // Add message if not already present (idempotency)
      if (!_messages.any((m) => m.id == message.id)) {
        _messages.add(message);
        _sortMessages();

        debugPrint(
          '💬 ChatProjection: Added legacy message ${message.id} from ${message.senderName}',
        );
        notifyListeners();
      } else {
        debugPrint(
          '⏭️ ChatProjection: Legacy message ${message.id} already exists, skipping',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ ChatProjection: Error processing legacy chat message: $e');
      debugPrint(stackTrace.toString());
    }
  }

  /// Applies a typed user presence event
  Future<void> _applyUserPresenceTyped(UserPresenceEvent typedEvent) async {
    try {
      final existingUser = _users[typedEvent.userId];

      _users[typedEvent.userId] = ChatPeer(
        id: typedEvent.userId,
        name: typedEvent.userName,
        isOnline: typedEvent.isOnline,
        lastSeen: typedEvent.timestamp,
      );

      final statusChange = existingUser == null
          ? 'new user'
          : existingUser.isOnline != typedEvent.isOnline
          ? (typedEvent.isOnline ? 'came online' : 'went offline')
          : 'updated';

      debugPrint(
        '👤 ChatProjection: User ${typedEvent.userName} $statusChange (typed, online: ${typedEvent.isOnline})',
      );
      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('❌ ChatProjection: Error processing typed user presence: $e');
      debugPrint(stackTrace.toString());
    }
  }

  /// Legacy method for backward compatibility
  Future<void> _applyUserPresence(Event event) async {
    try {
      final payload = event.payload;
      final userId = payload['userId'] as String;
      final userName = payload['userName'] as String;
      final isOnline = payload['isOnline'] as bool? ?? true;

      final existingUser = _users[userId];

      _users[userId] = ChatPeer(
        id: userId,
        name: userName,
        isOnline: isOnline,
        lastSeen: DateTime.now(),
      );

      final statusChange = existingUser == null
          ? 'new user'
          : existingUser.isOnline != isOnline
          ? (isOnline ? 'came online' : 'went offline')
          : 'updated';

      debugPrint(
        '👤 ChatProjection: User $userName $statusChange (legacy, online: $isOnline)',
      );
      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('❌ ChatProjection: Error processing legacy user presence: $e');
      debugPrint(stackTrace.toString());
    }
  }

  /// Applies a typed user joined event
  Future<void> _applyUserJoinedTyped(UserJoinedEvent typedEvent) async {
    try {
      _users[typedEvent.userId] = ChatPeer(
        id: typedEvent.userId,
        name: typedEvent.userName,
        isOnline: true,
        lastSeen: typedEvent.timestamp,
      );

      debugPrint(
        '👋 ChatProjection: User ${typedEvent.userName} joined (typed)',
      );
      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('❌ ChatProjection: Error processing typed user joined: $e');
      debugPrint(stackTrace.toString());
    }
  }

  /// Legacy method for backward compatibility
  Future<void> _applyUserJoined(Event event) async {
    try {
      final payload = event.payload;
      final userId = payload['userId'] as String;
      final userName = payload['userName'] as String;

      _users[userId] = ChatPeer(
        id: userId,
        name: userName,
        isOnline: true,
        lastSeen: DateTime.now(),
      );

      debugPrint('👋 ChatProjection: User $userName joined (legacy)');
      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('❌ ChatProjection: Error processing legacy user joined: $e');
      debugPrint(stackTrace.toString());
    }
  }

  /// Applies a typed user left event
  Future<void> _applyUserLeftTyped(UserLeftEvent typedEvent) async {
    try {
      final existingUser = _users[typedEvent.userId];
      if (existingUser != null) {
        _users[typedEvent.userId] = ChatPeer(
          id: existingUser.id,
          name: existingUser.name,
          isOnline: false,
          lastSeen: typedEvent.timestamp,
        );

        debugPrint('👋 ChatProjection: User ${existingUser.name} left (typed)');
        notifyListeners();
      } else {
        debugPrint(
          '⚠️ ChatProjection: User ${typedEvent.userId} left but was not found in users map',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ ChatProjection: Error processing typed user left: $e');
      debugPrint(stackTrace.toString());
    }
  }

  /// Legacy method for backward compatibility
  Future<void> _applyUserLeft(Event event) async {
    try {
      final payload = event.payload;
      final userId = payload['userId'] as String;

      final existingUser = _users[userId];
      if (existingUser != null) {
        _users[userId] = ChatPeer(
          id: existingUser.id,
          name: existingUser.name,
          isOnline: false,
          lastSeen: DateTime.now(),
        );

        debugPrint(
          '👋 ChatProjection: User ${existingUser.name} left (legacy)',
        );
        notifyListeners();
      } else {
        debugPrint(
          '⚠️ ChatProjection: User $userId left but was not found in users map (legacy)',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ ChatProjection: Error processing legacy user left: $e');
      debugPrint(stackTrace.toString());
    }
  }

  void _sortMessages() {
    _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Future<void> reset() async {
    _messages.clear();
    _users.clear();
    notifyListeners();
    debugPrint('🔄 ChatProjection: Reset to initial state');
  }

  @override
  Map<String, dynamic> getState() {
    return {
      'messageCount': _messages.length,
      'userCount': _users.length,
      'onlineUserCount': onlineUserCount,
      'messages': _messages
          .map(
            (m) => {
              'id': m.id,
              'senderId': m.senderId,
              'senderName': m.senderName,
              'content': m.content,
              'timestamp': m.timestamp.toIso8601String(),
              'replyToId': m.replyToId,
            },
          )
          .toList(),
      'users': _users.map(
        (id, user) => MapEntry(id, {
          'id': user.id,
          'name': user.name,
          'isOnline': user.isOnline,
          'lastSeen': user.lastSeen?.toIso8601String(),
        }),
      ),
    };
  }

  /// Get message by ID
  ChatMessage? getMessageById(String messageId) {
    try {
      return _messages.firstWhere((m) => m.id == messageId);
    } catch (e) {
      return null;
    }
  }

  /// Get messages from a specific user
  List<ChatMessage> getMessagesFromUser(String userId) {
    return _messages.where((m) => m.senderId == userId).toList();
  }

  /// Get replies to a specific message
  List<ChatMessage> getRepliesTo(String messageId) {
    return _messages.where((m) => m.replyToId == messageId).toList();
  }

  /// Get user by ID
  ChatPeer? getUser(String userId) {
    return _users[userId];
  }

  /// Check if user exists and is online
  bool isUserOnline(String userId) {
    final user = _users[userId];
    return user?.isOnline ?? false;
  }

  @override
  String get stateVersion => '1.0.0';

  @override
  Future<bool> restoreState(Map<String, dynamic> state) async {
    try {
      debugPrint('🔄 ChatProjection: Restoring state from projection store');

      // Reset to initial state first
      await reset();

      // Restore messages
      final messagesData = state['messages'] as List?;
      if (messagesData != null) {
        for (final messageData in messagesData) {
          final messageMap = Map<String, dynamic>.from(messageData as Map);
          final message = ChatMessage(
            id: messageMap['id'] as String,
            senderId: messageMap['senderId'] as String,
            senderName: messageMap['senderName'] as String,
            content: messageMap['content'] as String,
            timestamp: DateTime.parse(messageMap['timestamp'] as String),
            replyToId: messageMap['replyToId'] as String?,
          );
          _messages.add(message);
        }
        _sortMessages();
      }

      // Restore users
      final usersData = state['users'] != null
          ? Map<String, dynamic>.from(state['users'] as Map)
          : null;
      if (usersData != null) {
        _users.clear();
        for (final entry in usersData.entries) {
          final userData = Map<String, dynamic>.from(entry.value as Map);
          final user = ChatPeer(
            id: userData['id'] as String,
            name: userData['name'] as String,
            isOnline: userData['isOnline'] as bool,
            lastSeen: userData['lastSeen'] != null
                ? DateTime.parse(userData['lastSeen'] as String)
                : null,
          );
          _users[entry.key] = user;
        }
      }

      debugPrint(
        '✅ ChatProjection: State restored successfully '
        '(${_messages.length} messages, ${_users.length} users)',
      );

      // Notify listeners of the restored state
      notifyListeners();

      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ ChatProjection: Failed to restore state: $e');
      debugPrint(stackTrace.toString());

      // Reset to clean state on failure
      await reset();
      return false;
    }
  }

  @override
  void dispose() {
    _messages.clear();
    _users.clear();
    super.dispose();
  }
}
