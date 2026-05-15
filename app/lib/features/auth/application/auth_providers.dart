import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import 'auth_notifier.dart';

export 'auth_notifier.dart' show authNotifierProvider, AuthState, AuthNotifier;

/// Stream of the current Firebase auth user. Emits `null` when signed out.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

/// Firebase UID of the signed-in user, or empty string when signed out.
final signedInUidProvider = Provider<String>((ref) {
  return ref.watch(authStateProvider).valueOrNull?.uid ?? '';
});

/// Firebase ID token for the signed-in user. Re-fetched whenever auth state
/// changes. Returns `null` while signed out or while the token is loading.
final authIdTokenProvider = FutureProvider<String?>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return null;
  return user.getIdToken();
});

/// Dev-Override: erlaubt der Web-Preview (kein Firebase) den Auth-Gate des
/// Routers zu umgehen, ohne einen Fake-`User` zu basteln. Produktion lässt
/// das auf `false`; die Override im Main-Entry der Preview setzt true.
final devSignedInOverrideProvider = StateProvider<bool>((_) => false);
