import 'package:crew_link/core/observability/crash_reporter.dart';
import 'package:crew_link/core/observability/observability_bootstrap.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ObservabilityBootstrap.reportError', () {
    test('delegates to wrapped reporter', () async {
      final recording = _RecordingReporter();
      final bootstrap = ObservabilityBootstrap(recording);
      await bootstrap.reportError(
        StateError('test'),
        StackTrace.current,
        fatal: true,
        tags: {'k': 'v'},
      );
      expect(recording.errorCalls, 1);
      expect(recording.lastFatal, isTrue);
    });

    test('non-fatal errors are forwarded with fatal=false', () async {
      final recording = _RecordingReporter();
      final bootstrap = ObservabilityBootstrap(recording);
      await bootstrap.reportError(Exception('minor'), StackTrace.current);
      expect(recording.lastFatal, isFalse);
    });
  });

  group('ObservabilityBootstrap.install', () {
    late FlutterExceptionHandler? prevFlutterError;
    late ErrorCallback? prevDispatcherError;

    setUp(() {
      prevFlutterError = FlutterError.onError;
      prevDispatcherError = PlatformDispatcher.instance.onError;
    });

    tearDown(() {
      FlutterError.onError = prevFlutterError;
      PlatformDispatcher.instance.onError = prevDispatcherError;
    });

    test('wires FlutterError.onError to reporter', () async {
      final recording = _RecordingReporter();
      ObservabilityBootstrap(recording).install();

      FlutterError.onError!(
        FlutterErrorDetails(exception: StateError('flutter-err')),
      );

      // recordError is async; pump the microtask queue
      await Future<void>.delayed(Duration.zero);

      expect(recording.errorCalls, 1);
      expect(recording.lastFatal, isTrue);
    });

    test('wires PlatformDispatcher.onError to reporter', () async {
      final recording = _RecordingReporter();
      ObservabilityBootstrap(recording).install();

      final handled = PlatformDispatcher.instance.onError!(
        StateError('platform-err'),
        StackTrace.current,
      );

      await Future<void>.delayed(Duration.zero);

      expect(handled, isTrue);
      expect(recording.errorCalls, 1);
    });
  });
}

class _RecordingReporter implements CrashReporter {
  int errorCalls = 0;
  bool lastFatal = false;

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    Map<String, Object?> tags = const {},
  }) async {
    errorCalls++;
    lastFatal = fatal;
  }

  @override
  Future<void> setUser({required String memberId}) async {}
}
