import 'dart:convert';

import 'package:crew_link/core/config/api_config.dart';
import 'package:crew_link/features/push_to_talk/data/ptt_token_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _grantJson() => jsonEncode({
      'url': 'wss://livekit.example',
      'token': 'lk-token',
      'roomName': 'convoy-c1',
    });

bool _sendsJsonContentType(http.BaseRequest req) => req.headers.entries.any(
      (e) =>
          e.key.toLowerCase() == 'content-type' &&
          e.value.toLowerCase().contains('application/json'),
    );

void main() {
  group('PttTokenFetcher', () {
    late List<http.Request> recorded;
    late int tokenCalls;

    PttTokenFetcher fetcherWith(
      http.Response Function(http.Request req) handler,
    ) {
      recorded = [];
      tokenCalls = 0;
      return PttTokenFetcher(
        config: ApiConfig.local(),
        tokenProvider: () async {
          tokenCalls += 1;
          return 'fresh-$tokenCalls';
        },
        client: MockClient((req) async {
          recorded.add(req);
          return handler(req);
        }),
      );
    }

    test('Erfolg: POST auf /convoys/:id/ptt-token mit frischem Bearer-Token',
        () async {
      final fetcher = fetcherWith((_) => http.Response(_grantJson(), 200));

      final grant = await fetcher.fetchToken('c1');

      final req = recorded.single;
      expect(req.method, 'POST');
      expect(req.url.path, '/convoys/c1/ptt-token');
      expect(req.headers['Authorization'], 'Bearer fresh-1');
      expect(grant.url, 'wss://livekit.example');
      expect(grant.token, 'lk-token');
      expect(grant.roomName, 'convoy-c1');
    });

    test('bodyloser POST sendet keinen JSON-Content-Type (Fastify-Regression)',
        () async {
      // Ein bodyloser POST mit `Content-Type: application/json` würde Fastify
      // mit FST_ERR_CTP_EMPTY_JSON_BODY ablehnen, bevor die Auth läuft.
      final fetcher = fetcherWith((_) => http.Response(_grantJson(), 200));

      await fetcher.fetchToken('c1');

      expect(_sendsJsonContentType(recorded.single), isFalse);
    });

    test('holt für jeden Aufruf einen frischen Auth-Token', () async {
      final fetcher = fetcherWith((_) => http.Response(_grantJson(), 200));

      await fetcher.fetchToken('c1');
      await fetcher.fetchToken('c1');

      expect(recorded[1].headers['Authorization'], 'Bearer fresh-2');
    });

    test('503 (LiveKit nicht konfiguriert) wirft PttTokenException mit Status',
        () async {
      final fetcher = fetcherWith(
        (_) => http.Response('{"error":"livekit not configured"}', 503),
      );

      await expectLater(
        fetcher.fetchToken('c1'),
        throwsA(
          isA<PttTokenException>()
              .having((e) => e.statusCode, 'statusCode', 503),
        ),
      );
    });

    test('401 wirft PttTokenException mit Status', () async {
      final fetcher = fetcherWith((_) => http.Response('unauthorized', 401));

      await expectLater(
        fetcher.fetchToken('c1'),
        throwsA(
          isA<PttTokenException>()
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });
  });
}
