import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:crew_link/core/branding/crew_link_logo.dart';
import 'package:crew_link/core/branding/crew_link_wordmark.dart';
import 'package:crew_link/core/theme/app_theme.dart';
import 'package:crew_link/features/auth/application/auth_notifier.dart';
import 'package:crew_link/features/onboarding/presentation/onboarding_widgets.dart';

/// Welcome-Screen (Design.pdf Frame 1) — Apple-only Sign-In.
/// Email/Passwort wurde entfernt: das Spec-Design verlangt einen reduzierten
/// First-Tap-Flow ("Sign in with Apple" als CTA). Der Router schickt nach
/// erfolgreichem Auth automatisch in den Onboarding-Flow.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  static const routePath = '/login';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.isLoading;
    final errorMessage = authState.errorMessage;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(child: _HeroLogo()),
              const SizedBox(height: AppSpacing.xl),
              const Center(child: CrewLinkWordmark(fontSize: 34)),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Koordiniere deinen Konvoi live. Sieh, wo dein\n'
                'Kreis fährt, sprich mit allen mit einem Tap.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              if (errorMessage != null) ...[
                Text(
                  errorMessage,
                  key: const ValueKey('login-error'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              SizedBox(
                height: 54,
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SignInWithAppleButton(
                        key: const ValueKey('login-siwa'),
                        onPressed: () => ref
                            .read(authNotifierProvider.notifier)
                            .signInWithApple(),
                        style: SignInWithAppleButtonStyle.white,
                        borderRadius:
                            BorderRadius.circular(AppRadii.button),
                      ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.xl),
                child: DotIndicator(count: 3, current: 0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      height: 132,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.orange.withValues(alpha: 0.22),
            blurRadius: 60,
            spreadRadius: 6,
          ),
        ],
      ),
      child: const CrewLinkLogo(size: 96),
    );
  }
}
