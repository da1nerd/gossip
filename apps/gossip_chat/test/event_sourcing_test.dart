import 'package:flutter_test/flutter_test.dart';
import 'package:gossip/gossip.dart';
import 'package:gossip_event_sourcing/gossip_event_sourcing.dart';
import 'package:gossip_chat_demo/services/event_sourcing/projections/chat_projection.dart';
import 'package:gossip_chat_demo/models/chat_events.dart';
import 'package:gossip_typed_events/gossip_typed_events.dart';

void main() {
  group('Event Sourcing Tests', () {
    late EventProcessor eventProcessor;
    late ChatProjection chatProjection;

    setUp(() {
      eventProcessor = EventProcessor();
      chatProjection = ChatProjection();
      eventProcessor.registerProjection(chatProjection);
    });

    tearDown(() {
      eventProcessor.dispose();
      chatProjection.dispose();
    });

    group('ChatProjection', () {
      test('should handle chat message events', () async {
        // Arrange
        final messageEvent = Event(
          id: 'msg_1',
          nodeId: 'user_123',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'chat_message',
            'senderName': 'Alice',
            'content': 'Hello, World!',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        );

        // Act
        await eventProcessor.processEvent(messageEvent);

        // Assert
        expect(chatProjection.messages.length, equals(1));
        final message = chatProjection.messages.first;
        expect(message.id, equals('msg_1'));
        expect(message.senderId, equals('user_123'));
        expect(message.senderName, equals('Alice'));
        expect(message.content, equals('Hello, World!'));
      });

      test('should handle user presence events', () async {
        // Arrange
        final presenceEvent = Event(
          id: 'presence_1',
          nodeId: 'user_456',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'user_presence',
            'userId': 'user_123',
            'userName': 'Bob',
            'isOnline': true,
          },
        );

        // Act
        await eventProcessor.processEvent(presenceEvent);

        // Assert
        expect(chatProjection.users.length, equals(1));
        expect(chatProjection.onlineUserCount, equals(1));

        final user = chatProjection.getUser('user_123');
        expect(user, isNotNull);
        expect(user!.name, equals('Bob'));
        expect(user.isOnline, equals(true));
      });

      test('should handle user joined events', () async {
        // Arrange
        final joinedEvent = Event(
          id: 'joined_1',
          nodeId: 'user_789',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'user_joined',
            'userId': 'user_789',
            'userName': 'Charlie',
          },
        );

        // Act
        await eventProcessor.processEvent(joinedEvent);

        // Assert
        expect(chatProjection.users.length, equals(1));
        expect(chatProjection.onlineUserCount, equals(1));

        final user = chatProjection.getUser('user_789');
        expect(user, isNotNull);
        expect(user!.name, equals('Charlie'));
        expect(user.isOnline, equals(true));
      });

      test('should handle user left events', () async {
        // Arrange - First add a user
        final joinedEvent = Event(
          id: 'joined_1',
          nodeId: 'user_999',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'user_joined',
            'userId': 'user_999',
            'userName': 'David',
          },
        );

        final leftEvent = Event(
          id: 'left_1',
          nodeId: 'user_888',
          timestamp: DateTime.now().millisecondsSinceEpoch + 1000,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch + 1000,
          payload: {
            'type': 'user_left',
            'userId': 'user_999',
          },
        );

        // Act
        await eventProcessor.processEvent(joinedEvent);
        await eventProcessor.processEvent(leftEvent);

        // Assert
        expect(chatProjection.users.length, equals(1));
        expect(chatProjection.onlineUserCount, equals(0));

        final user = chatProjection.getUser('user_999');
        expect(user, isNotNull);
        expect(user!.name, equals('David'));
        expect(user.isOnline, equals(false));
      });

      test('should maintain message chronological order', () async {
        // Arrange - Create events with different timestamps
        final message1 = Event(
          id: 'msg_1',
          nodeId: 'user_1',
          timestamp: 1000,
          creationTimestamp: 1000,
          payload: {
            'type': 'chat_message',
            'senderName': 'Alice',
            'content': 'First message',
            'timestamp': 1000,
          },
        );

        final message3 = Event(
          id: 'msg_3',
          nodeId: 'user_1',
          timestamp: 3000,
          creationTimestamp: 3000,
          payload: {
            'type': 'chat_message',
            'senderName': 'Alice',
            'content': 'Third message',
            'timestamp': 3000,
          },
        );

        final message2 = Event(
          id: 'msg_2',
          nodeId: 'user_1',
          timestamp: 2000,
          creationTimestamp: 2000,
          payload: {
            'type': 'chat_message',
            'senderName': 'Alice',
            'content': 'Second message',
            'timestamp': 2000,
          },
        );

        // Act - Process in non-chronological order
        await eventProcessor.processEvent(message1);
        await eventProcessor.processEvent(message3);
        await eventProcessor.processEvent(message2);

        // Assert - Messages should be in chronological order
        expect(chatProjection.messages.length, equals(3));
        expect(chatProjection.messages[0].content, equals('First message'));
        expect(chatProjection.messages[1].content, equals('Second message'));
        expect(chatProjection.messages[2].content, equals('Third message'));
      });

      test('should handle idempotent event processing', () async {
        // Arrange
        final messageEvent = Event(
          id: 'msg_duplicate',
          nodeId: 'user_123',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'chat_message',
            'senderName': 'Alice',
            'content': 'Duplicate message',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        );

        // Act - Process same event twice
        await eventProcessor.processEvent(messageEvent);
        await eventProcessor.processEvent(messageEvent);

        // Assert - Should only have one message
        expect(chatProjection.messages.length, equals(1));
        expect(
            chatProjection.messages.first.content, equals('Duplicate message'));
      });

      test('should reset projection state', () async {
        // Arrange - Add some data
        final messageEvent = Event(
          id: 'msg_reset',
          nodeId: 'user_123',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'chat_message',
            'senderName': 'Alice',
            'content': 'Test message',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        );

        final userEvent = Event(
          id: 'user_reset',
          nodeId: 'user_456',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'user_joined',
            'userId': 'user_456',
            'userName': 'Test User',
          },
        );

        await eventProcessor.processEvent(messageEvent);
        await eventProcessor.processEvent(userEvent);

        // Verify data exists
        expect(chatProjection.messages.length, equals(1));
        expect(chatProjection.users.length, equals(1));

        // Act - Reset projection
        await chatProjection.reset();

        // Assert - All data should be cleared
        expect(chatProjection.messages.length, equals(0));
        expect(chatProjection.users.length, equals(0));
        expect(chatProjection.messageCount, equals(0));
        expect(chatProjection.userCount, equals(0));
        expect(chatProjection.onlineUserCount, equals(0));
      });

      test('should provide correct state snapshot', () async {
        // Arrange - Create various events
        final messageEvent = Event(
          id: 'msg_state',
          nodeId: 'user_state',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'chat_message',
            'senderName': 'StateUser',
            'content': 'State test message',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        );

        final userEvent = Event(
          id: 'user_state',
          nodeId: 'user_state_2',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'user_joined',
            'userId': 'user_state_2',
            'userName': 'StateUser2',
          },
        );

        // Act
        await eventProcessor.processEvent(messageEvent);
        await eventProcessor.processEvent(userEvent);

        // Assert
        final state = chatProjection.getState();
        expect(state['messageCount'], equals(1));
        expect(state['userCount'], equals(1));
        expect(state['onlineUserCount'], equals(1));
        expect(state['messages'], isA<List>());
        expect(state['users'], isA<Map>());

        final messages = state['messages'] as List;
        expect(messages.first['content'], equals('State test message'));

        final users = state['users'] as Map;
        expect(users.keys.first, equals('user_state_2'));
      });
    });

    group('EventProcessor', () {
      test('should rebuild projections from events', () async {
        // Arrange
        final events = [
          Event(
            id: 'rebuild_1',
            nodeId: 'user_1',
            timestamp: 1000,
            creationTimestamp: 1000,
            payload: {
              'type': 'chat_message',
              'senderName': 'User1',
              'content': 'Message 1',
              'timestamp': 1000,
            },
          ),
          Event(
            id: 'rebuild_2',
            nodeId: 'user_2',
            timestamp: 2000,
            creationTimestamp: 2000,
            payload: {
              'type': 'user_joined',
              'userId': 'user_2',
              'userName': 'User2',
            },
          ),
        ];

        // Act
        await eventProcessor.rebuildProjections(events);

        // Assert
        expect(chatProjection.messages.length, equals(1));
        expect(chatProjection.users.length, equals(1));
        expect(chatProjection.messages.first.content, equals('Message 1'));
        expect(chatProjection.getUser('user_2')?.name, equals('User2'));
      });

      test('should handle multiple projections', () async {
        // Arrange
        final secondProjection = ChatProjection();
        eventProcessor.registerProjection(secondProjection);

        final messageEvent = Event(
          id: 'multi_proj',
          nodeId: 'user_multi',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'chat_message',
            'senderName': 'MultiUser',
            'content': 'Multi projection test',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        );

        // Act
        await eventProcessor.processEvent(messageEvent);

        // Assert - Both projections should have the message
        expect(chatProjection.messages.length, equals(1));
        expect(secondProjection.messages.length, equals(1));
        expect(chatProjection.messages.first.content,
            equals('Multi projection test'));
        expect(secondProjection.messages.first.content,
            equals('Multi projection test'));

        // Cleanup
        secondProjection.dispose();
      });

      test('should provide projection by type', () {
        // Act
        final retrievedProjection =
            eventProcessor.getProjection<ChatProjection>();

        // Assert
        expect(retrievedProjection, isNotNull);
        expect(retrievedProjection, equals(chatProjection));
      });

      test('should clear processed events cache', () async {
        // Arrange
        final messageEvent = Event(
          id: 'cache_test',
          nodeId: 'user_cache',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'chat_message',
            'senderName': 'CacheUser',
            'content': 'Cache test',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        );

        await eventProcessor.processEvent(messageEvent);
        expect(eventProcessor.processedEventCount, equals(1));

        // Act
        eventProcessor.clearProcessedEventsCache();

        // Assert
        expect(eventProcessor.processedEventCount, equals(0));

        // Should be able to process the same event again
        await eventProcessor.processEvent(messageEvent);
        expect(chatProjection.messages.length,
            equals(1)); // ChatProjection also prevents duplicates
      });
    });

    group('Typed Events', () {
      late TypedEventRegistry registry;

      setUp(() {
        registry = TypedEventRegistry();
        ChatEventRegistry.registerAll();
      });

      tearDown(() {
        registry.clear();
      });

      test('should handle typed chat message events', () async {
        // Arrange
        final typedChatEvent = ChatMessageEvent(
          senderId: 'user_123',
          senderName: 'Alice',
          content: 'Hello from typed event!',
        );

        final wrappedEvent = Event(
          id: 'typed_msg_1',
          nodeId: 'user_123',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'chat_message',
            'data': typedChatEvent.toJson(),
            'version': '1.0',
          },
        );

        // Act
        await eventProcessor.processEvent(wrappedEvent);

        // Assert
        expect(chatProjection.messages.length, equals(1));
        final message = chatProjection.messages.first;
        expect(message.id, equals('typed_msg_1'));
        expect(message.senderId, equals('user_123'));
        expect(message.senderName, equals('Alice'));
        expect(message.content, equals('Hello from typed event!'));
      });

      test('should handle typed user presence events', () async {
        // Arrange
        final typedPresenceEvent = UserPresenceEvent(
          userId: 'user_456',
          userName: 'Bob',
          isOnline: true,
        );

        final wrappedEvent = Event(
          id: 'typed_presence_1',
          nodeId: 'user_456',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          creationTimestamp: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'type': 'user_presence',
            'data': typedPresenceEvent.toJson(),
            'version': '1.0',
          },
        );

        // Act
        await eventProcessor.processEvent(wrappedEvent);

        // Assert
        expect(chatProjection.users.length, equals(1));
        final user = chatProjection.getUser('user_456');
        expect(user, isNotNull);
        expect(user!.name, equals('Bob'));
        expect(user.isOnline, equals(true));
      });

      test('should maintain backward compatibility with legacy events',
          () async {
        // Arrange - Create both typed and legacy events
        final typedEvent = Event(
          id: 'typed_1',
          nodeId: 'user_1',
          timestamp: 1000,
          creationTimestamp: 1000,
          payload: {
            'type': 'chat_message',
            'data': ChatMessageEvent(
              senderId: 'user_1',
              senderName: 'TypedUser',
              content: 'Typed message',
            ).toJson(),
            'version': '1.0',
          },
        );

        final legacyEvent = Event(
          id: 'legacy_1',
          nodeId: 'user_2',
          timestamp: 2000,
          creationTimestamp: 2000,
          payload: {
            'type': 'chat_message',
            'senderName': 'LegacyUser',
            'content': 'Legacy message',
            'timestamp': 2000,
          },
        );

        // Act
        await eventProcessor.processEvent(typedEvent);
        await eventProcessor.processEvent(legacyEvent);

        // Assert - Both should be processed correctly
        expect(chatProjection.messages.length, equals(2));

        final typedMessage =
            chatProjection.messages.firstWhere((m) => m.id == 'typed_1');
        expect(typedMessage.senderName, equals('TypedUser'));
        expect(typedMessage.content, equals('Typed message'));

        final legacyMessage =
            chatProjection.messages.firstWhere((m) => m.id == 'legacy_1');
        expect(legacyMessage.senderName, equals('LegacyUser'));
        expect(legacyMessage.content, equals('Legacy message'));
      });

      test('should handle mixed typed and legacy events in rebuild', () async {
        // Arrange
        final events = [
          // Legacy event
          Event(
            id: 'legacy_rebuild',
            nodeId: 'user_1',
            timestamp: 1000,
            creationTimestamp: 1000,
            payload: {
              'type': 'user_joined',
              'userId': 'user_1',
              'userName': 'LegacyUser',
              'timestamp': 1000,
            },
          ),
          // Typed event
          Event(
            id: 'typed_rebuild',
            nodeId: 'user_2',
            timestamp: 2000,
            creationTimestamp: 2000,
            payload: {
              'type': 'user_joined',
              'data': UserJoinedEvent(
                userId: 'user_2',
                userName: 'TypedUser',
              ).toJson(),
              'version': '1.0',
            },
          ),
        ];

        // Act
        await eventProcessor.rebuildProjections(events);

        // Assert
        expect(chatProjection.users.length, equals(2));

        final legacyUser = chatProjection.getUser('user_1');
        expect(legacyUser?.name, equals('LegacyUser'));

        final typedUser = chatProjection.getUser('user_2');
        expect(typedUser?.name, equals('TypedUser'));
      });
    });
  });
}
