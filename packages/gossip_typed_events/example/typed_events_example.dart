/// Comprehensive example demonstrating typed events with the gossip protocol.
///
/// This example shows how to:
/// - Define custom typed events
/// - Register event types
/// - Create and broadcast typed events
/// - Listen for specific event types
/// - Use validation and metadata
/// - Handle errors gracefully
library;

import 'dart:async';
import 'dart:math';

import 'package:gossip/gossip.dart';
import 'package:gossip_typed_events/gossip_typed_events.dart';

// Define custom typed events for a simple e-commerce system

/// User authentication event
class UserLoginEvent extends TypedEvent with TypedEventMixin {
  UserLoginEvent({
    required this.userId,
    required this.sessionId,
    required this.ipAddress,
    required this.loginTime,
  });

  factory UserLoginEvent.fromJson(Map<String, dynamic> json) {
    final event = UserLoginEvent(
      userId: json['userId'] as String,
      sessionId: json['sessionId'] as String,
      ipAddress: json['ipAddress'] as String,
      loginTime: DateTime.fromMillisecondsSinceEpoch(json['loginTime'] as int),
    );

    event.fromJsonWithMetadata(json);
    return event;
  }
  final String userId;
  final String sessionId;
  final String ipAddress;
  final DateTime loginTime;

  @override
  String get type => 'user_login';

  @override
  void validate() {
    super.validate();
    if (userId.isEmpty) throw ArgumentError('userId cannot be empty');
    if (sessionId.isEmpty) throw ArgumentError('sessionId cannot be empty');
  }

  @override
  Map<String, dynamic> toJson() => {
    ...toJsonWithMetadata(),
    'userId': userId,
    'sessionId': sessionId,
    'ipAddress': ipAddress,
    'loginTime': loginTime.millisecondsSinceEpoch,
  };

  @override
  String toString() => 'UserLoginEvent(userId: $userId, sessionId: $sessionId)';
}

/// Order creation event
class OrderCreatedEvent extends TypedEvent with TypedEventMixin {
  OrderCreatedEvent({
    required this.orderId,
    required this.customerId,
    required this.items,
    required this.totalAmount,
    required this.currency,
  });

  factory OrderCreatedEvent.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'] as List;
    final items = itemsJson
        .cast<Map<String, dynamic>>()
        .map(OrderItem.fromJson)
        .toList();

    final event = OrderCreatedEvent(
      orderId: json['orderId'] as String,
      customerId: json['customerId'] as String,
      items: items,
      totalAmount: (json['totalAmount'] as num).toDouble(),
      currency: json['currency'] as String,
    );

    event.fromJsonWithMetadata(json);
    return event;
  }
  final String orderId;
  final String customerId;
  final List<OrderItem> items;
  final double totalAmount;
  final String currency;

  @override
  String get type => 'order_created';

  @override
  void validate() {
    super.validate();
    if (orderId.isEmpty) throw ArgumentError('orderId cannot be empty');
    if (customerId.isEmpty) throw ArgumentError('customerId cannot be empty');
    if (items.isEmpty) throw ArgumentError('order must have at least one item');
    if (totalAmount <= 0) throw ArgumentError('totalAmount must be positive');
  }

  @override
  Map<String, dynamic> toJson() => {
    ...toJsonWithMetadata(),
    'orderId': orderId,
    'customerId': customerId,
    'items': items.map((item) => item.toJson()).toList(),
    'totalAmount': totalAmount,
    'currency': currency,
  };

  @override
  String toString() =>
      'OrderCreatedEvent(orderId: $orderId, customerId: $customerId, total: $totalAmount $currency)';
}

/// Inventory update event
class InventoryUpdateEvent extends TypedEvent {
  InventoryUpdateEvent({
    required this.productId,
    required this.quantityChange,
    required this.newQuantity,
    required this.reason,
  });

  factory InventoryUpdateEvent.fromJson(Map<String, dynamic> json) =>
      InventoryUpdateEvent(
        productId: json['productId'] as String,
        quantityChange: json['quantityChange'] as int,
        newQuantity: json['newQuantity'] as int,
        reason: json['reason'] as String,
      );
  final String productId;
  final int quantityChange;
  final int newQuantity;
  final String reason;

  @override
  String get type => 'inventory_update';

  @override
  Map<String, dynamic> toJson() => {
    'productId': productId,
    'quantityChange': quantityChange,
    'newQuantity': newQuantity,
    'reason': reason,
  };

  @override
  String toString() =>
      'InventoryUpdateEvent(productId: $productId, change: $quantityChange, new: $newQuantity)';
}

