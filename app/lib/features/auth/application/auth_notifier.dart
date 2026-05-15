import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/observability/app_logger.dart';
import '../../../core/observability/observability_bootstrap.dart';
import '../data/auth_repository.dart';

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
      state = AuthState(errorMessage: e.toString());
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
      state = AuthState(errorMessage: e.toString());
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
      state = AuthState(errorMessage: e.toString());
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
      state = AuthState(errorMessage: e.toString());
    }
  }
}

final authNotifierProvider =
    NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
