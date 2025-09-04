/// Type-safe event extensions for the Dart gossip protocol library.
///
/// This library provides strongly-typed event capabilities on top of the
/// core gossip protocol, enabling developers to work with type-safe events
/// while maintaining full compatibility with the underlying gossip system.
///
/// ## Features
///
/// - 🎯 **Type-safe events** - Define custom event types with compile-time safety
/// - 📝 **Automatic serialization** - Events are automatically serialized/deserialized
/// - 🔍 **Event filtering** - Stream-based filtering by event type
/// - 📊 **Event registry** - Central registry for managing event types
/// - 🔄 **Stream transformers** - Powerful stream processing capabilities
/// - 🛡️ **Validation support** - Built-in validation framework for events
/// - 📦 **Metadata support** - Attach metadata to events for additional context
///
/// ## Quick Start
///
/// ### 1. Define Your Event Types
///
/// ```dart
/// class UserLoginEvent extends TypedEvent {
///   final String userId;
///   final DateTime timestamp;
///
///   UserLoginEvent({required this.userId, required this.timestamp});
///
///   @override
///   String get type => 'user_login';
///
///   @override
///   Map<String, dynamic> toJson() => {
///     'userId': userId,
///     'timestamp': timestamp.millisecondsSinceEpoch,
///   };
///
///   factory UserLoginEvent.fromJson(Map<String, dynamic> json) {
///     return UserLoginEvent(
///       userId: json['userId'] as String,
///       timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
///     );
///   }
/// }
/// ```
///
/// ### 2. Register Event Types
///
/// ```dart
/// void main() {
///   final registry = TypedEventRegistry();
///
///   registry.register<UserLoginEvent>(
///     'user_login',
///     (json) => UserLoginEvent.fromJson(json),
///   );
///
///   // ... rest of your application
/// }
/// ```
///
/// ### 3. Use Typed Events with GossipNode
///
/// ```dart
/// import 'package:gossip/gossip.dart';
/// import 'package:gossip_typed_events/gossip_typed_events.dart';
///
/// // Create and broadcast typed events
/// final loginEvent = UserLoginEvent(
///   userId: 'user123',
///   timestamp: DateTime.now(),
/// );
///
/// await node.broadcastTypedEvent(loginEvent);
///
/// // Listen for typed events
/// node.onTypedEvent<UserLoginEvent>((json) => UserLoginEvent.fromJson(json))
///     .listen((event) {
///   print('User ${event.userId} logged in at ${event.timestamp}');
/// });
///
/// // Or use the registry for automatic deserialization
/// node.onRegisteredTypedEvent<UserLoginEvent>().listen((event) {
///   print('User ${event.userId} logged in');
/// });
/// ```
///
/// ## Advanced Usage
///
/// ### Event Validation
///
/// ```dart
/// class OrderEvent extends TypedEvent with TypedEventMixin {
///   final String orderId;
///   final double amount;
///
///   OrderEvent({required this.orderId, required this.amount});
///
///   @override
///   String get type => 'order_created';
///
///   @override
///   void validate() {
///     super.validate();
///     if (orderId.isEmpty) throw ArgumentError('orderId cannot be empty');
///     if (amount <= 0) throw ArgumentError('amount must be positive');
///   }
///
///   @override
///   Map<String, dynamic> toJson() => {
///     ...toJsonWithMetadata(),
///     'orderId': orderId,
///     'amount': amount,
///   };
/// }
/// ```
///
/// ### Stream Transformers
///
/// ```dart
/// // Transform raw events to typed events
/// final typedStream = rawEventStream.transform(
///   typedEventTransformer<UserLoginEvent>(
///     eventType: 'user_login',
///     factory: (json) => UserLoginEvent.fromJson(json),
///   ),
/// );
///
/// // Multi-type transformer
/// final multiStream = rawEventStream.transform(
///   multiTypeEventTransformer(
///     includeTypes: {'user_login', 'user_logout', 'order_created'},
///   ),
/// );
/// ```
///
/// ### Metadata and Timestamps
///
/// ```dart
/// class EnhancedEvent extends TypedEvent with TypedEventMixin {
///   EnhancedEvent() {
///     setMetadata('source', 'mobile_app');
///     setMetadata('version', '1.2.3');
///   }
///
///   @override
///   String get type => 'enhanced_event';
///
///   @override
///   Map<String, dynamic> toJson() => {
///     ...toJsonWithMetadata(), // Includes createdAt and metadata
///     'data': 'some_data',
///   };
/// }
/// ```
///
/// ## Architecture
///
/// This library extends the core gossip protocol with type safety while
/// maintaining full backward compatibility:
///
/// ```
/// ┌─────────────────────────────────────────┐
/// │           Your Application              │
/// ├─────────────────────────────────────────┤
/// │      Typed Events (this library)       │
/// │  ┌─────────────┐  ┌─────────────────┐   │
/// │  │ TypedEvent  │  │ TypedGossipNode │   │
/// │  └─────────────┘  └─────────────────┘   │
/// ├─────────────────────────────────────────┤
/// │         Core Gossip Protocol            │
/// │  ┌─────────────┐  ┌─────────────────┐   │
/// │  │    Event    │  │   GossipNode    │   │
/// │  └─────────────┘  └─────────────────┘   │
/// └─────────────────────────────────────────┘
/// ```
///
/// ## Best Practices
///
/// - **Type Consistency**: Use consistent type identifiers across your application
/// - **Validation**: Implement validation for critical event types
/// - **Registry Management**: Register all event types at application startup
/// - **Error Handling**: Handle deserialization errors gracefully
/// - **Versioning**: Consider versioning your event schemas for backward compatibility
/// - **Testing**: Test both serialization and deserialization of your events
///
/// ## Performance Considerations
///
/// - **Lazy Deserialization**: Events are only deserialized when accessed
/// - **Efficient Filtering**: Stream transformers filter at the gossip level
/// - **Registry Overhead**: Minimal overhead from the singleton registry
/// - **Memory Usage**: TypedEvents have similar memory footprint to raw events
///
/// ## Error Handling
///
/// All typed event operations provide comprehensive error handling:
///
/// ```dart
/// try {
///   await node.broadcastTypedEvent(event);
/// } on TypedEventException catch (e) {
///   print('Failed to broadcast event: ${e.message}');
/// } on TypedEventRegistryException catch (e) {
///   print('Registry error: ${e.message}');
/// }
/// ```
library gossip_typed_events;

// Core exports
export 'src/typed_event.dart';
export 'src/typed_event_mixin.dart';
export 'src/typed_event_registry.dart';
export 'src/typed_event_transformer.dart';
export 'src/typed_gossip_node.dart';