/// Supporting data structures
class OrderItem {
  OrderItem({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    productId: json['productId'] as String,
    quantity: json['quantity'] as int,
    unitPrice: (json['unitPrice'] as num).toDouble(),
  );
  final String productId;
  final int quantity;
  final double unitPrice;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'quantity': quantity,
    'unitPrice': unitPrice,
  };
}

/// Simple in-memory transport for the example
class InMemoryTransport implements GossipTransport {
  InMemoryTransport(this.nodeId, this._nodeRegistry);
  final String nodeId;
  final Map<String, InMemoryTransport> _nodeRegistry;

  final StreamController<IncomingDigest> _digestController =
      StreamController<IncomingDigest>.broadcast();
  final StreamController<IncomingEvents> _eventsController =
      StreamController<IncomingEvents>.broadcast();

  @override
  Future<void> initialize() async {
    _nodeRegistry[nodeId] = this;
  }

  @override
  Future<void> shutdown() async {
    _nodeRegistry.remove(nodeId);
    await _digestController.close();
    await _eventsController.close();
  }

  @override
  Future<GossipDigestResponse> sendDigest(
    TransportPeer transportPeer,
    GossipDigest digest, {
    Duration? timeout,
  }) async {
    final targetTransport = _nodeRegistry[transportPeer.transportId.value];
    if (targetTransport == null) {
      throw TransportException('Peer ${transportPeer.transportId} not found');
    }

    final completer = Completer<GossipDigestResponse>();

    final incomingDigest = IncomingDigest(
      fromTransportPeer: TransportPeer(
        transportId: TransportPeerAddress(nodeId),
        displayName: nodeId,
        connectedAt: DateTime.now(),
      ),
      digest: digest,
      respond: (response) async {
        completer.complete(response);
      },
    );

    targetTransport._digestController.add(incomingDigest);
    return completer.future;
  }

  @override
  Future<void> sendEvents(
    TransportPeer transportPeer,
    GossipEventMessage message, {
    Duration? timeout,
  }) async {
    final targetTransport = _nodeRegistry[transportPeer.transportId.value];
    if (targetTransport == null) {
      throw TransportException('Peer ${transportPeer.transportId} not found');
    }

    final incomingEvents = IncomingEvents(
      fromTransportPeer: TransportPeer(
        transportId: TransportPeerAddress(nodeId),
        displayName: nodeId,
        connectedAt: DateTime.now(),
      ),
      message: message,
    );

    targetTransport._eventsController.add(incomingEvents);
  }

  @override
  Stream<IncomingDigest> get incomingDigests => _digestController.stream;

  @override
  Stream<IncomingEvents> get incomingEvents => _eventsController.stream;

  @override
  Future<List<TransportPeer>> discoverPeers() async => _nodeRegistry.keys
      .where((id) => id != nodeId)
      .map(
        (id) => TransportPeer(
          transportId: TransportPeerAddress(id),
          displayName: id,
          connectedAt: DateTime.now(),
        ),
      )
      .toList();

  @override
  Future<bool> isPeerReachable(TransportPeer transportPeer) async =>
      _nodeRegistry.containsKey(transportPeer.transportId.value);
}

void main() async {
  print('🚀 Starting Typed Events Gossip Example\n');

  // Register typed events
  await _registerEventTypes();

  // Set up gossip network
  final transportRegistry = <String, InMemoryTransport>{};
  final nodes = await _createNodes(transportRegistry);

  try {
    // Start all nodes
    print('📡 Starting gossip nodes...');
    await Future.wait(nodes.map((node) => node.start()));

    // Set up event listeners
    _setupEventListeners(nodes);

    // Wait for nodes to discover each other
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await Future.wait(nodes.map((node) => node.discoverPeers()));

    print('🔗 Nodes connected and ready\n');

    // Simulate business activities
    await _simulateBusinessActivity(nodes);

    // Wait for events to propagate
    print('\n⏳ Waiting for event propagation...');
    await Future<void>.delayed(const Duration(seconds: 3));

    // Show final statistics
    await _showStatistics(nodes);

    // Demonstrate error handling
    await _demonstrateErrorHandling(nodes.first);

    // Demonstrate stream transformers
    await _demonstrateStreamTransformers(nodes.first);
  } finally {
    // Clean up
    print('\n🛑 Shutting down...');
    await Future.wait(nodes.map((node) => node.stop()));
  }

  print('✅ Example completed successfully!');
}

/// Register all event types in the global registry
Future<void> _registerEventTypes() async {
  final registry = TypedEventRegistry();

  print('📝 Registering event types...');

  registry.register<UserLoginEvent>('user_login', UserLoginEvent.fromJson);

  registry.register<OrderCreatedEvent>(
    'order_created',
    OrderCreatedEvent.fromJson,
  );

  registry.register<InventoryUpdateEvent>(
    'inventory_update',
    InventoryUpdateEvent.fromJson,
  );

  final stats = registry.getStats();
  print(
    '   Registered ${stats.totalRegisteredTypes} event types: ${stats.registeredTypes}',
  );
}

