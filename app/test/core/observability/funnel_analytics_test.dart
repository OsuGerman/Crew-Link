import 'package:crew_link/core/observability/funnel_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FunnelAnalytics', () {
    // POSTHOG_API_KEY is not set in tests → all methods are no-ops.

    test('init() completes without throwing when key is empty', () async {
      await expectLater(FunnelAnalytics.init(), completes);
    });

    test('onboardingStarted() no-ops without throwing', () async {
      await expectLater(FunnelAnalytics.onboardingStarted(), completes);
    });

    test('pageViewed() no-ops without throwing', () async {
      await expectLater(FunnelAnalytics.pageViewed('welcome'), completes);
    });

    test('appleSignInTapped() no-ops without throwing', () async {
      await expectLater(FunnelAnalytics.appleSignInTapped(), completes);
    });

    test('appleSignInSuccess() no-ops without throwing', () async {
      await expectLater(FunnelAnalytics.appleSignInSuccess(), completes);
    });

    test('appleSignInFailed() no-ops without throwing', () async {
      await expectLater(
        FunnelAnalytics.appleSignInFailed('some_error'),
        completes,
      );
    });

    test('onboardingCompleted() no-ops without throwing', () async {
      await expectLater(FunnelAnalytics.onboardingCompleted(), completes);
    });

    test('identify() no-ops without throwing', () async {
      await expectLater(FunnelAnalytics.identify('user-123'), completes);
    });
  });
}
