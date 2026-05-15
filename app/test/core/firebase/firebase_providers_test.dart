import 'package:crew_link/core/firebase/firebase_providers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('firebase providers override contract', () {
    test('firebaseAuthProvider can be overridden', () {
      // Providers must be overridable so widgets/repos can be tested with fakes.
      final fakeAuth = _FakeFirebaseAuth();
      final container = ProviderContainer(
        overrides: [firebaseAuthProvider.overrideWithValue(fakeAuth)],
      );
      addTearDown(container.dispose);
      expect(container.read(firebaseAuthProvider), same(fakeAuth));
    });

    test('firestoreProvider can be overridden', () {
      final fakeFirestore = _FakeFirebaseFirestore();
      final container = ProviderContainer(
        overrides: [firestoreProvider.overrideWithValue(fakeFirestore)],
      );
      addTearDown(container.dispose);
      expect(container.read(firestoreProvider), same(fakeFirestore));
    });

    test('realtimeDatabaseProvider can be overridden', () {
      final fakeDb = _FakeFirebaseDatabase();
      final container = ProviderContainer(
        overrides: [realtimeDatabaseProvider.overrideWithValue(fakeDb)],
      );
      addTearDown(container.dispose);
      expect(container.read(realtimeDatabaseProvider), same(fakeDb));
    });
  });
}

class _FakeFirebaseAuth extends Fake implements FirebaseAuth {}

class _FakeFirebaseFirestore extends Fake implements FirebaseFirestore {}

class _FakeFirebaseDatabase extends Fake implements FirebaseDatabase {}
