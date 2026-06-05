import 'package:crew_link/core/observability/crash_reporter.dart';
import 'package:crew_link/core/observability/observability_bootstrap.dart';
import 'package:crew_link/features/auth/data/auth_repository.dart';
import 'package:crew_link/features/auth/presentation/login_screen.dart';
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
  bool appleSignInCalled = false;
  Object? appleSignInError;
  String? signedInEmail;
  String? signedUpEmail;

  @override
  Future<UserCredential> signInWithApple() async {
    appleSignInCalled = true;
    if (appleSignInError != null) throw appleSignInError!;
    return _FakeCredential();
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    signedInEmail = email;
    return _FakeCredential();
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword(
    String email,
    String password,
  ) async {
    signedUpEmail = email;
    return _FakeCredential();
  }

  @override
  Future<void> signOut() async {}
}

class _FakeCredential extends Fake implements UserCredential {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(_FakeAuthRepo repo) {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: LoginScreen()),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    ObservabilityBootstrap.build(overrideForTesting: const NullCrashReporter());
  });

  group('LoginScreen — Email/Passwort', () {
    testWidgets('renders email + password fields and submit button',
        (tester) async {
      await tester.pumpWidget(_wrap(_FakeAuthRepo()));

      expect(find.byKey(const ValueKey('login-email')), findsOneWidget);
      expect(find.byKey(const ValueKey('login-password')), findsOneWidget);
      expect(find.byKey(const ValueKey('login-submit')), findsOneWidget);
    });

    testWidgets('submitting calls signInWithEmailAndPassword in sign-in mode',
        (tester) async {
      final repo = _FakeAuthRepo();
      await tester.pumpWidget(_wrap(repo));

      await tester.enterText(
          find.byKey(const ValueKey('login-email')), 'rider@crew.de');
      await tester.enterText(
          find.byKey(const ValueKey('login-password')), 'secret123');
      await tester.ensureVisible(find.byKey(const ValueKey('login-submit')));
      await tester.tap(find.byKey(const ValueKey('login-submit')));
      await tester.pump();

      expect(repo.signedInEmail, 'rider@crew.de');
      expect(repo.signedUpEmail, isNull);
    });

    testWidgets('toggling to sign-up then submitting calls createUser...',
        (tester) async {
      final repo = _FakeAuthRepo();
      await tester.pumpWidget(_wrap(repo));

      await tester.ensureVisible(find.byKey(const ValueKey('login-toggle')));
      await tester.tap(find.byKey(const ValueKey('login-toggle')));
      await tester.pump();

      await tester.enterText(
          find.byKey(const ValueKey('login-email')), 'new@crew.de');
      await tester.enterText(
          find.byKey(const ValueKey('login-password')), 'secret123');
      await tester.ensureVisible(find.byKey(const ValueKey('login-submit')));
      await tester.tap(find.byKey(const ValueKey('login-submit')));
      await tester.pump();

      expect(repo.signedUpEmail, 'new@crew.de');
      expect(repo.signedInEmail, isNull);
    });
  });

  group('LoginScreen — Apple (Sekundär)', () {
    // The Apple button only renders on Apple platforms — pin the platform per
    // test, reset via addTearDown so the foundation-var invariant check (which
    // runs before group tearDown) passes.
    testWidgets('renders the Sign-in-with-Apple button', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(_wrap(_FakeAuthRepo()));

      expect(find.byKey(const ValueKey('login-siwa')), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('tapping the Apple button calls signInWithApple',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final repo = _FakeAuthRepo();
      await tester.pumpWidget(_wrap(repo));

      await tester.ensureVisible(find.byKey(const ValueKey('login-siwa')));
      await tester.tap(find.byKey(const ValueKey('login-siwa')));
      await tester.pump();

      expect(repo.appleSignInCalled, isTrue);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('error message appears when Apple sign-in fails',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final repo = _FakeAuthRepo()
        ..appleSignInError = Exception('apple-failed');
      await tester.pumpWidget(_wrap(repo));

      await tester.ensureVisible(find.byKey(const ValueKey('login-siwa')));
      await tester.tap(find.byKey(const ValueKey('login-siwa')));
      await tester.pump(); // process the async rejection + errorMessage state
      await tester.pump(); // render the error widget

      expect(find.byKey(const ValueKey('login-error')), findsOneWidget);
      expect(find.textContaining('apple-failed'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
