import 'package:crew_link/features/auth/application/auth_providers.dart';
import 'package:crew_link/features/auth/data/auth_repository.dart';
import 'package:crew_link/features/onboarding/application/onboarding_profile_notifier.dart';
import 'package:crew_link/features/onboarding/application/onboarding_state.dart';
import 'package:crew_link/features/onboarding/presentation/onboarding_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeAuthRepo implements AuthRepository {
  @override
  Future<UserCredential> signInWithApple() async {
    throw UnsupportedError('Apple Sign-In not available in unit tests');
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    throw UnsupportedError('Email sign-in not available in unit tests');
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword(
    String email,
    String password,
  ) async {
    throw UnsupportedError('Email sign-up not available in unit tests');
  }

  @override
  Future<void> signOut() async {}
}

class _FakeProfileNotifier extends OnboardingProfileNotifier {
  @override
  Future<OnboardingProfile> build() async =>
      const OnboardingProfile(displayName: '', completed: false);

  @override
  Future<void> save(String displayName) async {
    state = AsyncValue.data(
      OnboardingProfile(displayName: displayName, completed: true),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ProviderContainer _buildContainer() => ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((_) => Stream.value(null)),
        authRepositoryProvider.overrideWithValue(_FakeAuthRepo()),
        onboardingProfileProvider.overrideWith(_FakeProfileNotifier.new),
      ],
    );

Widget _wrap(
  ProviderContainer container, {
  int initialStep = 0,
}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: OnboardingScreen(debugInitialStep: initialStep),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('OnboardingScreen', () {
    late ProviderContainer container;

    setUp(() => container = _buildContainer());
    tearDown(() => container.dispose());

    testWidgets('starts on siwa step with Apple Sign-In button', (tester) async {
      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      expect(find.byKey(const ValueKey('onboarding-page-siwa')), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-signin-apple')), findsOneWidget);
    });

    testWidgets('profile step shows name field and Weiter disabled when empty',
        (tester) async {
      await tester.pumpWidget(_wrap(container, initialStep: 1));
      await tester.pump();
      expect(
          find.byKey(const ValueKey('onboarding-page-profile')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('onboarding-profile-name')), findsOneWidget);
      final btn = tester.widget<FilledButton>(
          find.byKey(const ValueKey('onboarding-profile-next')));
      expect(btn.onPressed, isNull);
    });

    testWidgets('profile Weiter enabled after entering name and advances to cta',
        (tester) async {
      await tester.pumpWidget(_wrap(container, initialStep: 1));
      await tester.pump();
      await tester.enterText(
          find.byKey(const ValueKey('onboarding-profile-name')), 'Alex');
      await tester.pump();
      final btn = tester.widget<FilledButton>(
          find.byKey(const ValueKey('onboarding-profile-next')));
      expect(btn.onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('onboarding-profile-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('onboarding-page-cta')), findsOneWidget);
    });

    testWidgets('cta step shows create and join buttons', (tester) async {
      await tester.pumpWidget(_wrap(container, initialStep: 2));
      await tester.pump();
      expect(find.byKey(const ValueKey('onboarding-page-cta')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('onboarding-cta-create')), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-cta-join')), findsOneWidget);
    });

    testWidgets('cta create button saves profile and marks onboarding completed',
        (tester) async {
      await tester.pumpWidget(_wrap(container, initialStep: 2));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('onboarding-cta-create')));
      await tester.pump();
      final profile = await container.read(onboardingProfileProvider.future);
      expect(profile.completed, isTrue);
    });

    testWidgets('cta join button also completes onboarding', (tester) async {
      await tester.pumpWidget(_wrap(container, initialStep: 2));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('onboarding-cta-join')));
      await tester.pump();
      final profile = await container.read(onboardingProfileProvider.future);
      expect(profile.completed, isTrue);
    });

    testWidgets('skip button sets dev-skip provider', (tester) async {
      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
      await tester.pump();
      expect(container.read(onboardingDevSkipProvider), isTrue);
    });

    testWidgets('skip button is non-interactive on cta step', (tester) async {
      await tester.pumpWidget(_wrap(container, initialStep: 2));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('onboarding-skip')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(container.read(onboardingDevSkipProvider), isFalse);
    });
  });

  group('onboardingCompletedProvider', () {
    test('false when not signed in and dev-skip not set', () {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((_) => Stream.value(null)),
          onboardingProfileProvider.overrideWith(_FakeProfileNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(onboardingCompletedProvider), isFalse);
    });

    test('true when dev-skip is set', () {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((_) => Stream.value(null)),
          onboardingProfileProvider.overrideWith(_FakeProfileNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      container.read(onboardingDevSkipProvider.notifier).state = true;
      expect(container.read(onboardingCompletedProvider), isTrue);
    });
  });
}
