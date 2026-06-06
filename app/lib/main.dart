import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app/crew_link_app.dart';
import 'core/firebase/firebase_options.dart';
import 'core/location/location_permission_service.dart';
import 'core/models/gps_update.dart';
import 'core/notifications/notification_service.dart';
import 'core/observability/analytics_service.dart';
import 'core/observability/app_logger.dart';
import 'core/observability/funnel_analytics.dart';
import 'core/observability/observability_bootstrap.dart';
import 'core/privacy/diagnostics_consent.dart';
import 'features/auth/application/auth_providers.dart';
import 'features/convoy/application/convoy_providers.dart';

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
  // Sentry wraps runApp in its own error-capturing zone (appRunner). Use
  // Sentry's binding so the bindings initialise in that same zone — otherwise
  // Flutter asserts "Zone mismatch" in debug (e.g. web), and Sentry can't
  // reliably capture zone-scoped errors in release.
  SentryWidgetsFlutterBinding.ensureInitialized();

  // GDPR: analytics + crash diagnostics are opt-in. Load the stored choice
  // (defaults to OFF / undecided) before anything reports, and propagate it to
  // the observability bootstrap so manual reportError calls respect it too.
  final consent = await DiagnosticsConsent.load();
  ObservabilityBootstrap.diagnosticsEnabled = consent.enabled;

  // Firebase has a real Web config too → initialise on every platform so the
  // Web build (main.dart on Chrome) can use Auth. FCM, Analytics and the
  // location-permission prompt stay native-only below.
  var firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;
  } catch (error, stack) {
    // Guard against placeholder/missing config so a failed init never crashes
    // the start — Firebase-dependent features just stay disabled.
    appLog.e(
      'Firebase.initializeApp fehlgeschlagen — Firebase-Features deaktiviert',
      error: error,
      stackTrace: stack,
    );
    try {
      await ObservabilityBootstrap.build().reportError(error, stack);
    } catch (_) {/* kein funktionierender Reporter vor dem Start */}
  }

  // Push notifications (proximity/breach alerts) are a feature, gated by the OS
  // permission prompt — not by the diagnostics consent. Firebase Analytics +
  // Crashlytics collection follow the consent (OFF by default).
  if (!kIsWeb && firebaseReady) {
    await applyDiagnosticsConsent(consent.enabled);
    FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
    // alert/badge/sound default to true; request push permission for alerts.
    await FirebaseMessaging.instance.requestPermission();
    if (consent.enabled) {
      await AnalyticsService.instance.logAppOpen();
    }
  }
  if (!kIsWeb) {
    if (consent.enabled) {
      await FunnelAnalytics.init();
    }
    // Request location permission early so the GPS producer starts immediately
    // when the user joins their first convoy.
    await LocationPermissionService.requestForConvoy();
  }

  // Crashlytics braucht ein initialisiertes Firebase; auf Web liefert build()
  // den NullCrashReporter (immer sicher). Bei fehlgeschlagenem Firebase-Init
  // überspringen, sonst crasht FirebaseCrashlytics.instance hier erneut.
  // Crash hooks only when the user consented to diagnostics.
  if (consent.enabled && (kIsWeb || firebaseReady)) {
    ObservabilityBootstrap.build().install();
  }

  Widget appRoot() => ProviderScope(
        overrides: [
          authTokenProvider.overrideWith((ref) {
            return ref.watch(authIdTokenProvider).valueOrNull ?? '';
          }),
          selfMemberIdProvider.overrideWith((ref) {
            return ref.watch(signedInUidProvider);
          }),
          if (kIsWeb)
            selfLocationStreamProvider.overrideWith(
              (_) => _simulatedLocationStream('web-preview-user')
                  .asBroadcastStream(),
            ),
        ],
        child: const CrewLinkApp(),
      );

  // Sentry only runs when the user consented to diagnostics; otherwise the app
  // starts without the Sentry error zone.
  if (consent.enabled) {
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
      appRunner: () => runApp(appRoot()),
    );
  } else {
    runApp(appRoot());
  }
}
