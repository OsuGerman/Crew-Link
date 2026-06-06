import 'dart:async';

import 'package:crew_link/core/config/api_config.dart';
import 'package:crew_link/core/realtime/convoy_socket_client.dart';
import 'package:crew_link/features/convoy/application/convoy_providers.dart';
import 'package:crew_link/features/convoy/application/quick_action_providers.dart';
import 'package:crew_link/features/convoy/domain/quick_action.dart';
import 'package:crew_link/features/convoy/presentation/quick_actions_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Socket fake exposing a controllable quick-action stream + capturing sends.
class _FakeSocket extends ConvoySocketClient {
  _FakeSocket()
      : super(
          convoyId: 'c1',
          config: ApiConfig.local(),
          authToken: 'tok',
        );

  final StreamController<QuickAction> _qa =
      StreamController<QuickAction>.broadcast();
  final List<QuickAction> published = [];

  @override
  Stream<QuickAction> get quickActions => _qa.stream;

  @override
  void publishQuickAction(QuickAction action) => published.add(action);

  @override
  Future<void> disconnect() async {
    if (!_qa.isClosed) await _qa.close();
  }
}

ProviderContainer _container(_FakeSocket socket) {
  final container = ProviderContainer(
    overrides: [
      convoySocketProvider.overrideWith((ref) => socket),
      selfMemberIdProvider.overrideWithValue('self'),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('quickActionProvider', () {
    test('received quick-action becomes the current state', () async {
      final socket = _FakeSocket();
      final container = _container(socket);
      container.read(quickActionProvider); // instantiate + bind

      socket._qa.add(QuickAction(
        memberId: 'buddy',
        kind: QuickActionKind.pause,
        at: DateTime.utc(2026, 6, 6),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final state = container.read(quickActionProvider);
      expect(state?.memberId, 'buddy');
      expect(state?.kind, QuickActionKind.pause);
    });

    test('send publishes the action and echoes it locally', () {
      final socket = _FakeSocket();
      final container = _container(socket);

      container
          .read(quickActionProvider.notifier)
          .send(QuickActionKind.fuelStop);

      expect(socket.published.single.kind, QuickActionKind.fuelStop);
      expect(socket.published.single.memberId, 'self');
      expect(container.read(quickActionProvider)?.kind,
          QuickActionKind.fuelStop);
    });
  });

  group('QuickActionsRow', () {
    testWidgets('tapping a button broadcasts that action', (tester) async {
      final socket = _FakeSocket();
      addTearDown(socket.disconnect);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            convoySocketProvider.overrideWith((ref) => socket),
            selfMemberIdProvider.overrideWithValue('self'),
          ],
          child: const MaterialApp(
            home: Scaffold(body: QuickActionsRow()),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('quick-action-back_in_convoy')));
      await tester.pump();

      expect(socket.published.single.kind, QuickActionKind.backInConvoy);
    });
  });
}
