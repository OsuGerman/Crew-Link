import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/branding/crew_link_logo.dart';
import '../../../core/theme/app_theme.dart';

class OnboardingPage {
  const OnboardingPage({
    required this.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.primaryLabel,
  });
  final String key;
  final IconData icon;
  final String title;
  final String body;
  final String primaryLabel;
}

class OnboardingPageView extends StatelessWidget {
  const OnboardingPageView({required this.page, super.key});

  final OnboardingPage page;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey('onboarding-page-${page.key}'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _HeroLogo(),
          const SizedBox(height: AppSpacing.xl),
          Text(
            page.title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            page.body,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _HeroLogo extends StatelessWidget {
  const _HeroLogo();

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

/// Pillenförmiger Step-Indicator. Aktiver Dot orange + breit, inaktive
/// kleine graue Punkte. Animiert beim Wechsel.
class DotIndicator extends StatelessWidget {
  const DotIndicator({required this.count, required this.current, super.key});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == current ? 28 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == current
                  ? AppColors.orange
                  : AppColors.surfaceOutline,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

class SignInArea extends StatelessWidget {
  const SignInArea({
    required this.signing,
    required this.error,
    required this.onSignIn,
    super.key,
  });

  final bool signing;
  final String? error;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (error != null) ...[
          Text(
            error!,
            style: const TextStyle(
              color: AppColors.danger,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        SizedBox(
          width: double.infinity,
          height: 54,
          child: signing
              ? const Center(child: CircularProgressIndicator())
              : SignInWithAppleButton(
                  key: const ValueKey('onboarding-signin-apple'),
                  onPressed: onSignIn,
                  style: SignInWithAppleButtonStyle.white,
                  borderRadius: BorderRadius.circular(AppRadii.button),
                ),
        ),
      ],
    );
  }
}
