import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../observability/app_logger.dart';

/// The user's choice about analytics + crash diagnostics. GDPR opt-in: until
/// the user [decided], collection stays OFF ([enabled] == false). Persisted in
/// the platform keychain/keystore via FlutterSecureStorage.
class DiagnosticsConsent {
  const DiagnosticsConsent({required this.decided, required this.enabled});

  /// Whether the user has made an explicit choice yet.
  final bool decided;

  /// Whether analytics (Firebase Analytics, PostHog) + crash reporting
  /// (Crashlytics, Sentry) are allowed to collect data.
  final bool enabled;

  static const _key = 'privacy.diagnostics_consent';

  /// Loads the stored choice. Unset → undecided + disabled (privacy-first).
  static Future<DiagnosticsConsent> load() async {
    const storage = FlutterSecureStorage();
    final value = await storage.read(key: _key);
    return DiagnosticsConsent(decided: value != null, enabled: value == 'true');
  }

  /// Persists an explicit choice.
  static Future<void> persist(bool enabled) async {
    const storage = FlutterSecureStorage();
    await storage.write(key: _key, value: enabled ? 'true' : 'false');
  }
}

/// Applies the consent to the SDKs that support a runtime collection toggle
/// (Firebase Analytics + Crashlytics), so opting in/out takes effect without a
/// restart. PostHog + Sentry are gated at launch in `main()`; their state
/// follows on the next start. No-op on web / without Firebase. Best-effort —
/// never throws into the caller.
Future<void> applyDiagnosticsConsent(bool enabled) async {
  if (kIsWeb) return;
  try {
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(enabled);
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(enabled);
  } catch (e, st) {
    appLog.e('applyDiagnosticsConsent', error: e, stackTrace: st);
  }
}
