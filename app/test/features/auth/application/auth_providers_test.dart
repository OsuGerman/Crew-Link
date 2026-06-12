import 'dart:async';

import 'package:crew_link/features/auth/application/auth_providers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('signedInUidProvider', () {
    test('returns empty string when auth stream emits null', () async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((_) => Stream.value(null)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authStateProvider.future);
      expect(container.read(signedInUidProvider), '');
    });

    test('returns uid when auth stream emits a user', () async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (_) => Stream.value(_FakeUser('test-uid-123')),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authStateProvider.future);
      expect(container.read(signedInUidProvider), 'test-uid-123');
    });
  });

  group('authIdTokenProvider', () {
    test('returns null when signed out', () async {
      final container = ProviderContainer(
        overrides: [
          idTokenChangesProvider.overrideWith((_) => Stream.value(null)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(idTokenChangesProvider.future);
      final result = await container.read(authIdTokenProvider.future);
      expect(result, isNull);
    });

    test('re-fetches the token whenever idTokenChanges emits — hourly '
        'Firebase refreshes reach REST callers without restart', () async {
      final userEvents = StreamController<User?>();
      addTearDown(userEvents.close);
      final container = ProviderContainer(
        overrides: [
          idTokenChangesProvider.overrideWith((_) => userEvents.stream),
        ],
      );
      addTearDown(container.dispose);
      // Keep the provider alive across emissions.
      final sub = container.listen(authIdTokenProvider, (_, __) {});
      addTearDown(sub.close);

      userEvents.add(_FakeUser('u1', token: 'tok-old'));
      await Future<void>.delayed(Duration.zero);
      expect(await container.read(authIdTokenProvider.future), 'tok-old');

      // Token-Refresh: gleicher User, neuer Token → Provider muss neu lesen.
      userEvents.add(_FakeUser('u1', token: 'tok-fresh'));
      await Future<void>.delayed(Duration.zero);
      expect(await container.read(authIdTokenProvider.future), 'tok-fresh');
    });
  });
}

class _FakeUser extends Fake implements User {
  _FakeUser(this._uid, {String token = 'fake-token'}) : _token = token;
  final String _uid;
  final String _token;

  @override
  String get uid => _uid;

  @override
  Future<String> getIdToken([bool forceRefresh = false]) async => _token;
}
