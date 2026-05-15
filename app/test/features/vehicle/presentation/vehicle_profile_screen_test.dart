import 'dart:async';
import 'dart:convert';

import 'package:crew_link/core/models/vehicle_profile.dart';
import 'package:crew_link/features/convoy/application/convoy_providers.dart';
import 'package:crew_link/features/vehicle/application/vehicle_providers.dart';
import 'package:crew_link/features/vehicle/presentation/vehicle_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Captures requests + lets the test program the response per-call.
class _RecordingClient {
  _RecordingClient(this.responder);
  final List<http.BaseRequest> recorded = <http.BaseRequest>[];
  final Future<http.Response> Function(http.BaseRequest) responder;

  http.Client build() => MockClient((req) async {
        recorded.add(req);
        return responder(req);
      });
}

ProviderContainer _containerWith({
  required _RecordingClient recorder,
}) {
  return ProviderContainer(overrides: [
    httpClientProvider.overrideWithValue(recorder.build()),
    authTokenProvider.overrideWithValue('test-token'),
  ]);
}

Widget _screen() => const MaterialApp(home: VehicleProfileScreen());

void main() {
  group('VehicleProfileScreen', () {
    testWidgets('shows progress while GET /vehicles/me is in flight',
        (tester) async {
      final completer = Completer<http.Response>();
      final rec = _RecordingClient((_) => completer.future);
      final container = _containerWith(recorder: rec);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: _screen(),
      ));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(http.Response('null', 200));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('renders empty form when server returns null',
        (tester) async {
      final rec = _RecordingClient((_) async => http.Response('null', 200));
      final container = _containerWith(recorder: rec);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: _screen(),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vehicle-make')), findsOneWidget);
      expect(find.byKey(const ValueKey('vehicle-remove')), findsNothing);
    });

    testWidgets('pre-fills form when server returns a vehicle',
        (tester) async {
      final rec = _RecordingClient((_) async => http.Response(
            jsonEncode({
              'id': 'v1',
              'make': 'Tesla',
              'model': 'Model 3',
              'year': 2024,
              'color': 'Rot',
            }),
            200,
          ));
      final container = _containerWith(recorder: rec);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: _screen(),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Tesla'), findsOneWidget);
      expect(find.byKey(const ValueKey('vehicle-remove')), findsOneWidget);
    });

    testWidgets('save PUTs to /vehicles/me and updates the provider',
        (tester) async {
      var current = http.Response('null', 200);
      final rec = _RecordingClient((req) async => current);
      final container = _containerWith(recorder: rec);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: _screen(),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const ValueKey('vehicle-make')), 'Porsche');
      await tester.enterText(
          find.byKey(const ValueKey('vehicle-model')), '911 GT3');

      current = http.Response(
        jsonEncode({
          'id': 'v2',
          'make': 'Porsche',
          'model': '911 GT3',
          'year': null,
          'color': null,
        }),
        200,
      );
      await tester.tap(find.byKey(const ValueKey('vehicle-save')));
      await tester.pumpAndSettle();

      final put = rec.recorded.firstWhere((r) => r.method == 'PUT');
      expect(put.url.path, '/vehicles/me');
      expect(put.headers['Authorization'], 'Bearer test-token');
      final body = jsonDecode((put as http.Request).body) as Map<String, Object?>;
      expect(body['make'], 'Porsche');
      expect(body['model'], '911 GT3');

      final saved = container.read(myVehicleProvider).valueOrNull;
      expect(saved, isNotNull);
      expect(saved!.make, 'Porsche');
    });

    testWidgets('save with empty fields shows validation, no PUT issued',
        (tester) async {
      final rec = _RecordingClient((_) async => http.Response('null', 200));
      final container = _containerWith(recorder: rec);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: _screen(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('vehicle-save')));
      await tester.pumpAndSettle();
      expect(find.text('Marke angeben'), findsOneWidget);
      expect(rec.recorded.any((r) => r.method == 'PUT'), isFalse);
    });

    testWidgets('remove issues DELETE and clears provider', (tester) async {
      var current = http.Response(
        jsonEncode({
          'id': 'v',
          'make': 'BMW',
          'model': 'M2',
          'year': null,
          'color': null,
        }),
        200,
      );
      final rec = _RecordingClient((_) async => current);
      final container = _containerWith(recorder: rec);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: _screen(),
      ));
      await tester.pumpAndSettle();

      current = http.Response('', 204);
      await tester.tap(find.byKey(const ValueKey('vehicle-remove')));
      await tester.pumpAndSettle();

      expect(rec.recorded.any((r) => r.method == 'DELETE'), isTrue);
      expect(container.read(myVehicleProvider).valueOrNull, isNull);
    });

    testWidgets('error state shows retry button', (tester) async {
      var current = http.Response('boom', 500);
      final rec = _RecordingClient((_) async => current);
      final container = _containerWith(recorder: rec);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: _screen(),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vehicle-retry')), findsOneWidget);

      current = http.Response('null', 200);
      await tester.tap(find.byKey(const ValueKey('vehicle-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vehicle-retry')), findsNothing);
      expect(find.byKey(const ValueKey('vehicle-make')), findsOneWidget);
    });

    testWidgets('pre-fills spec fields when vehicle has them', (tester) async {
      final rec = _RecordingClient((_) async => http.Response(
            jsonEncode({
              'id': 'v-spec',
              'make': 'BMW',
              'model': 'M3',
              'year': 2023,
              'color': null,
              'power_kw': 375,
              'drivetrain': 'RWD',
              'displacement': 2993,
              'transmission_type': 'manual',
            }),
            200,
          ));
      final container = _containerWith(recorder: rec);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: _screen(),
      ));
      await tester.pumpAndSettle();

      final powerField = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('vehicle-power-kw')),
          matching: find.byType(EditableText),
        ),
      );
      expect(powerField.controller.text, '375');

      final dispField = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('vehicle-displacement')),
          matching: find.byType(EditableText),
        ),
      );
      expect(dispField.controller.text, '2993');
    });

    testWidgets('spec fields appear in form for new vehicle', (tester) async {
      final rec = _RecordingClient((_) async => http.Response('null', 200));
      final container = _containerWith(recorder: rec);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: _screen(),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('vehicle-power-kw')), findsOneWidget);
      expect(find.byKey(const ValueKey('vehicle-displacement')), findsOneWidget);
      expect(find.byKey(const ValueKey('vehicle-drivetrain')), findsOneWidget);
      expect(find.byKey(const ValueKey('vehicle-transmission')), findsOneWidget);
    });

    test('VehicleProfile remains untouched (sanity)', () {
      const v = VehicleProfile(id: 'v', make: 'X', model: 'Y');
      expect(v.headline, 'X Y');
    });
  });
}
