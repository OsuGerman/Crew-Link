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

  // Capture is OFF until [init] runs (only with diagnostics consent). Events
  // must never fire before consent — e.g. during onboarding, which precedes
  // the consent gate. [_setupDone] guards against calling PostHog setup twice.
  static bool _enabled = false;
  static bool _setupDone = false;

  /// Sets up PostHog and enables capture. Call only with diagnostics consent.
  /// Idempotent — safe to call again on a runtime opt-in.
  static Future<void> init() async {
    if (_apiKey.isEmpty) return;
    if (!_setupDone) {
      try {
        final config = PostHogConfig(_apiKey)..host = _host;
        await Posthog().setup(config);
        _setupDone = true;
      } catch (e) {
        appLog.w('PostHog init failed', error: e);
        return;
      }
    }
    _enabled = true;
  }

  /// Stops capturing — runtime consent withdrawal.
  static void disable() {
    _enabled = false;
  }

  static Future<void> _capture(
    String event, {
    Map<String, Object>? properties,
  }) async {
    if (!_enabled) return;
    try {
      await Posthog().capture(eventName: event, properties: properties);
    } catch (e) {
      appLog.w('PostHog capture failed ($event)', error: e);
    }
  }

  static Future<void> identify(String userId) async {
    if (!_enabled) return;
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
