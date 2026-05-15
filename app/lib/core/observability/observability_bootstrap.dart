import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'crash_reporter.dart';

class ObservabilityBootstrap {
  ObservabilityBootstrap._({
    required CrashReporter installReporter,
    required CrashReporter reporter,
  })  : _installReporter = installReporter,
        _reporter = reporter;

  /// Crashlytics-only — used by FlutterError / PlatformDispatcher hooks.
  /// Sentry intercepts those channels separately after SentryFlutter.init(),
  /// so we must NOT include SentryReporter here to avoid double-reporting.
  final CrashReporter _installReporter;

  /// Multi-reporter (Crashlytics + Sentry) — used by manual reportError calls.
  final CrashReporter _reporter;

  static ObservabilityBootstrap? _instance;

  /// Singleton created by [build]; accessible app-wide for setUser / reportError.
  static ObservabilityBootstrap get current {
    assert(_instance != null, 'Call ObservabilityBootstrap.build() first');
    return _instance!;
  }

  static ObservabilityBootstrap build({
    FirebaseCrashlytics? crashlytics,
    @visibleForTesting CrashReporter? overrideForTesting,
  }) {
    // Return cached instance when called without args (e.g. from error handlers)
    // to avoid re-initialising Firebase plugins on every catch block.
    if (overrideForTesting == null && crashlytics == null && _instance != null) {
      return _instance!;
    }
    final CrashReporter cl;
    if (overrideForTesting != null) {
      cl = overrideForTesting;
    } else if (kIsWeb) {
      cl = const NullCrashReporter();
    } else {
      cl = CrashlyticsReporter(crashlytics ?? FirebaseCrashlytics.instance);
    }
    _instance = ObservabilityBootstrap._(
      installReporter: cl,
      reporter: MultiCrashReporter([cl, SentryReporter()]),
    );
    return _instance!;
  }

  /// Wires Crashlytics into Flutter's error hooks.
  /// Call BEFORE SentryFlutter.init() — Sentry then wraps and chains back here.
  void install() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _installReporter.recordError(
        details.exception,
        details.stack,
        fatal: true,
        tags: const {'source': 'FlutterError'},
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      _installReporter.recordError(
        error,
        stack,
        fatal: true,
        tags: const {'source': 'PlatformDispatcher'},
      );
      return true;
    };
  }

  /// Reports to both Crashlytics and Sentry (if Sentry is initialized).
  Future<void> reportError(
    Object error,
    StackTrace stack, {
    bool fatal = false,
    Map<String, Object?> tags = const {},
  }) =>
      _reporter.recordError(error, stack, fatal: fatal, tags: tags);

  /// Sets the current user in both Crashlytics and Sentry.
  /// Call after successful sign-in.
  Future<void> setUser({required String memberId}) =>
      _reporter.setUser(memberId: memberId);
}
