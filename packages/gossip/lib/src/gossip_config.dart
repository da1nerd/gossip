/// Configuration options for gossip protocol behavior.
///
/// This module provides configuration classes that control various aspects
/// of the gossip protocol, including timing, peer selection, and synchronization
/// behavior. Configuration is designed to be immutable and validated at creation time.
library;

import 'exceptions.dart';

/// Configuration for gossip protocol behavior.
///
/// This class contains all the configurable parameters that control how
/// the gossip protocol operates. All configurations are validated at
/// creation time and are immutable once created.
class GossipConfig {
  /// Unique identifier for this node in the gossip network.
  final String nodeId;

  /// Interval between gossip cycles.
  ///
  /// This determines how frequently this node will initiate gossip
  /// exchanges with its peers. Shorter intervals provide faster
  /// convergence but higher network overhead.
  final Duration gossipInterval;

  /// Number of peers to gossip with in each cycle.
  ///
  /// Higher fanout values provide better reliability and faster convergence
  /// but increase network traffic. A value of 3-5 is typically optimal.
  final int fanout;

  /// Maximum time to wait for a gossip operation to complete.
  ///
  /// If a gossip exchange with a peer takes longer than this timeout,
  /// the operation will be cancelled and potentially retried with
  /// a different peer.
  final Duration gossipTimeout;

  /// Maximum number of events to include in a single gossip message.
  ///
  /// This prevents oversized messages and helps control memory usage
  /// and network bandwidth. Events are prioritized by timestamp.
  final int maxEventsPerMessage;

  /// Maximum size in bytes for a single gossip message.
  ///
  /// If a message would exceed this size, it will be split across
  /// multiple messages or events will be prioritized.
  final int maxMessageSizeBytes;

  /// Strategy for selecting which peers to gossip with.
  final PeerSelectionStrategy peerSelectionStrategy;

  /// Whether to enable anti-entropy mechanisms.
  ///
  /// Anti-entropy helps ensure eventual consistency by periodically
  /// performing more comprehensive synchronization with peers.
  final bool enableAntiEntropy;

  /// Interval for anti-entropy operations (if enabled).
  final Duration antiEntropyInterval;

  /// Maximum age of events to include in anti-entropy exchanges.
  ///
  /// Older events may be excluded to prevent unbounded growth
  /// of synchronization messages.
  final Duration maxEventAge;

  /// Whether to enable duplicate detection and prevention.
  ///
  /// When enabled, the gossip protocol will track and prevent
  /// duplicate events from being processed multiple times.
  final bool enableDuplicateDetection;

  /// Size of the duplicate detection cache.
  ///
  /// Only relevant when duplicate detection is enabled.
  /// Larger caches provide better duplicate detection but use more memory.
  final int duplicateCacheSize;

  /// Interval for peer discovery.
  ///
  /// Determines how often the node will attempt to discover new peers.
  final Duration peerDiscoveryInterval;

  /// Whether to enable vector clock garbage collection.
  ///
  /// When enabled, the node will periodically remove vector clock entries
  /// for nodes that haven't been seen for longer than nodeExpirationAge.
  /// This prevents unbounded growth of vector clocks in systems with high
  /// node churn.
  final bool enableVectorClockGC;

  /// Maximum time to retain vector clock entries for inactive nodes.
  ///
  /// Nodes not seen for longer than this duration will have their
  /// vector clock entries removed during garbage collection.
  /// Only relevant when enableVectorClockGC is true.
  final Duration nodeExpirationAge;

  /// Creates a new gossip configuration with the specified parameters.
  ///
  /// All required parameters must be provided. Optional parameters have
  /// sensible defaults. Configuration is validated at creation time.
  GossipConfig({
    required this.nodeId,
    this.gossipInterval = const Duration(seconds: 1),
    this.fanout = 3,
    this.gossipTimeout = const Duration(seconds: 10),
    this.maxEventsPerMessage = 100,
    this.maxMessageSizeBytes = 1024 * 1024, // 1MB
    this.peerSelectionStrategy = PeerSelectionStrategy.random,
    this.enableAntiEntropy = true,
    this.antiEntropyInterval = const Duration(minutes: 5),
    this.maxEventAge = const Duration(hours: 24),
    this.enableDuplicateDetection = true,
    this.duplicateCacheSize = 10000,
    this.peerDiscoveryInterval = const Duration(minutes: 1),
    this.enableVectorClockGC = false,
    this.nodeExpirationAge = const Duration(days: 7),
  }) {
    _validate();
  }

