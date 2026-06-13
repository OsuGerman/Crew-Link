import 'dart:async';
import 'dart:convert';

import 'package:crew_link/core/config/api_config.dart';
import 'package:crew_link/features/convoy/data/convoy_api.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> _convoyJson() => {
      'id': 'c1',
      'name': 'Trip',
      'inviteCode': 'ABC123',
      'members': <Object?>[],
      'proximityWarningMeters': 500,
      'createdAt': '2026-06-05T12:00:00Z',
    };

bool _sendsJsonContentType(http.BaseRequest req) => req.headers.entries.any(
      (e) =>
          e.key.toLowerCase() == 'content-type' &&
          e.value.toLowerCase().contains('application/json'),
    );

void main() {
  group('ConvoyApi', () {
    late List<http.BaseRequest> recorded;

    ConvoyApi apiWith(http.Response Function(http.Request req) handler) {
      recorded = <http.BaseRequest>[];
      final client = MockClient((req) async {
        recorded.add(req);
        return handler(req);
      });
      return ConvoyApi(config: ApiConfig.local(), client: client);
    }

    test('createConvoy POSTs a non-empty JSON body', () async {
      final api = apiWith((_) => http.Response(jsonEncode(_convoyJson()), 201));
      await api.createConvoy(name: 'Trip', authToken: 'tok');
      final req = recorded.single as http.Request;
      expect(req.method, 'POST');
      expect(req.url.path, '/convoys');
      expect(req.headers['Authorization'], 'Bearer tok');
      expect(_sendsJsonContentType(req), isTrue);
      expect(req.body, isNotEmpty);
      expect(jsonDecode(req.body), containsPair('name', 'Trip'));
    });

    test('joinConvoy POSTs the invite code as a JSON body', () async {
      final api = apiWith((_) => http.Response(jsonEncode(_convoyJson()), 200));
      await api.joinConvoy(inviteCode: 'ABC123', authToken: 'tok');
      final req = recorded.single as http.Request;
      expect(req.method, 'POST');
      expect(req.url.path, '/convoys/join');
      expect(jsonDecode(req.body), containsPair('inviteCode', 'ABC123'));
    });

    test('leaveConvoy DELETE sends no JSON content-type (bodyless request)',
        () async {
      // Regression: a bodyless DELETE with `Content-Type: application/json`
      // makes Fastify reject with FST_ERR_CTP_EMPTY_JSON_BODY before the route
      // (and its auth) ever runs.
      final api = apiWith((_) => http.Response('', 204));
      await api.leaveConvoy(convoyId: 'c1', authToken: 'tok');
      final req = recorded.single;
      expect(req.method, 'DELETE');
      expect(req.url.path, '/convoys/c1/membership');
      expect(req.headers['Authorization'], 'Bearer tok');
      expect(_sendsJsonContentType(req), isFalse);
    });

    test('createConvoy wirft TimeoutException, wenn das Backend nie antwortet',
        () {
      // Hängendes Backend (z. B. pausierte DB): die Antwort kommt nie. Ohne
      // Timeout bliebe die Lobby ewig auf „Konvoi wird vorbereitet …".
      fakeAsync((async) {
        final client = MockClient((_) => Completer<http.Response>().future);
        final api = ConvoyApi(config: ApiConfig.local(), client: client);
        Object? caught;
        unawaited(
          api
              .createConvoy(name: 'Trip', authToken: 'tok')
              .then<void>((_) {})
              .catchError((Object e) {
            caught = e;
          }),
        );

        // Knapp unter dem Timeout: noch kein Fehler.
        async.elapse(ConvoyApi.requestTimeout - const Duration(seconds: 1));
        expect(caught, isNull);

        // Über den Timeout hinaus: TimeoutException statt ewigem Hängen.
        async.elapse(const Duration(seconds: 2));
        expect(caught, isA<TimeoutException>());
      });
    });
  });
}
