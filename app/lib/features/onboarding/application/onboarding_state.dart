import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import 'onboarding_profile_notifier.dart';

/// Dev-only: allows bypassing Apple Sign-In during local development.
/// The router treats this the same as being authenticated.
final onboardingDevSkipProvider = StateProvider<bool>((ref) => false);

/// `true` once the user has authenticated AND saved their profile stub,
/// or (in dev mode) explicitly skipped sign-in.
///
/// `signedIn` honors auch den [devSignedInOverrideProvider] — sonst landet
/// die Web-Preview nach dem Profile-Save in einer Loop, weil
/// `authStateProvider` keinen echten Firebase-User hat.
final onboardingCompletedProvider = Provider<bool>((ref) {
  final signedIn = ref.watch(authStateProvider).valueOrNull != null ||
      ref.watch(devSignedInOverrideProvider);
  final devSkipped = ref.watch(onboardingDevSkipProvider);
  final profileCompleted =
      ref.watch(onboardingProfileProvider).valueOrNull?.completed ?? false;
  return devSkipped || (signedIn && profileCompleted);
});
