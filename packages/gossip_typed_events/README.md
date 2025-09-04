# Gossip Typed Events

[![Pub Version](https://img.shields.io/pub/v/gossip_typed_events.svg)](https://pub.dev/packages/gossip_typed_events)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Type-safe event extensions for the [Dart gossip protocol library](https://github.com/da1nerd/gossip). This library provides strongly-typed event capabilities on top of the core gossip protocol, enabling developers to work with compile-time safe events while maintaining full compatibility with the underlying gossip system.

## Features

- 🎯 **Type-safe events** - Define custom event types with compile-time safety
- 📝 **Automatic serialization** - Events are automatically serialized/deserialized
- 🔍 **Event filtering** - Stream-based filtering by event type
- 📊 **Event registry** - Central registry for managing event types
- 🔄 **Stream transformers** - Powerful stream processing capabilities
- 🛡️ **Validation support** - Built-in validation framework for events
- 📦 **Metadata support** - Attach metadata to events for additional context

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  gossip:
    git: https://github.com/da1nerd/gossip.git
  gossip_typed_events:
    git: https://github.com/da1nerd/gossip_typed_events.git
```

Then run:

```bash
dart pub get
```

## Quick Start

### 1. Define Your Event Types

```dart
import 'package:gossip_typed_events/gossip_typed_events.dart';

class UserLoginEvent extends TypedEvent {
  final String userId;
  final DateTime timestamp;

  UserLoginEvent({required this.userId, required this.timestamp});

  @override
  String get type => 'user_login';

  @override
  Map<String, dynamic> toJson() => {
    'userId': userId,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };

  factory UserLoginEvent.fromJson(Map<String, dynamic> json) {
    return UserLoginEvent(
      userId: json['userId'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
    );
  }
}

class OrderCreatedEvent extends TypedEvent with TypedEventMixin {
  final String orderId;
  final String customerId;
  final double amount;

  OrderCreatedEvent({
    required this.orderId,
    required this.customerId,
    required this.amount,
  });

  @override
  String get type => 'order_created';

  @override
  void validate() {
    super.validate();
    if (orderId.isEmpty) throw ArgumentError('orderId cannot be empty');
    if (customerId.isEmpty) throw ArgumentError('customerId cannot be empty');
    if (amount <= 0) throw ArgumentError('amount must be positive');
  }

  @override
  Map<String, dynamic> toJson() => {
    ...toJsonWithMetadata(), // Includes createdAt timestamp and metadata
    'orderId': orderId,
    'customerId': customerId,
    'amount': amount,
  };

  factory OrderCreatedEvent.fromJson(Map<String, dynamic> json) {
    final event = OrderCreatedEvent(
      orderId: json['orderId'] as String,
      customerId: json['customerId'] as String,
      amount: (json['amount'] as num).toDouble(),
    );
    
    event.fromJsonWithMetadata(json); // Restore metadata
    return event;
  }
}
```

### 2. Register Event Types

```dart
void main() async {
  // Register your event types at application startup
  final registry = TypedEventRegistry();
  
  registry.register<UserLoginEvent>(
    'user_login',
    (json) => UserLoginEvent.fromJson(json),
  );
  
  registry.register<OrderCreatedEvent>(
    'order_created',
    (json) => OrderCreatedEvent.fromJson(json),
  );

  // ... rest of your application
}
```

### 3. Use with GossipNode

```dart
import 'package:gossip/gossip.dart';
import 'package:gossip_typed_events/gossip_typed_events.dart';

void main() async {
  // Set up your gossip node (see gossip library documentation)
  final node = GossipNode(
    config: GossipConfig(nodeId: 'my-node'),
    eventStore: MemoryEventStore(),
    transport: MyTransport(),
  );
  
  await node.start();
  
  // Create and broadcast typed events
  final loginEvent = UserLoginEvent(
    userId: 'user123',
    timestamp: DateTime.now(),
  );
  
  await node.broadcastTypedEvent(loginEvent);
  
  final orderEvent = OrderCreatedEvent(
    orderId: 'order456',
    customerId: 'user123',
    amount: 99.99,
  );
  
  await node.broadcastTypedEvent(orderEvent);
  
  // Listen for specific typed events
  node.onTypedEvent<UserLoginEvent>((json) => UserLoginEvent.fromJson(json))
      .listen((event) {
    print('User ${event.userId} logged in at ${event.timestamp}');
  });
  
  // Or use the registry for automatic deserialization
  node.onRegisteredTypedEvent<OrderCreatedEvent>().listen((event) {
    print('Order ${event.orderId} created for customer ${event.customerId}');
    print('Amount: \$${event.amount}');
    print('Created at: ${event.createdAt}');
  });
  
  // Listen for any typed event
  node.onAnyTypedEvent().listen((typedReceived) {
    print('Received ${typedReceived.eventType} from ${typedReceived.fromPeer.id}');
  });
}
```

## Advanced Usage

### Event Validation

Events can implement validation logic that runs before broadcasting:

```dart
class CriticalEvent extends TypedEvent with TypedEventMixin {
  final String message;
  final int severity;

  CriticalEvent({required this.message, required this.severity});

  @override
  String get type => 'critical_event';

  @override
  void validate() {
    super.validate();
    if (message.isEmpty) {
      throw ArgumentError('Critical events must have a message');
    }
    if (severity < 1 || severity > 10) {
      throw ArgumentError('Severity must be between 1 and 10');
    }
  }

  @override
  Map<String, dynamic> toJson() => {
    'message': message,
    'severity': severity,
  };

  // ... fromJson implementation
}
```

### Stream Transformers

Use powerful stream transformers to process events:

```dart
// Transform raw events to specific typed events
final userEventStream = rawEventStream.transform(
  typedEventTransformer<UserLoginEvent>(
    eventType: 'user_login',
    factory: (json) => UserLoginEvent.fromJson(json),
  ),
);

// Handle multiple event types
final businessEventStream = rawEventStream.transform(
  multiTypeEventTransformer(
    includeTypes: {'user_login', 'user_logout', 'order_created'},
    onError: (event, error, stackTrace) {
      print('Failed to deserialize event ${event.id}: $error');
    },
  ),
);

// Registry-based transformer (no factory needed)
final registryStream = rawEventStream.transform(
  registryTypedEventTransformer<OrderCreatedEvent>(),
);
```

### Metadata and Context

Add metadata to your events for additional context:

```dart
final event = OrderCreatedEvent(
  orderId: 'order789',
  customerId: 'user456',
  amount: 149.99,
);

// Add metadata
event.setMetadata('source', 'mobile_app');
event.setMetadata('version', '2.1.0');
event.setMetadata('sessionId', 'session123');

await node.broadcastTypedEvent(event);

// Access metadata when receiving
node.onRegisteredTypedEvent<OrderCreatedEvent>().listen((event) {
  final source = event.getMetadata<String>('source');
  final version = event.getMetadata<String>('version');
  
  print('Order from $source (v$version): ${event.orderId}');
});
```

### Batch Operations

Efficiently broadcast multiple events:

```dart
final events = [
  UserLoginEvent(userId: '123', timestamp: DateTime.now()),
  UserActionEvent(userId: '123', action: 'view_profile'),
  UserLogoutEvent(userId: '123', timestamp: DateTime.now()),
];

final gossipEvents = await node.broadcastTypedEvents(events);
print('Broadcasted ${gossipEvents.length} events');
```

## Architecture

This library extends the core gossip protocol with type safety:

```
┌─────────────────────────────────────────┐
│           Your Application              │
├─────────────────────────────────────────┤
│      Typed Events (this library)       │
│  ┌─────────────┐  ┌─────────────────┐   │
│  │ TypedEvent  │  │ TypedGossipNode │   │
│  └─────────────┘  └─────────────────┘   │
├─────────────────────────────────────────┤
│         Core Gossip Protocol            │
│  ┌─────────────┐  ┌─────────────────┐   │
│  │    Event    │  │   GossipNode    │   │
│  └─────────────┘  └─────────────────┘   │
└─────────────────────────────────────────┘
```

**Key Components:**

- **TypedEvent**: Abstract base class for all typed events
- **TypedEventMixin**: Provides common functionality like timestamps and metadata
- **TypedEventRegistry**: Central registry for managing event type mappings
- **TypedGossipNode**: Extension methods for GossipNode with type safety
- **Stream Transformers**: Convert raw event streams to typed event streams

## Best Practices

### Type Management
- Use consistent type identifiers across your application
- Register all event types at application startup
- Consider using constants for event type strings

```dart
class EventTypes {
  static const userLogin = 'user_login';
  static const userLogout = 'user_logout';
  static const orderCreated = 'order_created';
}
```

### Validation
- Implement validation for critical business events
- Use the TypedEventMixin for common validation patterns
- Validate both structure and business rules

### Error Handling
- Handle deserialization errors gracefully
- Use stream transformer error handlers
- Log failed deserializations for debugging

```dart
node.onTypedEvent<UserEvent>((json) => UserEvent.fromJson(json))
    .handleError((error) {
      print('Failed to process user event: $error');
    })
    .listen((event) {
      // Process valid events
    });
```

### Performance
- Events are lazily deserialized only when needed
- Use specific event type streams instead of filtering all events
- Consider event retention policies for metadata

### Testing
- Test both serialization and deserialization
- Validate event schemas across versions
- Test error scenarios and validation

```dart
test('UserLoginEvent serialization', () {
  final event = UserLoginEvent(
    userId: 'test123',
    timestamp: DateTime(2023, 1, 1),
  );
  
  final json = event.toJson();
  final deserialized = UserLoginEvent.fromJson(json);
  
  expect(deserialized.userId, equals('test123'));
  expect(deserialized.timestamp, equals(DateTime(2023, 1, 1)));
});
```

## Error Handling

The library provides comprehensive error handling:

```dart
try {
  await node.broadcastTypedEvent(event);
} on TypedEventException catch (e) {
  print('Failed to broadcast event: ${e.message}');
  if (e.eventType != null) {
    print('Event type: ${e.eventType}');
  }
} on TypedEventRegistryException catch (e) {
  print('Registry error: ${e.message}');
  if (e.type != null) {
    print('Failed type: ${e.type}');
  }
}

// Handle stream errors
node.onRegisteredTypedEvent<UserEvent>()
    .handleError((error) {
      if (error is TypedEventException) {
        print('Event processing error: ${error.message}');
      }
    })
    .listen((event) {
      // Process events
    });
```

## Performance Characteristics

- **Lazy Deserialization**: Events are only converted to typed events when accessed
- **Efficient Filtering**: Stream filtering happens at the gossip protocol level
- **Memory Overhead**: Minimal additional memory usage compared to raw events
- **Registry Lookup**: O(1) registry lookups for event type resolution

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/awesome-feature`)
3. Add tests for your changes
4. Ensure all tests pass (`dart test`)
5. Commit your changes (`git commit -am 'Add awesome feature'`)
6. Push to the branch (`git push origin feature/awesome-feature`)
7. Create a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Related

- [Gossip Protocol Library](https://github.com/da1nerd/gossip) - The core gossip protocol implementation
- [Dart Language](https://dart.dev) - The Dart programming language