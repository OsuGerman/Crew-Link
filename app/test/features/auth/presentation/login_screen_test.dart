import 'package:crew_link/core/observability/crash_reporter.dart';
import 'package:crew_link/core/observability/observability_bootstrap.dart';
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
  bool appleSignInCalled = false;
  Object? appleSignInError;

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
  ) async =>
      _FakeCredential();

  @override
  Future<UserCredential> createUserWithEmailAndPassword(
    String email,
    String password,
  ) async =>
      _FakeCredential();

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

  group('LoginScreen', () {
    testWidgets('renders the Sign-in-with-Apple button', (tester) async {
      await tester.pumpWidget(_wrap(_FakeAuthRepo()));

      expect(find.byKey(const ValueKey('login-siwa')), findsOneWidget);
    });

    testWidgets('tapping the Apple button calls signInWithApple',
        (tester) async {
      final repo = _FakeAuthRepo();
      await tester.pumpWidget(_wrap(repo));

      await tester.tap(find.byKey(const ValueKey('login-siwa')));
      await tester.pump();

      expect(repo.appleSignInCalled, isTrue);
    });

    testWidgets('error message appears when Apple sign-in fails',
        (tester) async {
      final repo = _FakeAuthRepo()
        ..appleSignInError = Exception('apple-failed');
      await tester.pumpWidget(_wrap(repo));

      await tester.tap(find.byKey(const ValueKey('login-siwa')));
      await tester.pump(); // process the async rejection + errorMessage state
      await tester.pump(); // render the error widget

      expect(find.byKey(const ValueKey('login-error')), findsOneWidget);
      // login-error IS the Text holding the message, so assert its content
      // directly (find.descendant would look for a nested Text and find none).
      expect(find.textContaining('apple-failed'), findsOneWidget);
    });
  });
}
