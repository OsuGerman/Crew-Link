import 'package:crew_link/features/auth/application/auth_error_messages.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

FirebaseAuthException _e(String code) => FirebaseAuthException(code: code);

void main() {
  group('authErrorMessage', () {
    test('maps credential errors to one neutral message', () {
      const expected = 'E-Mail oder Passwort falsch.';
      expect(authErrorMessage(_e('invalid-credential')), expected);
      expect(authErrorMessage(_e('wrong-password')), expected);
      expect(authErrorMessage(_e('user-not-found')), expected);
    });

    test('maps sign-up errors', () {
      expect(
        authErrorMessage(_e('email-already-in-use')),
        'Diese E-Mail ist bereits registriert.',
      );
      expect(
        authErrorMessage(_e('weak-password')),
        'Passwort zu schwach — mindestens 6 Zeichen.',
      );
      expect(
        authErrorMessage(_e('invalid-email')),
        'Das ist keine gültige E-Mail-Adresse.',
      );
    });

    test('maps network and throttling errors', () {
      expect(
        authErrorMessage(_e('network-request-failed')),
        'Keine Internetverbindung.',
      );
      expect(
        authErrorMessage(_e('too-many-requests')),
        'Zu viele Versuche — bitte kurz warten.',
      );
    });

    test('falls back for unknown Firebase codes', () {
      expect(authErrorMessage(_e('operation-not-allowed')), kAuthErrorFallback);
    });

    test('falls back for non-Firebase errors', () {
      expect(authErrorMessage(Exception('boom')), kAuthErrorFallback);
      expect(authErrorMessage(StateError('x')), kAuthErrorFallback);
    });
  });
}
