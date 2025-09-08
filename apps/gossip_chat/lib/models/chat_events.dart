import 'package:gossip_typed_events/gossip_typed_events.dart';

/// Typed event for chat messages.
class ChatMessageEvent extends TypedEvent with TypedEventMixin {
  final String senderId;
  final String senderName;
  final String content;
  final DateTime timestamp;

  ChatMessageEvent({
    required this.senderId,
    required this.senderName,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String get type => 'chat_message';

  @override
  void validate() {
    super.validate();
    if (senderId.isEmpty) throw ArgumentError('senderId cannot be empty');
    if (senderName.isEmpty) throw ArgumentError('senderName cannot be empty');
    if (content.isEmpty) throw ArgumentError('content cannot be empty');
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...toJsonWithMetadata(),
      'senderId': senderId,
      'senderName': senderName,
      'content': content,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory ChatMessageEvent.fromJson(Map<String, dynamic> json) {
    final event = ChatMessageEvent(
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String,
      content: json['content'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
    );
    event.fromJsonWithMetadata(json);
    return event;
  }

  @override
  String toString() {
    return '[$senderName]: $content';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessageEvent &&
          runtimeType == other.runtimeType &&
          senderId == other.senderId &&
          content == other.content &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(senderId, content, timestamp);
}

/// Typed event for when a user joins the chat.
class UserJoinedEvent extends TypedEvent with TypedEventMixin {
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
  void validate() {
    super.validate();
    if (userId.isEmpty) throw ArgumentError('userId cannot be empty');
    if (userName.isEmpty) throw ArgumentError('userName cannot be empty');
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...toJsonWithMetadata(),
      'userId': userId,
      'userName': userName,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory UserJoinedEvent.fromJson(Map<String, dynamic> json) {
    final event = UserJoinedEvent(
      userId: json['userId'] as String,
      userName: json['userName'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
    );
    event.fromJsonWithMetadata(json);
    return event;
  }

  @override
  String toString() {
    return '$userName joined the chat';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserJoinedEvent &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          userName == other.userName;

  @override
  int get hashCode => Object.hash(userId, userName);
}

/// Typed event for when a user leaves the chat.
class UserLeftEvent extends TypedEvent with TypedEventMixin {
  final String userId;
  final String userName;
  final DateTime timestamp;

  UserLeftEvent({
    required this.userId,
    required this.userName,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String get type => 'user_left';

  @override
  void validate() {
    super.validate();
    if (userId.isEmpty) throw ArgumentError('userId cannot be empty');
    if (userName.isEmpty) throw ArgumentError('userName cannot be empty');
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...toJsonWithMetadata(),
      'userId': userId,
      'userName': userName,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory UserLeftEvent.fromJson(Map<String, dynamic> json) {
    final event = UserLeftEvent(
      userId: json['userId'] as String,
      userName: json['userName'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
    );
    event.fromJsonWithMetadata(json);
    return event;
  }

  @override
  String toString() {
    return '$userName left the chat';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserLeftEvent &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          userName == other.userName;

  @override
  int get hashCode => Object.hash(userId, userName);
}

/// Typed event for user presence updates.
class UserPresenceEvent extends TypedEvent with TypedEventMixin {
  final String userId;
  final String userName;
  final bool isOnline;
  final DateTime timestamp;

  UserPresenceEvent({
    required this.userId,
    required this.userName,
    required this.isOnline,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String get type => 'user_presence';

  @override
  void validate() {
    super.validate();
    if (userId.isEmpty) throw ArgumentError('userId cannot be empty');
    if (userName.isEmpty) throw ArgumentError('userName cannot be empty');
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...toJsonWithMetadata(),
      'userId': userId,
      'userName': userName,
      'isOnline': isOnline,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory UserPresenceEvent.fromJson(Map<String, dynamic> json) {
    final event = UserPresenceEvent(
      userId: json['userId'] as String,
      userName: json['userName'] as String,
      isOnline: json['isOnline'] as bool,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
    );
    event.fromJsonWithMetadata(json);
    return event;
  }

  @override
  String toString() {
    return '$userName is ${isOnline ? 'online' : 'offline'}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserPresenceEvent &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          userName == other.userName &&
          isOnline == other.isOnline;

  @override
  int get hashCode => Object.hash(userId, userName, isOnline);
}

/// Helper class to register all chat event types.
class ChatEventRegistry {
  static void registerAll() {
    final registry = TypedEventRegistry();

    registry.register<ChatMessageEvent>(
      'chat_message',
      ChatMessageEvent.fromJson,
    );

    registry.register<UserJoinedEvent>('user_joined', UserJoinedEvent.fromJson);

    registry.register<UserLeftEvent>('user_left', UserLeftEvent.fromJson);

    registry.register<UserPresenceEvent>(
      'user_presence',
      UserPresenceEvent.fromJson,
    );
  }
}
