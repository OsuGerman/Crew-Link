import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/observability/app_logger.dart';
import '../../../core/observability/observability_bootstrap.dart';

class OnboardingProfile {
  const OnboardingProfile({
    required this.displayName,
    required this.completed,
  });
  final String displayName;
  final bool completed;
}

class OnboardingProfileNotifier extends AsyncNotifier<OnboardingProfile> {
  static const _keyName = 'onboarding.profile.displayName';
  static const _keyDone = 'onboarding.profile.completed';

  @override
  Future<OnboardingProfile> build() async {
    const storage = FlutterSecureStorage();
    final name = await storage.read(key: _keyName) ?? '';
    final done = await storage.read(key: _keyDone) == 'true';
    return OnboardingProfile(displayName: name, completed: done);
  }

  Future<void> save(String displayName) async {
    const storage = FlutterSecureStorage();
    await storage.write(key: _keyName, value: displayName);
    await storage.write(key: _keyDone, value: 'true');
    // Propagate the name to the Firebase profile + force-refresh the ID token,
    // so the backend (which derives the convoy member name from the token's
    // name claim) shows it instead of the email local part. Best-effort —
    // never block onboarding if the profile write or refresh fails.
    try {
      final user = ref.read(firebaseAuthProvider).currentUser;
      if (user != null) {
        await user.updateDisplayName(displayName);
        await user.getIdToken(true);
      }
    } catch (e, st) {
      appLog.e('OnboardingProfile.updateDisplayName', error: e, stackTrace: st);
      try {
        await ObservabilityBootstrap.build().reportError(e, st);
      } catch (_) {
        // Reporter may be unavailable (e.g. test without Firebase).
      }
    }
    state = AsyncValue.data(
      OnboardingProfile(displayName: displayName, completed: true),
    );
  }
}

final onboardingProfileProvider =
    AsyncNotifierProvider<OnboardingProfileNotifier, OnboardingProfile>(
  OnboardingProfileNotifier.new,
);
