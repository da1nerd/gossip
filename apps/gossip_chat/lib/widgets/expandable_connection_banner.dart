import 'package:flutter/material.dart';
import 'package:gossip_chat_demo/services/gossip_chat_service.dart';
import 'package:provider/provider.dart';

/// An expandable banner that shows connection status and debug information.
/// Shows a blue banner with "Looking for nearby devices..." that can be tapped
/// to expand and show detailed connection debug information.
class ExpandableConnectionBanner extends StatefulWidget {
  const ExpandableConnectionBanner({super.key});

  @override
  State<ExpandableConnectionBanner> createState() =>
      _ExpandableConnectionBannerState();
}

class _ExpandableConnectionBannerState
    extends State<ExpandableConnectionBanner> {
  bool _isExpanded = false;
  Map<String, dynamic>? _stats;
  bool _isLoadingStats = false;
  GossipChatService? _previousService;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentService = Provider.of<GossipChatService>(
      context,
      listen: false,
    );

    // If service changed, refresh stats
    if (_previousService != currentService) {
      _previousService = currentService;
      if (_isExpanded) {
        _loadStats();
      }
    }
  }

  Future<void> _loadStats() async {
    if (_isLoadingStats) return;

    setState(() {
      _isLoadingStats = true;
    });

    try {
      final chatService = Provider.of<GossipChatService>(
        context,
        listen: false,
      );
      final stats = await chatService.getConnectionStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _stats = {};
          _isLoadingStats = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GossipChatService>(
      builder: (context, chatService, child) {
        final stats = _stats ?? {};

        return GestureDetector(
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
            if (_isExpanded) {
              _loadStats();
            }
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            color: Colors.blue.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.wifi_find, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        chatService.hasConnectedPeers
                            ? '${chatService.connectedPeerCount} device${chatService.connectedPeerCount != 1 ? 's' : ''} connected'
                            : 'Looking for nearby devices...',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.blue.shade700,
                    ),
                  ],
                ),
                if (_isExpanded) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    'Service Status',
                    _getConnectionStatusText(stats),
                  ),
                  _buildInfoRow(
                    'Device Name',
                    chatService.nodeName ?? 'Unknown',
                  ),
                  _buildInfoRow(
                    'Sync Strategy',
                    stats['connectionStrategy']?.toString() ?? 'N/A',
                  ),
                  _buildInfoRow(
                    'Total Messages',
                    chatService.messages.length.toString(),
                  ),
                  _buildInfoRow(
                    'Total Events',
                    _isLoadingStats
                        ? 'Loading...'
                        : (stats['totalEvents']?.toString() ?? '0'),
                  ),
                  _buildInfoRow(
                    'Service ID',
                    stats['serviceId']?.toString() ?? 'N/A',
                  ),
                  _buildInfoRow(
                    'Pending Connections',
                    stats['pendingConnections']?.toString() ?? '0',
                  ),
                  _buildInfoRow(
                    'Connection Attempts',
                    stats['connectionAttempts']?.toString() ?? '0',
                  ),
                  const SizedBox(height: 8),
                  if (!chatService.hasConnectedPeers) ...[
                    Text(
                      '• Advertising your device to nearby phones',
                      style: TextStyle(
                        color: Colors.blue.shade600,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      '• Scanning for other devices with this app',
                      style: TextStyle(
                        color: Colors.blue.shade600,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Make sure: Bluetooth ON, Location ON, other devices within 20m with app open',
                      style: TextStyle(
                        color: Colors.blue.shade600,
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.blue.shade700,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'monospace',
                color: Colors.blue.shade600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getConnectionStatusText(Map<String, dynamic> stats) {
    final isInitialized = stats['initialized'] == true;
    final connectedPeers = stats['connectedPeers'] as int? ?? 0;
    final pendingConnections = stats['pendingConnections'] as int? ?? 0;

    if (!isInitialized) return 'Not Initialized';
    if (connectedPeers > 0) return 'Connected';
    if (pendingConnections > 0) return 'Connecting...';
    return 'Searching...';
  }
}
