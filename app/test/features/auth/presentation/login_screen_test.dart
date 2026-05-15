import 'package:crew_link/core/observability/crash_reporter.dart';
import 'package:crew_link/core/observability/observability_bootstrap.dart';
import 'package:crew_link/features/auth/application/auth_notifier.dart';
import 'package:crew_link/features/auth/application/auth_providers.dart';
import 'package:crew_link/features/auth/data/auth_repository.dart';
import 'package:crew_link/features/auth/presentation/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeAuthRepo implements AuthRepository {
  bool signInCalled = false;
  bool signUpCalled = false;
  Object? signInError;

  @override
  Future<UserCredential> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    signInCalled = true;
    if (signInError != null) throw signInError!;
    return _FakeCredential();
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword(
    String email,
    String password,
  ) async {
    signUpCalled = true;
    if (signInError != null) throw signInError!;
    return _FakeCredential();
  }

  @override
  Future<UserCredential> signInWithApple() async => _FakeCredential();

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
      authStateProvider.overrideWith((_) => Stream.value(null)),
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

  group('LoginScreen', () {
    testWidgets('renders email, password fields and Apple button', (tester) async {
      await tester.pumpWidget(_wrap(_FakeAuthRepo()));

      expect(find.byKey(const ValueKey('login-email')), findsOneWidget);
      expect(find.byKey(const ValueKey('login-password')), findsOneWidget);
      expect(find.byKey(const ValueKey('login-siwa')), findsOneWidget);
      expect(find.byKey(const ValueKey('login-submit')), findsOneWidget);
    });

    testWidgets('mode toggle switches between Anmelden and Registrieren',
        (tester) async {
      await tester.pumpWidget(_wrap(_FakeAuthRepo()));

      // Default is Anmelden
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('login-submit')),
          matching: find.text('Anmelden'),
        ),
        findsOneWidget,
      );

      // Tap Registrieren segment
      await tester.tap(find.text('Registrieren'));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('login-submit')),
          matching: find.text('Registrieren'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('submit in signIn mode calls signInWithEmailAndPassword',
        (tester) async {
      final repo = _FakeAuthRepo();
      await tester.pumpWidget(_wrap(repo));

      await tester.enterText(
          find.byKey(const ValueKey('login-email')), 'a@b.de');
      await tester.enterText(
          find.byKey(const ValueKey('login-password')), 'secret');
      await tester.tap(find.byKey(const ValueKey('login-submit')));
      await tester.pump();

      expect(repo.signInCalled, isTrue);
      expect(repo.signUpCalled, isFalse);
    });

    testWidgets('submit in signUp mode calls createUserWithEmailAndPassword',
        (tester) async {
      final repo = _FakeAuthRepo();
      await tester.pumpWidget(_wrap(repo));

      await tester.tap(find.text('Registrieren'));
      await tester.pump();

      await tester.enterText(
          find.byKey(const ValueKey('login-email')), 'a@b.de');
      await tester.enterText(
          find.byKey(const ValueKey('login-password')), 'secret');
      await tester.tap(find.byKey(const ValueKey('login-submit')));
      await tester.pump();

      expect(repo.signUpCalled, isTrue);
      expect(repo.signInCalled, isFalse);
    });

    testWidgets('error message appears when sign-in fails', (tester) async {
      final repo = _FakeAuthRepo()
        ..signInError = Exception('wrong-password');
      await tester.pumpWidget(_wrap(repo));

      await tester.enterText(
          find.byKey(const ValueKey('login-email')), 'a@b.de');
      await tester.enterText(
          find.byKey(const ValueKey('login-password')), 'wrong');
      await tester.tap(find.byKey(const ValueKey('login-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('login-error')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('login-error')),
          matching: find.textContaining('wrong-password'),
        ),
        findsOneWidget,
      );
    });
  });
}