  /// Creates a configuration optimized for high-throughput scenarios.
  ///
  /// This configuration uses more aggressive settings for faster convergence
  /// at the cost of higher resource usage.
  factory GossipConfig.highThroughput({
    required String nodeId,
    Duration? gossipInterval,
    int? fanout,
  }) {
    return GossipConfig(
      nodeId: nodeId,
      gossipInterval: gossipInterval ?? const Duration(milliseconds: 500),
      fanout: fanout ?? 5,
      gossipTimeout: const Duration(seconds: 5),
      maxEventsPerMessage: 200,
      maxMessageSizeBytes: 2 * 1024 * 1024, // 2MB
      enableAntiEntropy: true,
      antiEntropyInterval: const Duration(minutes: 2),
      enableVectorClockGC: true, // Enable for high throughput scenarios
      nodeExpirationAge: const Duration(days: 1), // Shorter expiration
    );
  }

  /// Creates a configuration optimized for low-resource scenarios.
  ///
  /// This configuration uses conservative settings to minimize resource
  /// usage at the cost of slower convergence.
  factory GossipConfig.lowResource({
    required String nodeId,
    Duration? gossipInterval,
    int? fanout,
  }) {
    return GossipConfig(
      nodeId: nodeId,
      gossipInterval: gossipInterval ?? const Duration(seconds: 5),
      fanout: fanout ?? 2,
      gossipTimeout: const Duration(seconds: 30),
      maxEventsPerMessage: 50,
      maxMessageSizeBytes: 512 * 1024, // 512KB
      enableAntiEntropy: false,
      duplicateCacheSize: 1000,
      enableVectorClockGC: false, // Keep disabled for low resource scenarios
    );
  }

  /// Creates a copy of this configuration with optionally modified values.
  GossipConfig copyWith({
    String? nodeId,
    Duration? gossipInterval,
    int? fanout,
    Duration? gossipTimeout,
    int? maxEventsPerMessage,
    int? maxMessageSizeBytes,
    PeerSelectionStrategy? peerSelectionStrategy,
    bool? enableAntiEntropy,
    Duration? antiEntropyInterval,
    Duration? maxEventAge,
    bool? enableDuplicateDetection,
    int? duplicateCacheSize,
    Duration? peerDiscoveryInterval,
    bool? enableVectorClockGC,
    Duration? nodeExpirationAge,
  }) {
    return GossipConfig(
      nodeId: nodeId ?? this.nodeId,
      gossipInterval: gossipInterval ?? this.gossipInterval,
      fanout: fanout ?? this.fanout,
      gossipTimeout: gossipTimeout ?? this.gossipTimeout,
      maxEventsPerMessage: maxEventsPerMessage ?? this.maxEventsPerMessage,
      maxMessageSizeBytes: maxMessageSizeBytes ?? this.maxMessageSizeBytes,
      peerSelectionStrategy:
          peerSelectionStrategy ?? this.peerSelectionStrategy,
      enableAntiEntropy: enableAntiEntropy ?? this.enableAntiEntropy,
      antiEntropyInterval: antiEntropyInterval ?? this.antiEntropyInterval,
      maxEventAge: maxEventAge ?? this.maxEventAge,
      enableDuplicateDetection:
          enableDuplicateDetection ?? this.enableDuplicateDetection,
      duplicateCacheSize: duplicateCacheSize ?? this.duplicateCacheSize,
      peerDiscoveryInterval:
          peerDiscoveryInterval ?? this.peerDiscoveryInterval,
      enableVectorClockGC: enableVectorClockGC ?? this.enableVectorClockGC,
      nodeExpirationAge: nodeExpirationAge ?? this.nodeExpirationAge,
    );
  }

