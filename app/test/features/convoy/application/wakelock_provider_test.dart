import 'package:crew_link/core/models/convoy.dart';
import 'package:crew_link/core/observability/crash_reporter.dart';
import 'package:crew_link/core/observability/observability_bootstrap.dart';
import 'package:crew_link/features/convoy/application/convoy_providers.dart';
import 'package:crew_link/features/convoy/application/wakelock_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWakelock implements WakelockControl {
  final calls = <String>[];

  @override
  Future<void> enable() async => calls.add('enable');

  @override
  Future<void> disable() async => calls.add('disable');
}

Convoy _convoy() => Convoy(
      id: 'c1',
      name: 'Trip',
      inviteCode: 'ABC123',
      members: const [],
      proximityWarningMeters: 500,
      createdAt: DateTime.utc(2026, 5, 13, 12),
    );

/// Lets the queued `unawaited(apply(...))` futures run.
Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  setUpAll(() {
    ObservabilityBootstrap.build(overrideForTesting: const NullCrashReporter());
  });

  group('convoyWakelockProvider', () {
    test('enables the wakelock while a convoy is active', () async {
      final fake = _FakeWakelock();
      final container = ProviderContainer(overrides: [
        wakelockControlProvider.overrideWithValue(fake),
      ]);
      addTearDown(container.dispose);
      container.read(currentConvoyProvider.notifier).state = _convoy();

      container.listen<void>(convoyWakelockProvider, (_, __) {});
      await _flush();

      expect(fake.calls, contains('enable'));
    });

    test('disables the wakelock when the convoy is left', () async {
      final fake = _FakeWakelock();
      final container = ProviderContainer(overrides: [
        wakelockControlProvider.overrideWithValue(fake),
      ]);
      addTearDown(container.dispose);
      container.read(currentConvoyProvider.notifier).state = _convoy();

      container.listen<void>(convoyWakelockProvider, (_, __) {});
      await _flush();
      fake.calls.clear();

      container.read(currentConvoyProvider.notifier).state = null;
      await _flush();

      expect(fake.calls, contains('disable'));
      expect(fake.calls, isNot(contains('enable')));
    });

    test('disables the wakelock when the provider is disposed', () async {
      final fake = _FakeWakelock();
      final container = ProviderContainer(overrides: [
        wakelockControlProvider.overrideWithValue(fake),
      ]);
      container.read(currentConvoyProvider.notifier).state = _convoy();

      container.listen<void>(convoyWakelockProvider, (_, __) {});
      await _flush();
      fake.calls.clear();

      container.dispose();
      await _flush();

      expect(fake.calls, contains('disable'));
    });

    test('stays off while no convoy is active', () async {
      final fake = _FakeWakelock();
      final container = ProviderContainer(overrides: [
        wakelockControlProvider.overrideWithValue(fake),
      ]);
      addTearDown(container.dispose);

      container.listen<void>(convoyWakelockProvider, (_, __) {});
      await _flush();

      expect(fake.calls, isNot(contains('enable')));
    });
  });
}
