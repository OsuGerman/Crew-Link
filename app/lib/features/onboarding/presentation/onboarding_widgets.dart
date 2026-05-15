import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: ValueKey('onboarding-page-${page.key}'),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 116,
            height: 116,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              page.icon,
              size: 56,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 40),
          Text(
            page.title,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            page.body,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class DotIndicator extends StatelessWidget {
  const DotIndicator({required this.count, required this.current, super.key});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == current ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == current
                  ? scheme.primary
                  : scheme.onSurfaceVariant.withValues(alpha: 0.3),
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
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: double.infinity,
          height: 52,
          child: signing
              ? const Center(child: CircularProgressIndicator())
              : SignInWithAppleButton(
                  key: const ValueKey('onboarding-signin-apple'),
                  onPressed: onSignIn,
                ),
        ),
      ],
    );
  }
}