  /// Validates the configuration parameters.
  ///
  /// Throws [InvalidConfigurationException] if any parameters are invalid.
  void _validate() {
    if (nodeId.isEmpty) {
      throw const InvalidConfigurationException('Node ID cannot be empty');
    }

    if (gossipInterval.inMilliseconds <= 0) {
      throw const InvalidConfigurationException(
        'Gossip interval must be positive',
      );
    }

    if (fanout <= 0) {
      throw const InvalidConfigurationException('Fanout must be positive');
    }

    if (gossipTimeout.inMilliseconds <= 0) {
      throw const InvalidConfigurationException(
        'Gossip timeout must be positive',
      );
    }

    if (maxEventsPerMessage <= 0) {
      throw const InvalidConfigurationException(
        'Max events per message must be positive',
      );
    }

    if (maxMessageSizeBytes <= 0) {
      throw const InvalidConfigurationException(
        'Max message size must be positive',
      );
    }

    if (enableAntiEntropy && antiEntropyInterval.inMilliseconds <= 0) {
      throw const InvalidConfigurationException(
        'Anti-entropy interval must be positive when anti-entropy is enabled',
      );
    }

    if (maxEventAge.inMilliseconds <= 0) {
      throw const InvalidConfigurationException(
        'Max event age must be positive',
      );
    }

    if (enableDuplicateDetection && duplicateCacheSize <= 0) {
      throw const InvalidConfigurationException(
        'Duplicate cache size must be positive when duplicate detection is enabled',
      );
    }

    // Logical validations
    if (gossipTimeout <= gossipInterval) {
      throw const InvalidConfigurationException(
        'Gossip timeout should be greater than gossip interval',
      );
    }

    if (fanout > 50) {
      throw const InvalidConfigurationException(
        'Fanout too high (>50), this may cause excessive network traffic',
      );
    }

    if (enableVectorClockGC && nodeExpirationAge.inMilliseconds <= 0) {
      throw const InvalidConfigurationException(
        'Node expiration age must be positive when vector clock GC is enabled',
      );
    }
  }

  @override
  String toString() {
    return 'GossipConfig('
        'nodeId: $nodeId, '
        'gossipInterval: $gossipInterval, '
        'fanout: $fanout, '
        'gossipTimeout: $gossipTimeout, '
        'maxEventsPerMessage: $maxEventsPerMessage, '
        'maxMessageSizeBytes: $maxMessageSizeBytes, '
        'peerSelectionStrategy: $peerSelectionStrategy, '
        'enableAntiEntropy: $enableAntiEntropy, '
        'antiEntropyInterval: $antiEntropyInterval, '
        'maxEventAge: $maxEventAge, '
        'enableDuplicateDetection: $enableDuplicateDetection, '
        'duplicateCacheSize: $duplicateCacheSize, '
        'peerDiscoveryInterval: $peerDiscoveryInterval, '
        'enableVectorClockGC: $enableVectorClockGC, '
        'nodeExpirationAge: $nodeExpirationAge'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! GossipConfig) return false;

    return nodeId == other.nodeId &&
        gossipInterval == other.gossipInterval &&
        fanout == other.fanout &&
        gossipTimeout == other.gossipTimeout &&
        maxEventsPerMessage == other.maxEventsPerMessage &&
        maxMessageSizeBytes == other.maxMessageSizeBytes &&
        peerSelectionStrategy == other.peerSelectionStrategy &&
        enableAntiEntropy == other.enableAntiEntropy &&
        antiEntropyInterval == other.antiEntropyInterval &&
        maxEventAge == other.maxEventAge &&
        enableDuplicateDetection == other.enableDuplicateDetection &&
        duplicateCacheSize == other.duplicateCacheSize &&
        peerDiscoveryInterval == other.peerDiscoveryInterval &&
        enableVectorClockGC == other.enableVectorClockGC &&
        nodeExpirationAge == other.nodeExpirationAge;
  }

  @override
  int get hashCode {
    return Object.hash(
      nodeId,
      gossipInterval,
      fanout,
      gossipTimeout,
      maxEventsPerMessage,
      maxMessageSizeBytes,
      peerSelectionStrategy,
      enableAntiEntropy,
      antiEntropyInterval,
      maxEventAge,
      enableDuplicateDetection,
      duplicateCacheSize,
      peerDiscoveryInterval,
      enableVectorClockGC,
      nodeExpirationAge,
    );
  }
}

/// Strategy for selecting which peers to gossip with.
enum PeerSelectionStrategy {
  /// Select peers randomly.
  ///
  /// This is the most common strategy and provides good load distribution
  /// across the network.
  random,

  /// Select peers with the oldest last contact time.
  ///
  /// This strategy ensures that all peers are contacted regularly
  /// and can help maintain better consistency.
  leastRecentlyContacted,

  /// Select peers based on their reliability/response time.
  ///
  /// Prioritizes peers that have been responsive and reliable
  /// in past gossip exchanges.
  mostReliable,

  /// Round-robin selection of peers.
  ///
  /// Cycles through all known peers in order, ensuring
  /// each peer is contacted equally.
  roundRobin,
}
