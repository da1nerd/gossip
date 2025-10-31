/// Test configuration and setup for the gossip package tests.
///
/// This file contains common test configuration, setup utilities,
/// and global test settings used across all test suites.
library;

import 'package:test/test.dart';

/// Global test configuration settings.
class TestConfig {
  /// Default timeout for tests that might take longer due to async operations.
  static const Duration defaultTimeout = Duration(seconds: 30);

  /// Timeout for performance/benchmark tests.
  static const Duration performanceTimeout = Duration(minutes: 2);

  /// Maximum allowed execution time for single operations in performance tests.
  static const Duration maxOperationTime = Duration(milliseconds: 100);

  /// Number of iterations for stress tests (stability/reliability testing).
  static const int stressTestIterations = 1000;

  /// Number of iterations for statistical tests (randomness, distribution validation).
  /// Higher count needed for statistical significance.
  static const int statisticalTestIterations = 10000;

  /// Tolerance for floating-point comparisons in tests.
  static const double floatingPointTolerance = 0.001;

  /// Random seed for reproducible tests.
  static const int testRandomSeed = 42;

  /// Test data sizes for scalability tests.
  static const List<int> scalabilityTestSizes = [10, 100, 500, 1000];
}

/// Sets up common test environment configuration.
void setupTestEnvironment() {
  // Configure test timeouts
  setUp(() {
    // Any common setup that needs to run before each test
  });

  tearDown(() {
    // Any common cleanup that needs to run after each test
  });
}

/// Custom matchers for domain-specific assertions.
class GossipMatchers {
  /// Matcher for validating reliability scores are within valid bounds.
  static Matcher isValidReliabilityScore() {
    return allOf([
      isA<double>(),
      greaterThanOrEqualTo(0.0),
      lessThanOrEqualTo(1.0),
    ]);
  }

  /// Matcher for validating success rates are within valid bounds.
  static Matcher isValidSuccessRate() {
    return allOf([
      isA<double>(),
      greaterThanOrEqualTo(0.0),
      lessThanOrEqualTo(1.0),
    ]);
  }

  /// Matcher for checking if a value is within a percentage tolerance.
  static Matcher isWithinPercentageOf(
    double expected,
    double percentTolerance,
  ) {
    final tolerance = expected * (percentTolerance / 100.0);
    return closeTo(expected, tolerance);
  }

  /// Matcher for validating that a list has no duplicates.
  static Matcher hasNoDuplicates() {
    return predicate<List>((list) {
      final seen = <dynamic>{};
      for (final item in list) {
        if (seen.contains(item)) {
          return false;
        }
        seen.add(item);
      }
      return true;
    }, 'has no duplicates');
  }

  /// Matcher for checking that a list is sorted by a specific property.
  static Matcher isSortedBy<T>(
    Comparable Function(T) keyExtractor, {
    bool descending = false,
  }) {
    return predicate<List<T>>(
      (list) {
        if (list.length <= 1) return true;

        for (int i = 0; i < list.length - 1; i++) {
          final current = keyExtractor(list[i]);
          final next = keyExtractor(list[i + 1]);

          final comparison = current.compareTo(next);
          if (descending) {
            if (comparison < 0) return false;
          } else {
            if (comparison > 0) return false;
          }
        }
        return true;
      },
      'is sorted by key function ${descending ? '(descending)' : '(ascending)'}',
    );
  }
}

/// Test group helper for organizing related tests.
void testGroup(String description, void Function() body) {
  group(description, () {
    setupTestEnvironment();
    body();
  });
}

/// Performance test helper that validates execution time.
void performanceTest(
  String description,
  void Function() testBody, {
  Duration? maxDuration,
}) {
  test(description, () {
    final stopwatch = Stopwatch()..start();
    testBody();
    stopwatch.stop();

    final maxTime = maxDuration ?? TestConfig.maxOperationTime;
    expect(
      stopwatch.elapsed,
      lessThan(maxTime),
      reason:
          'Test should complete within $maxTime but took ${stopwatch.elapsed}',
    );
  }, timeout: Timeout(TestConfig.performanceTimeout));
}

/// Stress test helper that runs a test multiple times to verify stability.
///
/// Stress tests focus on system stability under repeated operations,
/// checking for memory leaks, state corruption, or performance degradation.
/// Each iteration should be independent and test the same operation.
///
/// Example usage:
///
/// Stress test - runs same operation repeatedly to check for stability:
/// ```dart
/// stressTest(
///   'peer state remains consistent under repeated updates',
///   (iteration) {
///     peer.recordSuccessfulContact();
///     peer.recordFailedContact();
///     expect(peer.reliabilityScore, isValidReliabilityScore());
///   },
/// );
/// ```
void stressTest(
  String description,
  void Function(int iteration) testBody, {
  int? iterations,
}) {
  test(description, () {
    final testIterations = iterations ?? TestConfig.stressTestIterations;

    for (int i = 0; i < testIterations; i++) {
      testBody(i);
    }
  }, timeout: Timeout(TestConfig.performanceTimeout));
}

/// Statistical test helper for validating randomness and distribution.
///
/// Statistical tests run many iterations to collect data and validate
/// probabilistic behavior, checking for proper distribution, fairness,
/// and statistical properties. Results are aggregated for analysis.
///
/// Example usage:
///
/// Statistical test - collects data to validate probabilistic behavior:
/// ```dart
/// statisticalTest(
///   'random selection distributes fairly',
///   (iteration) {
///     final selected = service.selectPeers();
///     return {'selected': selected.map((p) => p.id).toList()};
///   },
///   validator: (results) {
///     // Validate distribution fairness across all iterations
///     final allSelections = results['selected']!;
///     // ... statistical analysis ...
///   },
/// );
/// ```
void statisticalTest(
  String description,
  Map<String, dynamic> Function(int iteration) testBody, {
  int? iterations,
  void Function(Map<String, List<dynamic>>)? validator,
}) {
  test(description, () {
    final testIterations = iterations ?? TestConfig.statisticalTestIterations;
    final results = <String, List<dynamic>>{};

    // Collect results from all iterations
    for (int i = 0; i < testIterations; i++) {
      final iterationResults = testBody(i);
      for (final entry in iterationResults.entries) {
        results.putIfAbsent(entry.key, () => []).add(entry.value);
      }
    }

    // Apply statistical validation if provided
    if (validator != null) {
      validator(results);
    }
  }, timeout: Timeout(TestConfig.performanceTimeout));
}
