import 'package:firebase_auth/firebase_auth.dart';

/// Fallback, wenn kein bekannter Firebase-Code zugeordnet werden kann
/// (oder der Fehler gar keine [FirebaseAuthException] ist).
const kAuthErrorFallback = 'Anmeldung fehlgeschlagen — bitte erneut versuchen.';

/// Pure Zuordnung `FirebaseAuthException.code` → deutscher Kurztext.
/// Bewusst neutral bei Credential-Fehlern (kein Hinweis, ob die E-Mail
/// existiert) und ohne rohe Exception-Dumps im UI.
String authErrorMessage(Object error) {
  if (error is! FirebaseAuthException) return kAuthErrorFallback;
  return switch (error.code) {
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' =>
      'E-Mail oder Passwort falsch.',
    'email-already-in-use' => 'Diese E-Mail ist bereits registriert.',
    'weak-password' => 'Passwort zu schwach — mindestens 6 Zeichen.',
    'invalid-email' => 'Das ist keine gültige E-Mail-Adresse.',
    'network-request-failed' => 'Keine Internetverbindung.',
    'too-many-requests' => 'Zu viele Versuche — bitte kurz warten.',
    _ => kAuthErrorFallback,
  };
}