/// Create gossip nodes
Future<List<GossipNode>> _createNodes(
  Map<String, InMemoryTransport> transportRegistry,
) async {
  final nodes = <GossipNode>[];

  final nodeConfigs = [
    ('WebServer', const Duration(milliseconds: 500)),
    ('OrderService', const Duration(milliseconds: 600)),
    ('InventoryService', const Duration(milliseconds: 700)),
  ];

  for (final (nodeId, gossipInterval) in nodeConfigs) {
    final config = GossipConfig(
      nodeId: nodeId,
      gossipInterval: gossipInterval,
      fanout: 2,
    );

    final node = GossipNode(
      config: config,
      eventStore: MemoryEventStore(),
      transport: InMemoryTransport(nodeId, transportRegistry),
    );

    nodes.add(node);
  }

  return nodes;
}

/// Set up typed event listeners for each node
void _setupEventListeners(List<GossipNode> nodes) {
  for (final node in nodes) {
    final nodeId = node.config.nodeId;

    // Listen for user login events
    node.onRegisteredTypedEvent<UserLoginEvent>().listen((event) {
      print(
        '🔐 [$nodeId] User ${event.userId} logged in from ${event.ipAddress}',
      );

      // Show metadata if available
      final source = event.getMetadata<String>('source');
      if (source != null) {
        print('    Source: $source');
      }
    });

    // Listen for order events
    node.onTypedEvent<OrderCreatedEvent>(OrderCreatedEvent.fromJson).listen((
      event,
    ) {
      print(
        '🛒 [$nodeId] Order ${event.orderId} created for customer ${event.customerId}',
      );
      print(
        '    Items: ${event.items.length}, Total: \$${event.totalAmount.toStringAsFixed(2)} ${event.currency}',
      );
      print('    Created at: ${event.createdAt}');
    });

    // Listen for inventory updates
    node.onRegisteredTypedEvent<InventoryUpdateEvent>().listen((event) {
      print('📦 [$nodeId] Inventory update for ${event.productId}:');
      print(
        '    Change: ${event.quantityChange > 0 ? '+' : ''}${event.quantityChange}',
      );
      print('    New quantity: ${event.newQuantity}');
      print('    Reason: ${event.reason}');
    });

    // Listen for any typed event with metadata
    node.onAnyTypedEvent().listen((typedReceived) {
      print(
        '📨 [$nodeId] Received ${typedReceived.eventType} from ${typedReceived.fromPeer.id}',
      );
    });
  }
}

/// Simulate business activity with typed events
Future<void> _simulateBusinessActivity(List<GossipNode> nodes) async {
  final random = Random();
  final webServer = nodes[0]; // WebServer node
  final orderService = nodes[1]; // OrderService node
  final inventoryService = nodes[2]; // InventoryService node

  print('🎭 Simulating business activity...\n');

  // 1. User logs in (with metadata)
  final loginEvent = UserLoginEvent(
    userId: 'user_${random.nextInt(1000)}',
    sessionId: 'session_${random.nextInt(10000)}',
    ipAddress: '192.168.1.${random.nextInt(255)}',
    loginTime: DateTime.now(),
  );

  // Add metadata
  loginEvent.setMetadata('source', 'mobile_app');
  loginEvent.setMetadata('device', 'iPhone 14');
  loginEvent.setMetadata('app_version', '2.1.0');

  print('🔐 Broadcasting user login event...');
  await webServer.createTypedEvent(loginEvent);
  await Future<void>.delayed(const Duration(milliseconds: 200));

  // 2. Customer creates an order
  final orderEvent = OrderCreatedEvent(
    orderId: 'order_${random.nextInt(10000)}',
    customerId: loginEvent.userId,
    items: [
      OrderItem(productId: 'prod_001', quantity: 2, unitPrice: 29.99),
      OrderItem(productId: 'prod_002', quantity: 1, unitPrice: 49.99),
    ],
    totalAmount: 109.97,
    currency: 'USD',
  );

  print('🛒 Broadcasting order creation event...');
  await orderService.createTypedEvent(orderEvent);
  await Future<void>.delayed(const Duration(milliseconds: 200));

  // 3. Inventory gets updated (multiple events)
  final inventoryEvents = [
    InventoryUpdateEvent(
      productId: 'prod_001',
      quantityChange: -2,
      newQuantity: 48,
      reason: 'Order ${orderEvent.orderId}',
    ),
    InventoryUpdateEvent(
      productId: 'prod_002',
      quantityChange: -1,
      newQuantity: 23,
      reason: 'Order ${orderEvent.orderId}',
    ),
  ];

  print('📦 Broadcasting inventory updates...');
  for (final event in inventoryEvents) {
    await inventoryService.createTypedEvent(event);
  }
  await Future<void>.delayed(const Duration(milliseconds: 200));

  // 4. Batch operation example
  final batchEvents = <TypedEvent>[
    UserLoginEvent(
      userId: 'user_${random.nextInt(1000)}',
      sessionId: 'session_${random.nextInt(10000)}',
      ipAddress: '10.0.0.${random.nextInt(255)}',
      loginTime: DateTime.now(),
    ),
    InventoryUpdateEvent(
      productId: 'prod_003',
      quantityChange: 50,
      newQuantity: 150,
      reason: 'Restocking',
    ),
  ];

  print('📦 Broadcasting batch events...');
  for (final event in batchEvents) {
    await webServer.createTypedEvent(event);
  }
}

