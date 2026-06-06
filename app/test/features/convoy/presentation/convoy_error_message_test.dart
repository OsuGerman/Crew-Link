import 'package:crew_link/features/convoy/data/convoy_api.dart';
import 'package:crew_link/features/convoy/presentation/convoy_home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('friendlyConvoyError', () {
    test('404 → invite-code-not-found warning, never the raw exception', () {
      final msg = friendlyConvoyError(ConvoyApiException(404, '{"error":"x"}'));
      expect(msg, contains('nicht gefunden'));
      expect(msg, isNot(contains('ConvoyApiException')));
      expect(msg, isNot(contains('404')));
    });

    test('401 → re-login warning', () {
      expect(friendlyConvoyError(ConvoyApiException(401, '{}')),
          contains('neu anmelden'));
    });

    test('500 → generic convoy-action failure', () {
      expect(friendlyConvoyError(ConvoyApiException(500, '{}')),
          contains('fehlgeschlagen'));
    });

    test('non-API error → generic, friendly message', () {
      expect(
          friendlyConvoyError(Exception('boom')), contains('schiefgelaufen'));
    });
  });
}
