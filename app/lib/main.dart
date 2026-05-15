import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app/crew_link_app.dart';
import 'core/firebase/firebase_options.dart';
import 'core/models/gps_update.dart';
import 'core/notifications/notification_service.dart';
import 'core/observability/analytics_service.dart';
import 'core/observability/app_logger.dart';
import 'core/observability/funnel_analytics.dart';
import 'core/observability/observability_bootstrap.dart';
import 'features/auth/application/auth_providers.dart';
import 'features/convoy/application/convoy_providers.dart';
import 'core/location/location_permission_service.dart';

const _sentryDsn = String.fromEnvironment('SENTRY_DSN');
const _sentryRelease = String.fromEnvironment(
  'CREW_LINK_RELEASE',
  defaultValue: 'crew_link@0.1.0+1',
);
const _sentryEnv = String.fromEnvironment(
  'CREW_LINK_ENV',
  defaultValue: 'dev',
);

@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  final svc = LocalNotificationService();
  await svc.init();
  final data = message.data;
  await svc.show(
    id: (message.messageId ?? '').hashCode.abs() % 100000,
    title: data['title'] as String? ?? 'Konvoi-Warnung',
    body: data['body'] as String? ?? '',
  );
}

Stream<GpsUpdate> _simulatedLocationStream(String memberId) async* {
  double lat = 48.1374;
  double lng = 11.5755;
  double heading = 90.0;
  int step = 0;
  while (true) {
    await Future<void>.delayed(const Duration(seconds: 3));
    step++;
    if (step % 40 < 10) {
      lng += 0.00008;
      heading = 90;
    } else if (step % 40 < 20) {
      lat -= 0.00008;
      heading = 180;
    } else if (step % 40 < 30) {
      lng -= 0.00008;
      heading = 270;
    } else {
      lat += 0.00008;
      heading = 0;
    }
    yield GpsUpdate(
      memberId: memberId,
      latitude: lat,
      longitude: lng,
      headingDegrees: heading,
      speedMps: 8.3,
      timestamp: DateTime.now(),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await AnalyticsService.instance.logAppOpen();
    await FunnelAnalytics.init();
    // Request location permission early so the GPS producer starts
    // immediately when the user joins their first convoy.
    await LocationPermissionService.requestForConvoy();
  }

  // Always build — uses NullCrashReporter on web, Crashlytics on mobile.
  // Must be called after Firebase.initializeApp() (already done above for !kIsWeb).
  ObservabilityBootstrap.build().install();

  if (_sentryDsn.isEmpty) {
    appLog.w('[Sentry] SENTRY_DSN not set — crash reporting disabled');
  }

  await SentryFlutter.init(
    (options) {
      options.dsn = _sentryDsn;
      options.release = _sentryRelease;
      options.environment = _sentryEnv;
      // dist = build number; feeds Sentry Release Health adoption graph.
      options.dist = const String.fromEnvironment(
        'CREW_LINK_BUILD_NUMBER',
        defaultValue: '1',
      );
      options.tracesSampleRate = 0.1;
      options.enableAutoSessionTracking = true;
      options.autoSessionTrackingInterval = const Duration(seconds: 30);
      options.attachStacktrace = true;
      options.sendDefaultPii = false;
      options.maxBreadcrumbs = 50;
    },
    appRunner: () => runApp(
      ProviderScope(
        overrides: [
          authTokenProvider.overrideWith((ref) {
            return ref.watch(authIdTokenProvider).valueOrNull ?? '';
          }),
          selfMemberIdProvider.overrideWith((ref) {
            return ref.watch(signedInUidProvider);
          }),
          if (kIsWeb)
            selfLocationStreamProvider.overrideWith(
              (_) => _simulatedLocationStream('web-preview-user'),
            ),
        ],
        child: const CrewLinkApp(),
      ),
    ),
  );
}
