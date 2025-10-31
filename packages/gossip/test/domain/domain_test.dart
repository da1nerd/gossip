/// Main test suite runner for all domain layer tests.
///
/// This file imports and runs all domain layer tests to provide
/// a comprehensive test suite for the domain logic.
library;

import 'entities/internal_gossip_peer_test.dart' as internal_gossip_peer_tests;
import 'services/peer_selection_service_test.dart'
    as peer_selection_service_tests;
import 'domain_integration_test.dart' as domain_integration_tests;

void main() {
  // Run all domain entity tests
  internal_gossip_peer_tests.main();

  // Run all domain service tests
  peer_selection_service_tests.main();

  // Run domain integration tests
  domain_integration_tests.main();
}
