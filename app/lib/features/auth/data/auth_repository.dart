import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/firebase/firebase_providers.dart';

abstract class AuthRepository {
  Future<UserCredential> signInWithApple();
  Future<UserCredential> signInWithEmailAndPassword(
    String email,
    String password,
  );
  Future<UserCredential> createUserWithEmailAndPassword(
    String email,
    String password,
  );
  Future<void> signOut();
}

class FirebaseAuthRepository implements AuthRepository {
  const FirebaseAuthRepository(this._auth);
  final FirebaseAuth _auth;

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256ofString(String input) {
    final digest = sha256.convert(utf8.encode(input));
    return digest.toString();
  }

  @override
  Future<UserCredential> signInWithApple() async {
    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );

    final idToken = appleCredential.identityToken;
    if (idToken == null) {
      throw StateError('Apple Sign-In returned no identity token');
    }

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: idToken,
      rawNonce: rawNonce,
    );

    return _auth.signInWithCredential(oauthCredential);
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword(
    String email,
    String password,
  ) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  @override
  Future<UserCredential> createUserWithEmailAndPassword(
    String email,
    String password,
  ) =>
      _auth.createUserWithEmailAndPassword(email: email, password: password);

  @override
  Future<void> signOut() => _auth.signOut();
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository(ref.watch(firebaseAuthProvider));
});
