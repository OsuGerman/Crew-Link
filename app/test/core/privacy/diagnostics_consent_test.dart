import 'package:crew_link/core/privacy/diagnostics_consent.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final store = <String, String>{};

  setUp(() {
    store.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, Object?>() ?? {};
      switch (call.method) {
        case 'write':
          store[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return store[args['key'] as String];
        case 'readAll':
          return Map<String, String>.from(store);
        case 'delete':
          store.remove(args['key']);
          return null;
        case 'deleteAll':
          store.clear();
          return null;
        case 'containsKey':
          return store.containsKey(args['key']);
      }
      return null;
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  group('DiagnosticsConsent', () {
    test('defaults to undecided + disabled when nothing is stored', () async {
      final consent = await DiagnosticsConsent.load();
      expect(consent.decided, isFalse);
      expect(consent.enabled, isFalse);
    });

    test('persist(true) → decided + enabled', () async {
      await DiagnosticsConsent.persist(true);
      final consent = await DiagnosticsConsent.load();
      expect(consent.decided, isTrue);
      expect(consent.enabled, isTrue);
    });

    test('persist(false) → decided but disabled', () async {
      await DiagnosticsConsent.persist(false);
      final consent = await DiagnosticsConsent.load();
      expect(consent.decided, isTrue);
      expect(consent.enabled, isFalse);
    });
  });
}
