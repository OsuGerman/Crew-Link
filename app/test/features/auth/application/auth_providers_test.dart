import 'package:crew_link/features/auth/application/auth_providers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('signedInUidProvider', () {
    test('returns empty string when auth stream emits null', () {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((_) => Stream.value(null)),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(signedInUidProvider), '');
    });

    test('returns uid when auth stream emits a user', () {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (_) => Stream.value(_FakeUser('test-uid-123')),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(signedInUidProvider), 'test-uid-123');
    });
  });

  group('authIdTokenProvider', () {
    test('returns null when signed out', () async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((_) => Stream.value(null)),
        ],
      );
      addTearDown(container.dispose);
      final result = await container.read(authIdTokenProvider.future);
      expect(result, isNull);
    });
  });
}

class _FakeUser extends Fake implements User {
  _FakeUser(this._uid);
  final String _uid;

  @override
  String get uid => _uid;

  @override
  Future<String> getIdToken([bool forceRefresh = false]) async => 'fake-token';
}
