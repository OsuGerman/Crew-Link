import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

abstract class CrashReporter {
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    Map<String, Object?> tags = const {},
  });

  Future<void> setUser({required String memberId});
}

class CrashlyticsReporter implements CrashReporter {
  CrashlyticsReporter(this._crashlytics);

  final FirebaseCrashlytics _crashlytics;

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    Map<String, Object?> tags = const {},
  }) async {
    for (final entry in tags.entries) {
      await _crashlytics.setCustomKey(entry.key, entry.value ?? 'null');
    }
    await _crashlytics.recordError(error, stack, fatal: fatal);
  }

  @override
  Future<void> setUser({required String memberId}) =>
      _crashlytics.setUserIdentifier(memberId);
}

/// Reports to Sentry. No-ops when Sentry is not yet initialized (DSN empty).
class SentryReporter implements CrashReporter {
  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    Map<String, Object?> tags = const {},
  }) async {
    if (!Sentry.isEnabled) return;
    await Sentry.captureException(
      error,
      stackTrace: stack,
      withScope: (scope) {
        scope.level = fatal ? SentryLevel.fatal : SentryLevel.error;
        for (final entry in tags.entries) {
          scope.setTag(entry.key, entry.value?.toString() ?? 'null');
        }
      },
    );
  }

  @override
  Future<void> setUser({required String memberId}) async {
    if (!Sentry.isEnabled) return;
    await Sentry.configureScope(
      (scope) => scope.setUser(SentryUser(id: memberId)),
    );
  }
}

/// No-op reporter for platforms where crash reporting is unsupported (e.g. web).
class NullCrashReporter implements CrashReporter {
  const NullCrashReporter();

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    Map<String, Object?> tags = const {},
  }) async {}

  @override
  Future<void> setUser({required String memberId}) async {}
}

/// Fan-out reporter: forwards every call to all inner reporters in parallel.
class MultiCrashReporter implements CrashReporter {
  const MultiCrashReporter(this._reporters);

  final List<CrashReporter> _reporters;

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    Map<String, Object?> tags = const {},
  }) =>
      Future.wait(
        _reporters.map(
          (r) => r.recordError(error, stack, fatal: fatal, tags: tags),
        ),
      );

  @override
  Future<void> setUser({required String memberId}) =>
      Future.wait(_reporters.map((r) => r.setUser(memberId: memberId)));
}
