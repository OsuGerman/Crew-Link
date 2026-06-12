import 'package:crew_link/core/models/convoy.dart';
import 'package:crew_link/core/observability/crash_reporter.dart';
import 'package:crew_link/core/observability/observability_bootstrap.dart';
import 'package:crew_link/features/convoy/presentation/invite_share.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Convoy _convoy() => Convoy(
      id: 'c1',
      name: 'Schwarzwald Sonntag',
      inviteCode: 'ABC123',
      members: const [],
      proximityWarningMeters: 500,
      createdAt: DateTime.utc(2026, 5, 13, 12),
    );

class _Harness extends ConsumerWidget {
  const _Harness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const ValueKey('share-btn'),
          onPressed: () => shareConvoyInvite(
            context,
            ref,
            convoy: _convoy(),
            fallbackClipboardText: 'fallback-clip',
            fallbackSnackbarText: 'fallback-snack',
          ),
          child: const Text('share'),
        ),
      ),
    );
  }
}

Widget _app(ShareLauncher launcher) => ProviderScope(
      overrides: [shareLauncherProvider.overrideWithValue(launcher)],
      child: const MaterialApp(home: _Harness()),
    );

void main() {
  setUpAll(() {
    ObservabilityBootstrap.build(overrideForTesting: const NullCrashReporter());
  });

  group('shareConvoyInvite', () {
    testWidgets('passes name + code + store link to the share sheet',
        (tester) async {
      String? shared;
      await tester.pumpWidget(_app((text) async => shared = text));

      await tester.tap(find.byKey(const ValueKey('share-btn')));
      await tester.pump();

      expect(
        shared,
        'Fahr mit im Konvoi Schwarzwald Sonntag — Code ABC123. '
        'App: $kPlayStoreUrl',
      );
      // Erfolgsfall: kein Fallback-Snackbar.
      expect(find.text('fallback-snack'), findsNothing);
    });

    testWidgets('falls back to clipboard + snackbar when sharing fails',
        (tester) async {
      final clipboardWrites = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardWrites.add(
              (call.arguments as Map<Object?, Object?>)['text'] as String?,
            );
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.pumpWidget(
        _app((text) async => throw StateError('no share sheet')),
      );

      await tester.tap(find.byKey(const ValueKey('share-btn')));
      await tester.pump();
      await tester.pump();

      expect(clipboardWrites, ['fallback-clip']);
      expect(find.text('fallback-snack'), findsOneWidget);
    });
  });
}
