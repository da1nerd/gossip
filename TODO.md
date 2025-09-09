# Things to do

## Required for Open Door
- [x] Get nearby connection transport to properly start on initial install.
- [x] Sync entire chat history instead of just the new history.
- [x] Chat users should be added as soon as they are discovered instead of waiting for the next timer.
- Update chat users that are coming back online, as online.
  - [x] Implement a clock store so we don't break syncing.
- [x] Reduce the amount of time between discovery and addition.
- [x] Implement a mechanism for handling disconnections and reconnections gracefully.
- [x] Implement a mechanism for handling network errors and retries.
- [x] Refine the gossip library interface; keep it simple and efficient.
- [x] Make sure typed events are optional for all gossip libraries. (all libraries for that matter)
- [x] Fix some events missing after peer restart.
- [x] Do not display self in peer list.
- [ ] Move general classes out of the transport file.
- [ ] Fix issue with peers randomly disconnecting without notification.
- [ ] Fix peer list not being updated correctly on a peer that was resarted.
- [ ] Propagate events to all peers in the network. It seems to only send events to directly connected peers.
- [ ] Support syncing certain events to only certain peers.
- [ ] Ensure there is proper consistency with the names of nodes/peers. We use both interchangeably, but this will be confusing. The same is true for "node id".
- [ ] Update OpenDoor to use this library

## Nice to have
- [ ] Remove the nodeId from the Event class.
- [ ] Migrate all node IDs to GossipPeerID
- [ ] Persist the node id with vector clocks to ensure causality is not accidentally broken by failing to store the node id with the clock vector.
- [ ] Support peers with different transport protocols.
- [ ] Implement a mechanism for authentication and authorization.
- [ ] Create Kotlin version of gossip library.
- [ ] Create gossip-flutter library for flutter utilities.
- [ ] Create a gossip-nearby library for quick nearby connections support.
- [ ] Turn typed events into proper Hive objects for faster storage performance.
- [ ] Document that you shouldn't use the actual user id as the peer node id. Use a unique identifier generated on the device instead. The persistent user id should be sent as part of the event data instead. Otherwise you will break causality when using multiple devices with the same user id, or when deleting app data on a peer and re-connecting.
- [ ] It might be good if we don't usually have to expose the node id to the application layer. It could be available as an optional feature, but the implementation should be carefully considered to avoid the application using the node id for persistent peer identification. Because node IDs identify the physical device, not the user.
