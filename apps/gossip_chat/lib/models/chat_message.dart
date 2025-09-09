import 'package:gossip/gossip.dart';

/// Represents a chat message in the gossip chat system.
class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime timestamp;
  final String? replyToId;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.timestamp,
    this.replyToId,
  });

  factory ChatMessage.fromEvent(Event event) {
    final payload = event.payload;
    return ChatMessage(
      id: event.id,
      // TODO: don't use the node id here. This is application logic, and should not know about nodes. The sender id should come from the payload.
      senderId: event.nodeId.value,
      senderName: payload['senderName'] as String,
      content: payload['content'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        payload['timestamp'] as int,
      ),
      replyToId: payload['replyToId'] as String?,
    );
  }

  Map<String, dynamic> toEventPayload() {
    return {
      'type': 'chat_message',
      'senderName': senderName,
      'content': content,
      'timestamp': timestamp.millisecondsSinceEpoch,
      if (replyToId != null) 'replyToId': replyToId,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatMessage && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
