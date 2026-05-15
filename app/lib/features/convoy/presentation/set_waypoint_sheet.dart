import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/gps_update.dart';
import '../../../core/theme/app_theme.dart';
import '../application/convoy_providers.dart';
import '../application/waypoint_providers.dart';
import '../domain/waypoint.dart';

/// Modaler Bottom-Sheet — Leader setzt einen Navigationspunkt.
///
/// MVP: setzt die aktuelle GPS-Position als Ziel mit optionalem Label.
/// Spätere Iteration ergänzt: Adress-Suche (Geocoding) und Map-Tap-Auswahl.
class SetWaypointSheet extends ConsumerStatefulWidget {
  const SetWaypointSheet({super.key});

  @override
  ConsumerState<SetWaypointSheet> createState() => _SetWaypointSheetState();
}

class _SetWaypointSheetState extends ConsumerState<SetWaypointSheet> {
  final _labelCtrl = TextEditingController();

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(waypointProvider);
    final selfId = ref.watch(selfMemberIdProvider);
    final positions = ref.watch(livePositionsProvider).valueOrNull;
    final selfPos = positions?[selfId];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surfaceOutline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'NAVIGATION',
              style: AppTextStyles.sectionLabel,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Navigationspunkt setzen',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Setzt ein Ziel für alle Mitglieder.\n'
              'Erscheint sofort als Banner mit Distanz + Richtung.',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            TextField(
              key: const ValueKey('waypoint-label-input'),
              controller: _labelCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'z. B. Tankstelle Müller',
                labelText: 'Beschreibung (optional)',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              key: const ValueKey('waypoint-set-from-position'),
              icon: const Icon(Icons.my_location_rounded),
              label: Text(
                selfPos == null
                    ? 'Warte auf GPS …'
                    : 'Aktuelle Position als Ziel',
              ),
              onPressed: selfPos == null ? null : () => _set(selfPos, selfId),
            ),
            if (current != null) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                key: const ValueKey('waypoint-clear'),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Ziel entfernen'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger, width: 1.4),
                ),
                onPressed: _clear,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _set(GpsUpdate self, String selfId) {
    final label = _labelCtrl.text.trim();
    ref.read(tourProvider.notifier).addStop(
          Waypoint(
            latitude: self.latitude,
            longitude: self.longitude,
            label: label.isEmpty ? 'Treffpunkt' : label,
            setBy: selfId,
            setAt: DateTime.now().toUtc(),
          ),
        );
    Navigator.of(context).pop();
  }

  void _clear() {
    ref.read(tourProvider.notifier).clear();
    Navigator.of(context).pop();
  }
}
