import 'package:crew_link/core/observability/crash_reporter.dart';
import 'package:crew_link/core/observability/observability_bootstrap.dart';
import 'package:crew_link/features/auth/application/auth_error_messages.dart';
import 'package:crew_link/features/auth/application/auth_notifier.dart';
import 'package:crew_link/features/auth/data/auth_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class FakeAuthRepository implements AuthRepository {
  bool signInWithEmailCalled = false;
  bool signUpWithEmailCalled = false;
  bool signInWithAppleCalled = false;
  bool signOutCalled = false;
  bool deleteAccountCalled = false;
  String? passwordResetEmail;

  Object? emailSignInError;
  Object? appleSignInError;
  Object? deleteAccountError;
  Object? passwordResetError;

  @override
  Future<UserCredential> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    signInWithEmailCalled = true;
    if (emailSignInError != null) throw emailSignInError!;
    return _FakeUserCredential();
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword(
    String email,
    String password,
  ) async {
    signUpWithEmailCalled = true;
    if (emailSignInError != null) throw emailSignInError!;
    return _FakeUserCredential();
  }

  @override
  Future<UserCredential> signInWithApple() async {
    signInWithAppleCalled = true;
    if (appleSignInError != null) throw appleSignInError!;
    return _FakeUserCredential();
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    passwordResetEmail = email;
    if (passwordResetError != null) throw passwordResetError!;
  }

  @override
  Future<void> deleteAccount() async {
    deleteAccountCalled = true;
    if (deleteAccountError != null) throw deleteAccountError!;
  }
}

class _FakeUserCredential extends Fake implements UserCredential {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer(FakeAuthRepository repo) {
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    // Seed the ObservabilityBootstrap singleton with a no-op reporter so the
    // notifier's .current calls do not attempt to reach Firebase/Sentry.
    ObservabilityBootstrap.build(
      overrideForTesting: const NullCrashReporter(),
    );
  });

  group('AuthNotifier', () {
    test('signInWithEmail — sets isLoading then resolves to idle on success',
        () async {
      final repo = FakeAuthRepository();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      final states = <AuthState>[];
      container.listen<AuthState>(
        authNotifierProvider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );

      await container
          .read(authNotifierProvider.notifier)
          .signInWithEmail('user@example.com', 'secret');

      expect(repo.signInWithEmailCalled, isTrue);
      // Initial idle → loading → idle
      expect(states[0], const AuthState());
      expect(states[1].isLoading, isTrue);
      expect(states[2], const AuthState());
    });

    test('signInWithEmail — sets errorMessage on failure', () async {
      final repo = FakeAuthRepository()
        ..emailSignInError = Exception('bad-credentials');
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      final states = <AuthState>[];
      container.listen<AuthState>(
        authNotifierProvider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );

      await container
          .read(authNotifierProvider.notifier)
          .signInWithEmail('user@example.com', 'wrong');

      expect(repo.signInWithEmailCalled, isTrue);
      // States: idle → loading → error. Raw exceptions never leak into the
      // UI — unknown errors map to the German fallback text.
      expect(states[0], const AuthState());
      expect(states[1].isLoading, isTrue);
      expect(states[2].isLoading, isFalse);
      expect(states[2].errorMessage, kAuthErrorFallback);
    });

    test('signInWithEmail — maps FirebaseAuthException codes to German text',
        () async {
      final repo = FakeAuthRepository()
        ..emailSignInError = FirebaseAuthException(code: 'invalid-credential');
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container
          .read(authNotifierProvider.notifier)
          .signInWithEmail('user@example.com', 'wrong');

      expect(
        container.read(authNotifierProvider).errorMessage,
        'E-Mail oder Passwort falsch.',
      );
    });

    test('sendPasswordReset — delegates to repository, null on success',
        () async {
      final repo = FakeAuthRepository();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      final error = await container
          .read(authNotifierProvider.notifier)
          .sendPasswordReset('user@example.com');

      expect(repo.passwordResetEmail, 'user@example.com');
      expect(error, isNull);
      // Reset läuft außerhalb des Formular-States — keine Mutation.
      expect(container.read(authNotifierProvider), const AuthState());
    });

    test('sendPasswordReset — returns the mapped message on failure',
        () async {
      final repo = FakeAuthRepository()
        ..passwordResetError = FirebaseAuthException(code: 'invalid-email');
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      final error = await container
          .read(authNotifierProvider.notifier)
          .sendPasswordReset('not-an-email');

      expect(error, 'Das ist keine gültige E-Mail-Adresse.');
      expect(container.read(authNotifierProvider), const AuthState());
    });

    test('signInWithApple — sets isLoading then resolves to idle on success',
        () async {
      final repo = FakeAuthRepository();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      final states = <AuthState>[];
      container.listen<AuthState>(
        authNotifierProvider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );

      await container.read(authNotifierProvider.notifier).signInWithApple();

      expect(repo.signInWithAppleCalled, isTrue);
      expect(states[0], const AuthState());
      expect(states[1].isLoading, isTrue);
      expect(states[2], const AuthState());
    });

    test('signOut — delegates to repository and returns to idle state',
        () async {
      final repo = FakeAuthRepository();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).signOut();

      expect(repo.signOutCalled, isTrue);
      expect(
        container.read(authNotifierProvider),
        const AuthState(),
      );
    });

    test('deleteAccount — delegates to repository and returns to idle state',
        () async {
      final repo = FakeAuthRepository();
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).deleteAccount();

      expect(repo.deleteAccountCalled, isTrue);
      expect(container.read(authNotifierProvider), const AuthState());
    });

    test('deleteAccount — falls back to signOut when Firebase delete fails',
        () async {
      final repo = FakeAuthRepository()
        ..deleteAccountError = Exception('requires-recent-login');
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).deleteAccount();

      expect(repo.deleteAccountCalled, isTrue);
      // Firebase delete failed → we still sign out so the local session ends.
      expect(repo.signOutCalled, isTrue);
      expect(container.read(authNotifierProvider), const AuthState());
    });
  });
}
