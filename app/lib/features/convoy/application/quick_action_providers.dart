import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/quick_action.dart';
import 'convoy_providers.dart';

/// How long a quick-action (own or received) stays visible in the banner.
const Duration kQuickActionVisibleFor = Duration(seconds: 8);

/// Holds the most recent one-tap status broadcast and clears it after
/// [kQuickActionVisibleFor]. Sending echoes locally because the server fanout
/// excludes the original sender, so the sender still sees their own action.
class QuickActionNotifier extends StateNotifier<QuickAction?> {
  QuickActionNotifier(this._ref) : super(null) {
    _bindToSocket();
    _ref.listen(convoySocketProvider, (_, __) => _bindToSocket());
  }

  final Ref _ref;
  StreamSubscription<QuickAction>? _socketSub;
  Timer? _clearTimer;

  void _bindToSocket() {
    _socketSub?.cancel();
    final socket = _ref.read(convoySocketProvider);
    if (socket == null) return;
    _socketSub = socket.quickActions.listen(_show);
  }

  void _show(QuickAction action) {
    state = action;
    _clearTimer?.cancel();
    _clearTimer = Timer(kQuickActionVisibleFor, () {
      if (mounted) state = null;
    });
  }

  /// Broadcasts [kind] from the local user and shows it immediately.
  void send(QuickActionKind kind) {
    final selfId = _ref.read(selfMemberIdProvider);
    final action = QuickAction(
      memberId: selfId,
      kind: kind,
      at: DateTime.now().toUtc(),
    );
    _ref.read(convoySocketProvider)?.publishQuickAction(action);
    _show(action);
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    _clearTimer?.cancel();
    super.dispose();
  }
}

final quickActionProvider =
    StateNotifierProvider<QuickActionNotifier, QuickAction?>(
  QuickActionNotifier.new,
);
