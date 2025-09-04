class ChatPeer {
  final String id;
  final String name;
  final String? address;
  final DateTime connectedAt;
  final ChatPeerStatus status;
  final bool isOnline;
  final DateTime? lastSeen;

  ChatPeer({
    required this.id,
    required this.name,
    this.address,
    DateTime? connectedAt,
    this.status = ChatPeerStatus.connected,
    this.isOnline = true,
    this.lastSeen,
  }) : connectedAt = connectedAt ?? DateTime.now();

  factory ChatPeer.fromJson(Map<String, dynamic> json) {
    return ChatPeer(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String?,
      connectedAt:
          DateTime.fromMillisecondsSinceEpoch(json['connectedAt'] as int),
      status: ChatPeerStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ChatPeerStatus.connected,
      ),
      isOnline: json['isOnline'] as bool? ?? true,
      lastSeen: json['lastSeen'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] as int)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'connectedAt': connectedAt.millisecondsSinceEpoch,
      'status': status.name,
      'isOnline': isOnline,
      'lastSeen': lastSeen?.millisecondsSinceEpoch,
    };
  }

  ChatPeer copyWith({
    String? id,
    String? name,
    String? address,
    DateTime? connectedAt,
    ChatPeerStatus? status,
    bool? isOnline,
    DateTime? lastSeen,
  }) {
    return ChatPeer(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      connectedAt: connectedAt ?? this.connectedAt,
      status: status ?? this.status,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatPeer && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'ChatPeer{id: $id, name: $name, address: $address, status: $status, isOnline: $isOnline, lastSeen: $lastSeen}';
  }
}

enum ChatPeerStatus {
  connecting,
  connected,
  disconnected,
  failed,
}
