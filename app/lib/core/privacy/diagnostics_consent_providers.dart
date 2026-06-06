import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'diagnostics_consent.dart';

/// Exposes the stored diagnostics consent to the UI and lets the user change it.
class DiagnosticsConsentNotifier extends AsyncNotifier<DiagnosticsConsent> {
  @override
  Future<DiagnosticsConsent> build() => DiagnosticsConsent.load();

  /// Records the user's choice, persists it, and applies it to the SDKs at
  /// runtime (Firebase Analytics + Crashlytics; PostHog + Sentry follow on the
  /// next launch).
  Future<void> decide(bool enabled) async {
    await DiagnosticsConsent.persist(enabled);
    await applyDiagnosticsConsent(enabled);
    state = AsyncValue.data(
      DiagnosticsConsent(decided: true, enabled: enabled),
    );
  }
}

final diagnosticsConsentProvider =
    AsyncNotifierProvider<DiagnosticsConsentNotifier, DiagnosticsConsent>(
  DiagnosticsConsentNotifier.new,
);
