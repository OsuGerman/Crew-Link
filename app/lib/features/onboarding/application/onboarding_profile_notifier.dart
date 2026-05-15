import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
    state = AsyncValue.data(
      OnboardingProfile(displayName: displayName, completed: true),
    );
  }
}

final onboardingProfileProvider =
    AsyncNotifierProvider<OnboardingProfileNotifier, OnboardingProfile>(
  OnboardingProfileNotifier.new,
);
