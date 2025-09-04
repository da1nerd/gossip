import 'package:uuid/uuid.dart';

class SimpleChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime timestamp;
  final ChatMessageType type;

  SimpleChatMessage({
    String? id,
    required this.senderId,
    required this.senderName,
    required this.content,
    DateTime? timestamp,
    this.type = ChatMessageType.text,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  // Create from JSON (for Gossip event payload)
  factory SimpleChatMessage.fromJson(Map<String, dynamic> json) {
    return SimpleChatMessage(
      id: json['id'] as String,
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String,
      content: json['content'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      type: ChatMessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ChatMessageType.text,
      ),
    );
  }

  // Convert to JSON (for Gossip event payload)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'senderName': senderName,
      'content': content,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'type': type.name,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SimpleChatMessage &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'ChatMessage{id: $id, senderId: $senderId, senderName: $senderName, content: $content, timestamp: $timestamp, type: $type}';
  }

  SimpleChatMessage copyWith({
    String? id,
    String? senderId,
    String? senderName,
    String? content,
    DateTime? timestamp,
    ChatMessageType? type,
  }) {
    return SimpleChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
    );
  }
}

enum ChatMessageType {
  text,
  userJoined,
  userLeft,
  system,
}
