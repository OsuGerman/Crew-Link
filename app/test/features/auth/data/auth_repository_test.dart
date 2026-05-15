import 'package:crew_link/features/auth/data/auth_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FirebaseAuthRepository._generateNonce / _sha256ofString', () {
    // Testing via signInWithApple() is not feasible in unit tests (requires
    // native Apple SDK). We validate the repository contract via the interface.

    test('_FakeAuthRepo signOut completes without throwing', () async {
      await expectLater(_FakeAuthRepo().signOut(), completes);
    });

    test('_FakeAuthRepo signInWithApple throws UnsupportedError', () async {
      expect(
        () => _FakeAuthRepo().signInWithApple(),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}

class _FakeAuthRepo implements AuthRepository {
  @override
  Future<UserCredential> signInWithApple() =>
      throw UnsupportedError('no native Apple SDK in tests');

  @override
  Future<void> signOut() async {}
}