/// Show statistics for all nodes
Future<void> _showStatistics(List<GossipNode> nodes) async {
  print('\n📊 Final Statistics:');
  print('=====================');

  for (final node in nodes) {
    final nodeId = node.config.nodeId;
    final events = await node.eventStore.getAllEvents();
    final stats = await node.eventStore.getStats();

    print('$nodeId:');
    print('  Total events: ${events.length}');
    print('  Unique nodes: ${stats.uniqueNodes}');
    print('  Vector clock: ${node.vectorClock}');

    // Count events by type
    final typeCounts = <String, int>{};
    for (final event in events) {
      final payload = event.payload;
      if (payload.containsKey('type')) {
        final type = payload['type'] as String;
        typeCounts[type] = (typeCounts[type] ?? 0) + 1;
      }
    }

    if (typeCounts.isNotEmpty) {
      print('  Event types: $typeCounts');
    }
    print('');
  }
}

/// Demonstrate error handling with typed events
Future<void> _demonstrateErrorHandling(GossipNode node) async {
  print('🚨 Demonstrating error handling...\n');

  try {
    // Try to broadcast an invalid event (this will fail validation)
    final invalidOrder = OrderCreatedEvent(
      orderId: '', // Empty order ID will fail validation
      customerId: 'test',
      items: [],
      totalAmount: -100, // Negative amount will fail
      currency: 'USD',
    );

    await node.createTypedEvent(invalidOrder);
  } on TypedEventException catch (e) {
    print('❌ Caught expected validation error: ${e.message}');
  }

  try {
    // Try to use an unregistered event type
    final registry = TypedEventRegistry();
    final unknownEvent = registry.createFromJson('unknown_type', {
      'data': 'test',
    });
    print('Unknown event result: $unknownEvent'); // Will be null
  } catch (e) {
    print('❌ Registry error: $e');
  }

  print('✅ Error handling demonstration complete\n');
}

/// Demonstrate stream transformers
Future<void> _demonstrateStreamTransformers(GossipNode node) async {
  print('🔄 Demonstrating stream transformers...\n');

  // Create a stream controller to simulate incoming events
  final eventController = StreamController<Event>.broadcast();

  // Set up transformers
  final userEventStream = eventController.stream.transform(
    typedEventTransformer<UserLoginEvent>(
      eventType: 'user_login',
      factory: UserLoginEvent.fromJson,
    ),
  );

  final multiTypeStream = eventController.stream.transform(
    multiTypeEventTransformer(
      includeTypes: {'user_login', 'order_created'},
      onError: (event, error, stackTrace) {
        print('🚨 Transformer error for event ${event.id}: $error');
      },
    ),
  );

  // Listen to transformed streams
  final userSubscription = userEventStream.listen((event) {
    print('🎯 Filtered user event: ${event.userId}');
  });

  final multiSubscription = multiTypeStream.listen((event) {
    print('🎯 Multi-type event: ${event.type}');
  });

  // Simulate some events through the stream
  await Future<void>.delayed(const Duration(milliseconds: 100));

  // Create a mock typed event wrapped in gossip event format
  final mockLoginEvent = UserLoginEvent(
    userId: 'transformer_test_user',
    sessionId: 'test_session',
    ipAddress: '127.0.0.1',
    loginTime: DateTime.now(),
  );

  final wrappedEvent = Event(
    id: 'transformer_test',
    nodeId: 'test_node',
    timestamp: 1,
    creationTimestamp: DateTime.now().millisecondsSinceEpoch,
    payload: {
      'type': 'user_login',
      'data': mockLoginEvent.toJson(),
      'version': '1.0',
    },
  );

  eventController.add(wrappedEvent);

  // Wait a bit for processing
  await Future<void>.delayed(const Duration(milliseconds: 100));

  // Clean up
  await userSubscription.cancel();
  await multiSubscription.cancel();
  await eventController.close();

  print('✅ Stream transformer demonstration complete');
}
