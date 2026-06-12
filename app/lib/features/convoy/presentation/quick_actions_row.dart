import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/connection_status.dart';
import '../../../core/theme/app_theme.dart';
import '../application/convoy_providers.dart';
import '../application/quick_action_providers.dart';
import '../domain/quick_action.dart';

/// (icon, color, short label) per quick-action kind — keeps the one-tap row and
/// the received-action banner visually in sync.
({IconData icon, Color color, String label}) _meta(QuickActionKind kind) =>
    switch (kind) {
      QuickActionKind.pause => (
          icon: Icons.local_cafe_rounded,
          color: const Color(0xFFFFC53D),
          label: 'Pause',
        ),
      QuickActionKind.fuelStop => (
          icon: Icons.local_gas_station_rounded,
          color: const Color(0xFF4F8DFD),
          label: 'Tankstopp',
        ),
      QuickActionKind.backInConvoy => (
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF22C55E),
          label: 'Bin zurück',
        ),
      QuickActionKind.vehicleProblem => (
          icon: Icons.build_rounded,
          color: const Color(0xFFE94560),
          label: 'Problem',
        ),
    };

/// One-tap row of the four convoy quick-actions. Each tap broadcasts the action
/// to every member (and echoes it back to the sender via the banner).
class QuickActionsRow extends ConsumerWidget {
  const QuickActionsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        key: const ValueKey('quick-actions-row'),
        children: [
          for (final kind in QuickActionKind.values) ...[
            Expanded(child: _QuickActionButton(kind: kind)),
            if (kind != QuickActionKind.values.last)
              const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _QuickActionButton extends ConsumerWidget {
  const _QuickActionButton({required this.kind});

  final QuickActionKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = _meta(kind);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('quick-action-${kind.wireValue}'),
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: () {
          ref.read(quickActionProvider.notifier).send(kind);
          // Ehrliches Feedback: Status-Frames sind fire-and-forget (bewusst
          // KEINE Offline-Queue — eine nachgesendete, veraltete Schnellaktion
          // wäre irreführend). Ohne Verbindung also keinen Erfolg behaupten.
          final connected = ref.read(convoySocketProvider)?.currentStatus ==
              ConnectionStatus.connected;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 2),
              content: Text(
                connected
                    ? '„${m.label}" an den Konvoi gesendet'
                    : 'Keine Verbindung — „${m.label}" wurde nicht gesendet.',
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: m.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadii.card),
            border:
                Border.all(color: m.color.withValues(alpha: 0.5), width: 0.8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(m.icon, color: m.color, size: 22),
              const SizedBox(height: 3),
              Text(
                m.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: m.color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Transient banner for the latest quick-action broadcast (own or received).
class QuickActionBanner extends ConsumerWidget {
  const QuickActionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(quickActionProvider);
    if (action == null) return const SizedBox.shrink();
    final m = _meta(action.kind);
    final selfId = ref.watch(selfMemberIdProvider);
    final convoy = ref.watch(currentConvoyProvider);
    final isSelf = action.memberId == selfId;
    final name = isSelf
        ? 'Du'
        : (convoy?.members
                .where((mem) => mem.id == action.memberId)
                .firstOrNull
                ?.displayName ??
            action.memberId);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        key: const ValueKey('quick-action-banner'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: m.color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(
            color: m.color.withValues(alpha: 0.5),
            width: AppBorders.hairline,
          ),
        ),
        child: Row(
          children: [
            Icon(m.icon, color: m.color, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '$name · ${m.label}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
