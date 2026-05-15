import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../push_to_talk/application/ptt_providers.dart';
import '../../push_to_talk/presentation/ptt_button.dart';
import '../application/convoy_providers.dart';

/// Bottom-Bar in der ActiveConvoy-View. Drei Slots:
///   • Links:  Pillen-Counter "X im Konvoi" (tap → Member-Sheet, später)
///   • Mitte:  großer Push-to-Talk-Button
///   • Rechts: kreisförmiger Leave-Konvoi-Button (rot)
///
/// Höhe ~104 px damit der PTT in der iOS-Tap-Zone liegt.
/// Designvorlage: Design.pdf Frame 5/6 (Bottom-Action-Row).
class ActiveConvoyActionBar extends ConsumerWidget {
  const ActiveConvoyActionBar({
    super.key,
    required this.memberCount,
    required this.onLeave,
  });

  final int memberCount;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pttActive = ref.watch(pttActiveProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: _MemberCountPill(count: memberCount)),
          const SizedBox(width: AppSpacing.md),
          PttButton(size: pttActive ? 84 : 76),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: _LeaveButton(onLeave: onLeave)),
        ],
      ),
    );
  }
}

class _MemberCountPill extends StatelessWidget {
  const _MemberCountPill({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.surfaceOutline, width: 0.8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.people_alt_rounded,
              color: AppColors.orange, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              '$count im Konvoi',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaveButton extends StatelessWidget {
  const _LeaveButton({required this.onLeave});
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('leave-convoy-action'),
        onTap: () => _confirm(context),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.dangerSurface,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: AppColors.danger, width: 1.2),
          ),
          child: const Icon(
            Icons.logout_rounded,
            color: AppColors.danger,
            size: 22,
          ),
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Konvoi verlassen?'),
        content: const Text(
          'Du verlierst die Live-Übersicht und bekommst keine '
          'Abstandswarnungen mehr. Code-Beitritt bleibt möglich.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Verlassen'),
          ),
        ],
      ),
    );
    if (ok == true) onLeave();
  }
}
