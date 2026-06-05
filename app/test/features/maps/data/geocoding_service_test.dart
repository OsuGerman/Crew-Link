import 'package:crew_link/features/maps/data/geocoding_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('GeocodingService.search', () {
    test('returns empty for queries shorter than the minimum', () async {
      final service = GeocodingService(
        client: MockClient((_) async => http.Response('[]', 200)),
      );
      expect(await service.search('ab'), isEmpty);
    });

    test('parses Nominatim results and sends the query', () async {
      const body = '[{"lat":"49.4459","lon":"11.0826",'
          '"display_name":"Hauptbahnhof, Nürnberg, Bayern"},'
          '{"lat":"52.5251","lon":"13.3694",'
          '"display_name":"Hauptbahnhof, Berlin"}]';
      late Uri captured;
      final service = GeocodingService(
        client: MockClient((req) async {
          captured = req.url;
          return http.Response(body, 200);
        }),
      );

      final results = await service.search('Hauptbahnhof');

      expect(captured.queryParameters['q'], 'Hauptbahnhof');
      expect(results, hasLength(2));
      expect(results.first.label, 'Hauptbahnhof, Nürnberg, Bayern');
      expect(results.first.shortLabel, 'Hauptbahnhof');
      expect(results.first.latitude, closeTo(49.4459, 0.0001));
      expect(results.first.longitude, closeTo(11.0826, 0.0001));
    });

    test('returns empty on a non-200 response', () async {
      final service = GeocodingService(
        client: MockClient((_) async => http.Response('error', 500)),
      );
      expect(await service.search('Nürnberg'), isEmpty);
    });

    test('skips entries without parseable coordinates', () async {
      const body = '[{"display_name":"No coords"},'
          '{"lat":"1.0","lon":"2.0","display_name":"OK"}]';
      final service = GeocodingService(
        client: MockClient((_) async => http.Response(body, 200)),
      );
      final results = await service.search('test');
      expect(results, hasLength(1));
      expect(results.single.label, 'OK');
    });
  });
}
