import 'dart:async';

import 'package:crew_link/features/convoy/data/gps_producer.dart';
import 'package:crew_link/features/convoy/data/gps_producer_lifecycle_observer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

/// Records background setter calls without running real geolocator streams.
class _FakeGpsProducer extends GpsProducer {
  int backgroundSetCount = 0;
  bool? lastBackground;

  _FakeGpsProducer()
      : super(
          memberId: 'fake',
          streamFactory: (_) => StreamController<Position>.broadcast().stream,
          settingsFactory: (_) =>
              const LocationSettings(accuracy: LocationAccuracy.low),
        );

  @override
  set background(bool value) {
    backgroundSetCount++;
    lastBackground = value;
  }
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('GpsProducerLifecycleObserver', () {
    late _FakeGpsProducer producer;
    late GpsProducerLifecycleObserver observer;

    setUp(() {
      producer = _FakeGpsProducer();
      observer = GpsProducerLifecycleObserver(producer);
    });

    tearDown(observer.dispose);

    void sendState(AppLifecycleState s) =>
        observer.didChangeAppLifecycleState(s);

    test('paused → background = true', () {
      sendState(AppLifecycleState.paused);
      expect(producer.lastBackground, isTrue);
    });

    test('hidden → background = true', () {
      sendState(AppLifecycleState.hidden);
      expect(producer.lastBackground, isTrue);
    });

    test('detached → background = true', () {
      sendState(AppLifecycleState.detached);
      expect(producer.lastBackground, isTrue);
    });

    test('resumed → background = false', () {
      sendState(AppLifecycleState.resumed);
      expect(producer.lastBackground, isFalse);
    });

    test('inactive does not touch background setter', () {
      final before = producer.backgroundSetCount;
      sendState(AppLifecycleState.inactive);
      expect(producer.backgroundSetCount, before,
          reason: 'inactive is transitional — background must not change');
    });

    test('dispose is idempotent — no throw on double call', () {
      expect(() {
        observer.dispose();
        observer.dispose();
      }, returnsNormally);
    });
  });
}
