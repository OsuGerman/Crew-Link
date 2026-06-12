import 'dart:convert';

import 'package:crew_link/core/realtime/hazard_event.dart';
import 'package:crew_link/core/realtime/inbound_frame_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

String _frame(String type, Object? payload) =>
    jsonEncode({'type': type, 'payload': payload});

void main() {
  group('decodeInboundFrame', () {
    test('decodes gps frames', () {
      final frame = decodeInboundFrame(_frame('gps', {
        'memberId': 'alice',
        'latitude': 52.52,
        'longitude': 13.405,
        'heading': 90.0,
        'speed': 10.0,
        'timestamp': '2026-05-14T10:00:00.000Z',
      }));
      expect(frame, isA<GpsFrame>());
      expect((frame! as GpsFrame).update.memberId, 'alice');
    });

    test('decodes waypoint clear (null payload) as WaypointFrame(null)', () {
      final frame = decodeInboundFrame(_frame('waypoint', null));
      expect(frame, isA<WaypointFrame>());
      expect((frame! as WaypointFrame).waypoint, isNull);
    });

    test('decodes hazard_remove into HazardRemoved event', () {
      final frame = decodeInboundFrame(_frame('hazard_remove', {'id': 'h1'}));
      expect(frame, isA<HazardFrame>());
      final event = (frame! as HazardFrame).event;
      expect(event, isA<HazardRemoved>());
      expect((event as HazardRemoved).id, 'h1');
    });

    test('decodes status frames into QuickActionFrame', () {
      final frame = decodeInboundFrame(_frame('status', {
        'memberId': 'buddy',
        'kind': 'pause',
        'at': '2026-06-12T10:00:00.000Z',
      }));
      expect(frame, isA<QuickActionFrame>());
    });

    test('returns null for unknown types, malformed payloads and non-strings',
        () {
      expect(decodeInboundFrame(_frame('unknown_future_type', {})), isNull);
      expect(decodeInboundFrame(_frame('gps', 'not-a-map')), isNull);
      expect(decodeInboundFrame(_frame('hazard_remove', {'id': 42})), isNull);
      expect(decodeInboundFrame(jsonEncode(['not', 'a', 'map'])), isNull);
      expect(decodeInboundFrame(42), isNull);
      expect(decodeInboundFrame('{broken json'), isNull,
          reason: 'malformed JSON must not crash the stream listener');
    });
  });
}
