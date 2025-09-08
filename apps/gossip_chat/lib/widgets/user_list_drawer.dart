import 'package:flutter/material.dart';
import 'package:gossip_chat_demo/models/chat_peer.dart';
import 'package:provider/provider.dart';

import '../services/gossip_chat_service.dart';

class UserListDrawer extends StatelessWidget {
  const UserListDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).primaryColor),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.people, color: Colors.white, size: 48),
                SizedBox(height: 16),
                Text(
                  'Connected Users',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Consumer<GossipChatService>(
              builder: (context, chatService, child) {
                if (chatService.peers.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_find, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No users connected',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'Make sure other devices are nearby with the app open',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: chatService.peers.length,
                  itemBuilder: (context, index) {
                    final user = chatService.peers[index];
                    return UserTile(peer: user);
                  },
                );
              },
            ),
          ),
          // Current user info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Consumer<GossipChatService>(
              builder: (context, chatService, child) {
                return Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          _getInitials(chatService.nodeName ?? ''),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chatService.nodeName ?? 'Unknown',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'You',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final words = name.trim().split(' ');
    if (words.length == 1) {
      return words[0].substring(0, 1).toUpperCase();
    }
    return '${words[0].substring(0, 1)}${words[1].substring(0, 1)}'
        .toUpperCase();
  }
}

class UserTile extends StatelessWidget {
  final ChatPeer peer;

  const UserTile({super.key, required this.peer});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _getStatusColor(),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            _getInitials(peer.name),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      title: Text(
        peer.name,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(_getStatusText()),
      trailing: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: _getStatusColor(),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final words = name.trim().split(' ');
    if (words.length == 1) {
      return words[0].substring(0, 1).toUpperCase();
    }
    return '${words[0].substring(0, 1)}${words[1].substring(0, 1)}'
        .toUpperCase();
  }

  Color _getStatusColor() {
    return peer.isOnline ? Colors.green : Colors.grey;
  }

  String _getStatusText() {
    if (peer.isOnline) {
      return 'Online';
    } else {
      if (peer.lastSeen != null) {
        final now = DateTime.now();
        final difference = now.difference(peer.lastSeen!);
        if (difference.inMinutes < 1) {
          return 'Last seen just now';
        } else if (difference.inHours < 1) {
          return 'Last seen ${difference.inMinutes}m ago';
        } else if (difference.inDays < 1) {
          return 'Last seen ${difference.inHours}h ago';
        } else {
          return 'Last seen ${difference.inDays}d ago';
        }
      } else {
        return 'Offline';
      }
    }
  }
}
