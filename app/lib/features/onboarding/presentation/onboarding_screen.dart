import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/observability/app_logger.dart';
import '../../../core/observability/funnel_analytics.dart';
import '../../../core/observability/observability_bootstrap.dart';
import '../../auth/data/auth_repository.dart';
import '../application/onboarding_profile_notifier.dart';
import '../application/onboarding_state.dart';
import 'onboarding_widgets.dart';

part 'onboarding_screen_steps.dart';

const _siwaPage = OnboardingPage(
  key: 'siwa',
  icon: Icons.route,
  title: 'Willkommen bei Crew Link',
  body: 'Koordiniere deinen Konvoi live. Sieh, wo dein Kreis fährt, '
      'sprich mit allen mit einem Tap.',
  primaryLabel: '',
);

const _ctaPage = OnboardingPage(
  key: 'convoy-cta',
  icon: Icons.group,
  title: 'Bereit für deinen ersten Konvoi?',
  body: 'Erstelle einen neuen Konvoi oder tritt einem bestehenden bei.',
  primaryLabel: '',
);

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.debugInitialStep = 0});

  /// For widget tests only — skips directly to a given step (0, 1 or 2).
  final int debugInitialStep;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late int _step;
  bool _signing = false;
  String? _signingError;
  bool _completing = false;
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _step = widget.debugInitialStep;
    _nameController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FunnelAnalytics.onboardingStarted();
      FunnelAnalytics.pageViewed(_pageKey(_step));
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  static String _pageKey(int step) => switch (step) {
        0 => 'siwa',
        1 => 'profile',
        _ => 'convoy-cta',
      };

  void _skip() {
    FunnelAnalytics.onboardingCompleted();
    ref.read(onboardingDevSkipProvider.notifier).state = true;
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _signing = true;
      _signingError = null;
    });
    await FunnelAnalytics.appleSignInTapped();
    try {
      final result = await ref.read(authRepositoryProvider).signInWithApple();
      final uid = result.user?.uid;
      if (uid != null) await FunnelAnalytics.identify(uid);
      await FunnelAnalytics.appleSignInSuccess();
      if (mounted) {
        setState(() {
          _signing = false;
          _step = 1;
        });
        unawaited(FunnelAnalytics.pageViewed('profile'));
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        setState(() => _signing = false);
        return;
      }
      appLog.e('Apple Sign-In authorization error', error: e);
      await ObservabilityBootstrap.build().reportError(e, StackTrace.current);
      await FunnelAnalytics.appleSignInFailed(e.code.name);
      setState(() {
        _signing = false;
        _signingError = 'Anmeldung fehlgeschlagen. Bitte erneut versuchen.';
      });
    } catch (e, st) {
      appLog.e('Apple Sign-In unexpected error', error: e, stackTrace: st);
      await ObservabilityBootstrap.build().reportError(e, st);
      await FunnelAnalytics.appleSignInFailed(e.toString());
      setState(() {
        _signing = false;
        _signingError = 'Anmeldung fehlgeschlagen. Bitte erneut versuchen.';
      });
    }
  }

  void _advanceToCta() {
    setState(() => _step = 2);
    unawaited(FunnelAnalytics.pageViewed('convoy-cta'));
  }

  Future<void> _complete() async {
    setState(() => _completing = true);
    try {
      await ref
          .read(onboardingProfileProvider.notifier)
          .save(_nameController.text.trim());
      await FunnelAnalytics.onboardingCompleted();
    } catch (e, st) {
      appLog.e('Profil speichern fehlgeschlagen', error: e, stackTrace: st);
      await ObservabilityBootstrap.build().reportError(e, st);
      if (mounted) setState(() => _completing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: AnimatedOpacity(
                opacity: _step < 2 ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: _step >= 2,
                  child: TextButton(
                    key: const ValueKey('onboarding-skip'),
                    onPressed: _skip,
                    child: const Text('Überspringen'),
                  ),
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: switch (_step) {
                    0 => _buildSiwaStep(),
                    1 => _buildProfileStep(),
                    _ => _buildConvoyCtaStep(),
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: DotIndicator(count: 3, current: _step),
            ),
          ],
        ),
      ),
    );
  }

}

