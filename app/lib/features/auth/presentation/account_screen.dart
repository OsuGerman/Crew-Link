import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/observability/app_logger.dart';
import '../../../core/observability/observability_bootstrap.dart';
import '../../../core/theme/app_theme.dart';
import '../../convoy/application/convoy_providers.dart';
import '../application/auth_providers.dart';

/// Account screen — shows the signed-in identity and the two destructive
/// actions: sign out and (GDPR / Play-required) permanent account deletion.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _busy = false;

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
        title: const Text('Konto löschen?'),
        content: const Text(
          'Dein Konto, dein Fahrzeug und die von dir erstellten Konvois werden '
          'unwiderruflich gelöscht. Mitfahrer landen wieder in der Lobby.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-account'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Endgültig löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final token = await ref.read(authIdTokenProvider.future) ?? '';
      await ref.read(convoyApiProvider).deleteAccount(authToken: token);
      // Server data is gone; now drop the Firebase account + local session.
      await ref.read(authNotifierProvider.notifier).deleteAccount();
      // authStateChanges emits null → the router redirects to /login.
      if (mounted) Navigator.of(context).pop();
    } catch (e, st) {
      appLog.e('AccountScreen.deleteAccount', error: e, stackTrace: st);
      unawaited(ObservabilityBootstrap.build().reportError(e, st));
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Löschen fehlgeschlagen. Bitte erneut versuchen.'),
          ),
        );
      }
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    await ref.read(authNotifierProvider.notifier).signOut();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(authStateProvider).valueOrNull?.email;
    return Scaffold(
      appBar: AppBar(title: const Text('Konto')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (email != null) ...[
                const Text('Angemeldet als', style: AppTextStyles.sectionLabel),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              OutlinedButton.icon(
                key: const ValueKey('sign-out-button'),
                onPressed: _busy ? null : _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Abmelden'),
              ),
              const Spacer(),
              const Text(
                'Konto löschen entfernt alle deine Daten (Profil, Fahrzeug, '
                'eigene Konvois) endgültig. Das lässt sich nicht rückgängig '
                'machen.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.icon(
                key: const ValueKey('delete-account-button'),
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: _busy ? null : _deleteAccount,
                icon: const Icon(Icons.delete_forever),
                label: const Text('Konto löschen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
