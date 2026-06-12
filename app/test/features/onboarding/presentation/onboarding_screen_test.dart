import 'package:crew_link/features/auth/application/auth_providers.dart';
import 'package:crew_link/features/auth/data/auth_repository.dart';
import 'package:crew_link/features/onboarding/application/onboarding_profile_notifier.dart';
import 'package:crew_link/features/onboarding/application/onboarding_state.dart';
import 'package:crew_link/features/onboarding/presentation/onboarding_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, TargetPlatform;
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

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> deleteAccount() async {}
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

    testWidgets('siwa step: continue button by default, Apple on iOS',
        (tester) async {
      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      // The siwa step wrapper Padding and the nested OnboardingPageView both
      // carry key 'onboarding-page-siwa' (ancestor + descendant).
      expect(find.byKey(const ValueKey('onboarding-page-siwa')), findsWidgets);
      // Default test platform (android) → continue button, no Apple button.
      expect(
          find.byKey(const ValueKey('onboarding-continue')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('onboarding-signin-apple')), findsNothing);

      // On Apple platforms the Apple sign-in button renders instead.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      expect(find.byKey(const ValueKey('onboarding-signin-apple')),
          findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('swipe left on the welcome step advances to profile',
        (tester) async {
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      await tester.fling(
          find.text('Willkommen bei Crew Link'), const Offset(-300, 0), 1000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('onboarding-profile-name')),
          findsOneWidget);
    });

    testWidgets('swipe right on the profile step goes back to welcome',
        (tester) async {
      await tester.pumpWidget(_wrap(container, initialStep: 1));
      await tester.pump();

      await tester.fling(find.byKey(const ValueKey('onboarding-page-profile')),
          const Offset(300, 0), 1000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('onboarding-continue')), findsOneWidget);
    });

    testWidgets('calm drag (no fling) on welcome step still advances',
        (tester) async {
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      // A plain drag has near-zero release velocity — it must trigger on the
      // accumulated horizontal distance alone, not just on a fast fling.
      await tester.drag(
          find.text('Willkommen bei Crew Link'), const Offset(-150, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('onboarding-profile-name')),
          findsOneWidget);
    });

    testWidgets('calm drag right on profile step goes back to welcome',
        (tester) async {
      await tester.pumpWidget(_wrap(container, initialStep: 1));
      await tester.pump();

      await tester.drag(
          find.byKey(const ValueKey('onboarding-page-profile')),
          const Offset(150, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('onboarding-continue')), findsOneWidget);
    });

    testWidgets('tiny drag below the distance threshold does not advance',
        (tester) async {
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      // 30px < 60px threshold and no fling → stay on the welcome step.
      await tester.drag(
          find.text('Willkommen bei Crew Link'), const Offset(-30, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
          find.byKey(const ValueKey('onboarding-continue')), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-profile-name')),
          findsNothing);
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

    testWidgets('cta step shows the create button', (tester) async {
      await tester.pumpWidget(_wrap(container, initialStep: 2));
      await tester.pump();
      expect(find.byKey(const ValueKey('onboarding-page-cta')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('onboarding-cta-create')), findsOneWidget);
    });

    testWidgets('cta create button saves profile and marks onboarding completed',
        (tester) async {
      await tester.pumpWidget(_wrap(container, initialStep: 2));
      await tester.pump();
      // Warm up the profile provider so its async build() resolves BEFORE the
      // tap; otherwise the still-pending build() future overwrites the
      // completed=true state that save() sets synchronously inside _complete.
      await container.read(onboardingProfileProvider.future);
      await tester.tap(find.byKey(const ValueKey('onboarding-cta-create')));
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
