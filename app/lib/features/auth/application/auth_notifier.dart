import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/observability/app_logger.dart';
import '../../../core/observability/observability_bootstrap.dart';
import '../data/auth_repository.dart';
import 'auth_error_messages.dart';

/// Immutable state for auth operations.
class AuthState {
  const AuthState({this.isLoading = false, this.errorMessage});

  final bool isLoading;
  final String? errorMessage;

  AuthState copyWith({bool? isLoading, String? errorMessage}) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthState &&
          runtimeType == other.runtimeType &&
          isLoading == other.isLoading &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(isLoading, errorMessage);

  @override
  String toString() =>
      'AuthState(isLoading: $isLoading, errorMessage: $errorMessage)';
}

/// Manages auth operations (Apple, email/password) with loading and error state.
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> signInWithApple() async {
    state = state.copyWith(isLoading: true);
    try {
      await _repo.signInWithApple();
      state = const AuthState();
    } catch (e, st) {
      appLog.e('AuthNotifier.signInWithApple', error: e, stackTrace: st);
      unawaited(ObservabilityBootstrap.build().reportError(e, st));
      state = AuthState(errorMessage: authErrorMessage(e));
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    state = state.copyWith(isLoading: true);
    try {
      await _repo.signInWithEmailAndPassword(email, password);
      state = const AuthState();
    } catch (e, st) {
      appLog.e('AuthNotifier.signInWithEmail', error: e, stackTrace: st);
      unawaited(ObservabilityBootstrap.build().reportError(e, st));
      state = AuthState(errorMessage: authErrorMessage(e));
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    state = state.copyWith(isLoading: true);
    try {
      await _repo.createUserWithEmailAndPassword(email, password);
      state = const AuthState();
    } catch (e, st) {
      appLog.e('AuthNotifier.signUpWithEmail', error: e, stackTrace: st);
      unawaited(ObservabilityBootstrap.build().reportError(e, st));
      state = AuthState(errorMessage: authErrorMessage(e));
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);
    try {
      await _repo.signOut();
      state = const AuthState();
    } catch (e, st) {
      appLog.e('AuthNotifier.signOut', error: e, stackTrace: st);
      unawaited(ObservabilityBootstrap.build().reportError(e, st));
      state = AuthState(errorMessage: authErrorMessage(e));
    }
  }

  /// Versendet die Passwort-Reset-Mail. Liefert `null` bei Erfolg, sonst den
  /// gemappten Kurztext. Bewusst ohne [state]-Mutation: Die Bestätigung ist
  /// neutral ("falls ein Konto existiert") und läuft als SnackBar, nicht über
  /// den Inline-Fehlertext des Login-Formulars.
  Future<String?> sendPasswordReset(String email) async {
    try {
      await _repo.sendPasswordResetEmail(email);
      return null;
    } catch (e, st) {
      appLog.e('AuthNotifier.sendPasswordReset', error: e, stackTrace: st);
      unawaited(ObservabilityBootstrap.build().reportError(e, st));
      return authErrorMessage(e);
    }
  }

  /// Deletes the Firebase account. Server-side data is removed separately (REST)
  /// before this runs. If Firebase rejects the delete (e.g. a stale session) we
  /// still sign out so the local session ends — the user is logged out either
  /// way and their server data is already gone.
  Future<void> deleteAccount() async {
    state = state.copyWith(isLoading: true);
    try {
      await _repo.deleteAccount();
      state = const AuthState();
    } catch (e, st) {
      appLog.e('AuthNotifier.deleteAccount', error: e, stackTrace: st);
      unawaited(ObservabilityBootstrap.build().reportError(e, st));
      await _repo.signOut();
      state = const AuthState();
    }
  }
}

final authNotifierProvider =
    NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
