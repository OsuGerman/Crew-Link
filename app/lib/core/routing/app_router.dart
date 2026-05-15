import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_providers.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/convoy/presentation/convoy_home_screen.dart';
import '../../features/convoy/presentation/deep_link_join_screen.dart';
import '../../features/legal/presentation/privacy_policy_screen.dart';
import '../../features/maps/presentation/convoy_map_screen.dart';
import '../../features/onboarding/application/onboarding_profile_notifier.dart';
import '../../features/onboarding/application/onboarding_state.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/vehicle/presentation/vehicle_profile_screen.dart';

abstract final class AppRoutes {
  static const String login = '/login';
  static const String home = '/';
  static const String onboarding = '/onboarding';
  static const String convoyMap = '/convoy/map';
  static const String vehicleProfile = '/vehicle/profile';
  static const String convoyJoin = '/join/:code';
  static const String privacy = '/privacy';

  static String convoyJoinPath(String code) => '/join/$code';
}

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    _subOnboarding = ref.listen<bool>(
      onboardingCompletedProvider,
      (_, __) => notifyListeners(),
    );
    // Also listen to raw auth state so the loading→resolved transition
    // triggers a re-evaluation even when onboardingCompletedProvider stays false.
    _subAuth = ref.listen<AsyncValue<User?>>(
      authStateProvider,
      (_, __) => notifyListeners(),
    );
    _subProfile = ref.listen<AsyncValue<OnboardingProfile>>(
      onboardingProfileProvider,
      (_, __) => notifyListeners(),
    );
  }

  late final ProviderSubscription<bool> _subOnboarding;
  late final ProviderSubscription<AsyncValue<User?>> _subAuth;
  late final ProviderSubscription<AsyncValue<OnboardingProfile>> _subProfile;

  @override
  void dispose() {
    _subOnboarding.close();
    _subAuth.close();
    _subProfile.close();
    super.dispose();
  }
}

void _handleDeepLinkUri(GoRouter router, Uri uri) {
  final segments = uri.pathSegments;
  if (segments.isEmpty) return;
  if (segments.first == 'join') {
    final code =
        segments.elementAtOrNull(1) ?? uri.queryParameters['code'];
    if (code != null && code.isNotEmpty) {
      router.go(AppRoutes.convoyJoinPath(code));
    }
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterRefreshNotifier(ref);
  final router = GoRouter(
    refreshListenable: notifier,
    redirect: (context, state) {
      // Don't redirect while auth or profile state is still loading to avoid
      // a flash of the login screen on cold-start for signed-in users.
      final authAsync = ref.read(authStateProvider);
      if (authAsync.isLoading) return null;

      final signedIn = authAsync.valueOrNull != null;
      final atLogin = state.matchedLocation == AppRoutes.login;

      if (!signedIn) {
        return atLogin ? null : AppRoutes.login;
      }

      // Signed-in path: resolve onboarding gate.
      final profileAsync = ref.read(onboardingProfileProvider);
      if (profileAsync.isLoading) return null;

      final onboarded = ref.read(onboardingCompletedProvider);
      final atOnboarding = state.matchedLocation == AppRoutes.onboarding;

      if (atLogin) return onboarded ? AppRoutes.home : AppRoutes.onboarding;
      if (!onboarded && !atOnboarding) return AppRoutes.onboarding;
      if (onboarded && atOnboarding) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => const ConvoyHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.convoyMap,
        builder: (_, __) => const ConvoyMapScreen(),
      ),
      GoRoute(
        path: AppRoutes.vehicleProfile,
        builder: (_, __) => const VehicleProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.convoyJoin,
        builder: (_, state) => DeepLinkJoinScreen(
          inviteCode: state.pathParameters['code']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.privacy,
        builder: (_, __) => const PrivacyPolicyScreen(),
      ),
    ],
  );

  if (!kIsWeb) {
    final appLinks = AppLinks();
    unawaited(
      appLinks.getInitialLink().then((uri) {
        if (uri != null) _handleDeepLinkUri(router, uri);
      }),
    );
    final sub = appLinks.uriLinkStream.listen((uri) {
      _handleDeepLinkUri(router, uri);
    });
    ref.onDispose(sub.cancel);
  }

  ref.onDispose(() {
    notifier.dispose();
    router.dispose();
  });
  return router;
});
