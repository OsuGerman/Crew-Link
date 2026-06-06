import 'package:crew_link/core/privacy/diagnostics_consent.dart';
import 'package:crew_link/core/privacy/diagnostics_consent_providers.dart';
import 'package:crew_link/features/legal/presentation/diagnostics_consent_screen.dart';
import 'package:crew_link/features/legal/presentation/privacy_policy_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures decisions without touching secure storage or the Firebase SDKs.
class _FakeConsentNotifier extends DiagnosticsConsentNotifier {
  _FakeConsentNotifier({this.initialDecided = false});

  final bool initialDecided;
  final List<bool> decisions = [];

  @override
  Future<DiagnosticsConsent> build() async =>
      DiagnosticsConsent(decided: initialDecided, enabled: false);

  @override
  Future<void> decide(bool enabled) async {
    decisions.add(enabled);
    state =
        AsyncValue.data(DiagnosticsConsent(decided: true, enabled: enabled));
  }
}

Widget _wrap(Widget child, _FakeConsentNotifier fake) => ProviderScope(
      overrides: [diagnosticsConsentProvider.overrideWith(() => fake)],
      child: MaterialApp(home: child),
    );

void main() {
  group('DiagnosticsConsentScreen', () {
    testWidgets('accepting records an opt-in', (tester) async {
      final fake = _FakeConsentNotifier();
      await tester.pumpWidget(_wrap(const DiagnosticsConsentScreen(), fake));
      await tester.tap(find.byKey(const ValueKey('consent-accept')));
      await tester.pump();
      expect(fake.decisions, [true]);
    });

    testWidgets('declining records an opt-out', (tester) async {
      final fake = _FakeConsentNotifier();
      await tester.pumpWidget(_wrap(const DiagnosticsConsentScreen(), fake));
      await tester.tap(find.byKey(const ValueKey('consent-decline')));
      await tester.pump();
      expect(fake.decisions, [false]);
    });
  });

  group('Privacy diagnostics toggle', () {
    testWidgets('reflects current consent and flips it on tap',
        (tester) async {
      final fake = _FakeConsentNotifier(initialDecided: true);
      await tester.pumpWidget(_wrap(const PrivacyPolicyScreen(), fake));
      await tester.pumpAndSettle();

      final toggle = find.byKey(const ValueKey('diagnostics-consent-toggle'));
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

      await tester.tap(toggle);
      await tester.pump();
      expect(fake.decisions, [true]);
    });
  });
}
