import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../domain/geocode_result.dart';

/// Forward-geocoding via OpenStreetMap Nominatim — turns an address/place query
/// into coordinates. Free and key-less, matching the OpenFreeMap map tiles.
///
/// Nominatim's usage policy requires a descriptive User-Agent and light load,
/// so callers should debounce input; results are capped. For heavy production
/// traffic switch to a self-hosted Nominatim or a paid geocoder.
class GeocodingService {
  GeocodingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static final Uri _endpoint =
      Uri.parse('https://nominatim.openstreetmap.org/search');
  static const int minQueryLength = 3;
  static const int _maxResults = 6;
  static const String _userAgent = 'CrewLink/1.0 (https://crewlink.app)';

  /// Searches for [query]; returns up to a handful of matches, or an empty list
  /// for short queries, network errors, or non-200 responses (never throws to
  /// the UI for the common failure cases).
  Future<List<GeocodeResult>> search(String query) async {
    final q = query.trim();
    if (q.length < minQueryLength) return const [];

    final uri = _endpoint.replace(queryParameters: <String, String>{
      'q': q,
      'format': 'jsonv2',
      'limit': '$_maxResults',
      'addressdetails': '0',
    });

    final response = await _client.get(uri, headers: const {
      'User-Agent': _userAgent,
      'Accept': 'application/json',
    });
    if (response.statusCode != 200) return const [];

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];

    final results = <GeocodeResult>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final lat = double.tryParse('${item['lat']}');
      final lon = double.tryParse('${item['lon']}');
      if (lat == null || lon == null) continue;
      results.add(
        GeocodeResult(
          label: '${item['display_name'] ?? q}',
          latitude: lat,
          longitude: lon,
        ),
      );
    }
    return results;
  }
}

final geocodingServiceProvider =
    Provider<GeocodingService>((ref) => GeocodingService());
