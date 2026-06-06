import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/privacy/diagnostics_consent_providers.dart';
import 'privacy_policy_screen.dart';

/// One-time GDPR opt-in gate shown after onboarding. Both choices are equally
/// reachable (no dark pattern); declining collects nothing and the app stays
/// fully functional. The router sends the user on once a choice is recorded.
class DiagnosticsConsentScreen extends ConsumerStatefulWidget {
  const DiagnosticsConsentScreen({super.key});

  @override
  ConsumerState<DiagnosticsConsentScreen> createState() =>
      _DiagnosticsConsentScreenState();
}

class _DiagnosticsConsentScreenState
    extends ConsumerState<DiagnosticsConsentScreen> {
  bool _busy = false;

  Future<void> _decide(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    await ref.read(diagnosticsConsentProvider.notifier).decide(enabled);
    // The router redirect re-evaluates once `decided` flips and routes home —
    // no manual navigation here.
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 24),
                      Icon(Icons.insights_rounded,
                          size: 64, color: scheme.primary),
                      const SizedBox(height: 24),
                      Text(
                        'Diagnose & Verbesserung',
                        style: textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Mit deiner Erlaubnis erfassen wir pseudonyme '
                        'Diagnose-Daten, um Fehler zu finden und Crew Link zu '
                        'verbessern:\n\n'
                        '•  Genutzte Funktionen + Sitzungsdauer '
                        '(Firebase Analytics, PostHog)\n'
                        '•  Absturz- und Fehlerberichte inkl. Stacktrace '
                        '(Crashlytics, Sentry)\n\n'
                        'Ohne Werbe-IDs, ohne app-übergreifendes Tracking. '
                        'Verarbeitung durch Google, Sentry und PostHog '
                        '(USA/EU, EU-Standardvertragsklauseln).\n\n'
                        'Ohne Zustimmung werden keine Diagnose-Daten erhoben — '
                        'die App funktioniert voll. Du kannst die Wahl '
                        'jederzeit unter „Datenschutz" ändern.',
                        style: textTheme.bodyMedium?.copyWith(height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PrivacyPolicyScreen(),
                          ),
                        ),
                        child: const Text('Datenschutzerklärung lesen'),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              FilledButton(
                key: const ValueKey('consent-accept'),
                onPressed: _busy ? null : () => _decide(true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Text('Zustimmen'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const ValueKey('consent-decline'),
                onPressed: _busy ? null : () => _decide(false),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Ablehnen — nur das Nötigste'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
