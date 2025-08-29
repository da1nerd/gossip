/// Custom exceptions for the gossip protocol library.
///
/// This module defines specific exception types that can be thrown during
/// gossip protocol operations, providing clear error handling and debugging
/// information for library users.
library;

/// Base class for all gossip protocol related exceptions.
abstract class GossipException implements Exception {
  /// Human-readable error message.
  final String message;

  /// Optional underlying cause of this exception.
  final Object? cause;

  /// Stack trace from where this exception was created.
  final StackTrace? stackTrace;

  const GossipException(this.message, {this.cause, this.stackTrace});

  @override
  String toString() {
    final buffer = StringBuffer('$runtimeType: $message');
    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }
    return buffer.toString();
  }
}

/// Exception thrown when there are issues with event storage operations.
class EventStoreException extends GossipException {
  const EventStoreException(super.message, {super.cause, super.stackTrace});
}

/// Exception thrown when there are issues with network transport operations.
class TransportException extends GossipException {
  const TransportException(super.message, {super.cause, super.stackTrace});
}

/// Exception thrown when gossip node configuration is invalid.
class InvalidConfigurationException extends GossipException {
  const InvalidConfigurationException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// Exception thrown when trying to operate on a node that's not properly initialized.
class NodeNotInitializedException extends GossipException {
  const NodeNotInitializedException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// Exception thrown when a gossip operation times out.
class GossipTimeoutException extends GossipException {
  /// The duration that was exceeded.
  final Duration timeout;

  const GossipTimeoutException(
    super.message,
    this.timeout, {
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() {
    return '${super.toString()}\nTimeout: $timeout';
  }
}

/// Exception thrown when there are issues with vector clock operations.
class VectorClockException extends GossipException {
  const VectorClockException(super.message, {super.cause, super.stackTrace});
}

/// Exception thrown when event serialization/deserialization fails.
class SerializationException extends GossipException {
  /// The data that failed to serialize/deserialize.
  final Object? data;

  const SerializationException(
    super.message, {
    this.data,
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer(super.toString());
    if (data != null) {
      buffer.write('\nData: $data');
    }
    return buffer.toString();
  }
}

/// Exception thrown when peer operations fail.
class PeerException extends GossipException {
  /// The peer that caused the exception.
  final String? peerId;

  const PeerException(
    super.message, {
    this.peerId,
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer(super.toString());
    if (peerId != null) {
      buffer.write('\nPeer ID: $peerId');
    }
    return buffer.toString();
  }
}

/// Exception thrown when duplicate events are detected in contexts where they shouldn't exist.
class DuplicateEventException extends GossipException {
  /// The ID of the duplicate event.
  final String eventId;

  const DuplicateEventException(
    super.message,
    this.eventId, {
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() {
    return '${super.toString()}\nEvent ID: $eventId';
  }
}

/// Exception thrown when an invalid event is encountered.
class InvalidEventException extends GossipException {
  /// The invalid event data.
  final Object? eventData;

  const InvalidEventException(
    super.message, {
    this.eventData,
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer(super.toString());
    if (eventData != null) {
      buffer.write('\nEvent data: $eventData');
    }
    return buffer.toString();
  }
}
