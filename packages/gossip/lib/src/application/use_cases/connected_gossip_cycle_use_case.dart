import 'package:gossip/src/application/ports/connected_peer_repository.dart';
import 'package:gossip/src/domain/services/connected_peer_selection_service.dart';
import 'package:gossip/src/application/use_cases/gossip_with_connected_peer_use_case.dart';
import 'package:gossip/src/gossip_config.dart';
import 'package:gossip/src/gossip_node.dart' show GossipExchangeResult;
import 'package:gossip/src/domain/entities/connected_peer.dart';

/// Use case for executing a single gossip cycle using ConnectedPeers.
///
/// This cycle:
/// 1) Loads active connected peers (transport-level, address-keyed)
/// 2) Selects a fanout-sized subset using the strategy from GossipConfig
/// 3) Executes gossip exchanges concurrently against selected peers
/// 4) Returns per-peer exchange results (reliability updates are performed
///    inside the single-peer use case and persisted through the repository)
class ConnectedGossipCycleUseCase {
  final ConnectedPeerRepository connectedPeerRepository;
  final ConnectedPeerSelectionService connectedPeerSelectionService;
  final GossipWithConnectedPeerUseCase gossipWithConnectedPeerUseCase;
  final GossipConfig config;

  ConnectedGossipCycleUseCase({
    required this.connectedPeerRepository,
    required this.connectedPeerSelectionService,
    required this.gossipWithConnectedPeerUseCase,
    required this.config,
  });

  /// Execute one complete connected-peer gossip cycle.
  ///
  /// - Returns empty list if no active peers are available.
  /// - Uses DateTime.now() at call time for each peer exchange start,
  ///   ensuring durations are measured relative to dispatch.
  Future<List<GossipExchangeResult>> execute() async {
    final activePeers = await _loadActivePeers();
    if (activePeers.isEmpty) return const <GossipExchangeResult>[];

    final selected = _selectPeers(activePeers);
    if (selected.isEmpty) return const <GossipExchangeResult>[];

    final results = await _gossipWithSelected(selected);
    return results;
  }

  // --- Private helpers ---

  Future<List<ConnectedPeer>> _loadActivePeers() {
    return connectedPeerRepository.getActiveConnectedPeers();
  }

  List<ConnectedPeer> _selectPeers(List<ConnectedPeer> active) {
    return connectedPeerSelectionService.selectPeersForGossip(
      active,
      config.fanout,
      config.peerSelectionStrategy,
    );
  }

  Future<List<GossipExchangeResult>> _gossipWithSelected(
    List<ConnectedPeer> selected,
  ) async {
    final now = DateTime.now();
    final tasks = selected.map(
      (p) => gossipWithConnectedPeerUseCase.execute(peer: p, now: now),
    );
    return Future.wait(tasks, eagerError: false);
  }
}
