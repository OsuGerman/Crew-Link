import 'package:posthog_flutter/posthog_flutter.dart';

import 'app_logger.dart';

/// Thin wrapper around PostHog for onboarding funnel events.
/// No-ops when [_apiKey] is empty (dev / test).
class FunnelAnalytics {
  FunnelAnalytics._();

  static const _apiKey =
      String.fromEnvironment('POSTHOG_API_KEY', defaultValue: '');
  static const _host = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://eu.i.posthog.com',
  );

  static Future<void> init() async {
    if (_apiKey.isEmpty) return;
    try {
      final config = PostHogConfig(_apiKey)..host = _host;
      await Posthog().setup(config);
    } catch (e) {
      appLog.w('PostHog init failed', error: e);
    }
  }

  static Future<void> _capture(
    String event, {
    Map<String, Object>? properties,
  }) async {
    if (_apiKey.isEmpty) return;
    try {
      await Posthog().capture(eventName: event, properties: properties);
    } catch (e) {
      appLog.w('PostHog capture failed ($event)', error: e);
    }
  }

  static Future<void> identify(String userId) async {
    if (_apiKey.isEmpty) return;
    try {
      await Posthog().identify(userId: userId);
    } catch (e) {
      appLog.w('PostHog identify failed', error: e);
    }
  }

  static Future<void> onboardingStarted() =>
      _capture('onboarding_started');

  static Future<void> pageViewed(String pageName) =>
      _capture('onboarding_page_viewed', properties: {'page': pageName});

  static Future<void> appleSignInTapped() => _capture('apple_signin_tapped');

  static Future<void> appleSignInSuccess() =>
      _capture('apple_signin_success');

  static Future<void> appleSignInFailed(String error) =>
      _capture('apple_signin_failed', properties: {'error': error});

  static Future<void> onboardingCompleted() =>
      _capture('onboarding_completed');
}
