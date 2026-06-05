import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/convoy.dart';
import '../../../core/models/gps_update.dart';
import '../../../core/models/hazard_report.dart';
import '../../../core/theme/app_theme.dart';
import '../application/convoy_providers.dart';
import '../application/hazard_providers.dart';

/// Quick-Sheet zum Melden einer Gefahr. 1-Tap pro Kategorie → posiert ein
/// Hazard-Pin an der eigenen GPS-Position für alle Konvoi-Member sichtbar.
class HazardQuickSheet extends ConsumerWidget {
  const HazardQuickSheet({super.key, required this.convoy});

  final Convoy convoy;

  /// Reihenfolge orientiert sich an Häufigkeit + Dringlichkeit beim Cruisen.
  static const _categories = <_HazardOption>[
    _HazardOption(HazardType.trafficJam, 'Stau', Icons.traffic_rounded,
        Color(0xFFE94560)),
    _HazardOption(HazardType.accident, 'Unfall',
        Icons.car_crash_rounded, Color(0xFFFF6B2C)),
    _HazardOption(HazardType.construction, 'Baustelle',
        Icons.construction_rounded, Color(0xFFFFC53D)),
    _HazardOption(HazardType.obstacle, 'Hindernis',
        Icons.warning_amber_rounded, Color(0xFFFFC53D)),
    _HazardOption(HazardType.slipperyRoad, 'Glatte Fahrbahn',
        Icons.water_drop_rounded, Color(0xFF4F8DFD)),
    _HazardOption(HazardType.poorVisibility, 'Sicht schlecht',
        Icons.foggy, Color(0xFF6B6B73)),
    _HazardOption(HazardType.brokenDownVehicle, 'Pannenfahrzeug',
        Icons.directions_car_filled_rounded, Color(0xFFA855F7)),
    _HazardOption(HazardType.policeCheckpoint, 'Polizei',
        Icons.local_police_rounded, Color(0xFF06B6D4)),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selfId = ref.watch(selfMemberIdProvider);
    final positions = ref.watch(livePositionsProvider).valueOrNull;
    final selfPos = positions?[selfId];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xl,
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
            const Text(
              'GEFAHR MELDEN',
              style: AppTextStyles.sectionLabel,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Was siehst du?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Pin bleibt 30 Min sichtbar für alle Mitglieder.\n'
              'StVO-konform — keine Blitzer/Tempomessungen.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (selfPos == null)
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.gps_off_rounded,
                        color: AppColors.warning, size: 18),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Warte auf GPS — Hazard kann erst nach erster\n'
                        'Positions-Übertragung gemeldet werden.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              _SosHoldButton(
                onTriggered: () => _reportSos(context, ref, selfPos, selfId),
              ),
              const SizedBox(height: AppSpacing.lg),
              GridView.count(
                key: const ValueKey('hazard-quick-grid'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 4,
                crossAxisSpacing: AppSpacing.sm,
                mainAxisSpacing: AppSpacing.sm,
                childAspectRatio: 0.86,
                children: [
                  for (final opt in _categories)
                    _HazardCategoryTile(
                      option: opt,
                      onTap: () => _report(context, ref, opt, selfPos, selfId),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _report(
    BuildContext context,
    WidgetRef ref,
    _HazardOption opt,
    GpsUpdate selfPos,
    String selfId,
  ) {
    ref.read(hazardPingsProvider.notifier).report(
          type: opt.type,
          latitude: selfPos.latitude,
          longitude: selfPos.longitude,
          reporterId: selfId,
          convoyId: convoy.id,
        );
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(opt.icon, color: opt.color, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('${opt.label} gemeldet')),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _reportSos(
    BuildContext context,
    WidgetRef ref,
    GpsUpdate selfPos,
    String selfId,
  ) {
    ref.read(hazardPingsProvider.notifier).report(
          type: HazardType.sos,
          latitude: selfPos.latitude,
          longitude: selfPos.longitude,
          reporterId: selfId,
          convoyId: convoy.id,
        );
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppColors.danger,
        content: Row(
          children: [
            Icon(Icons.sos_rounded, color: Colors.white),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'SOS an alle gesendet — deine Position wurde geteilt.',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hold-3-seconds SOS trigger — broadcasts the user's position as an SOS to all
/// convoy members. The hold + progress fill guards against accidental taps.
class _SosHoldButton extends StatefulWidget {
  const _SosHoldButton({required this.onTriggered});

  final VoidCallback onTriggered;

  @override
  State<_SosHoldButton> createState() => _SosHoldButtonState();
}

class _SosHoldButtonState extends State<_SosHoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed && !_fired) {
          _fired = true;
          widget.onTriggered();
        }
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _cancel() {
    if (!_fired) _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        _fired = false;
        _ctrl.forward(from: 0);
      },
      onTapUp: (_) => _cancel(),
      onTapCancel: _cancel,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final p = _ctrl.value;
          final secondsLeft = ((1 - p) * 3).ceil();
          return Container(
            key: const ValueKey('sos-hold-button'),
            height: 60,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: AppColors.danger, width: 1.4),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: p,
                  child: ColoredBox(
                    color: AppColors.danger.withValues(alpha: 0.4),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.sos_rounded, color: AppColors.danger),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      p > 0 && p < 1
                          ? 'Halten … ${secondsLeft}s'
                          : 'SOS · 3 Sek. halten',
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HazardOption {
  const _HazardOption(this.type, this.label, this.icon, this.color);
  final HazardType type;
  final String label;
  final IconData icon;
  final Color color;
}

class _HazardCategoryTile extends StatelessWidget {
  const _HazardCategoryTile({required this.option, required this.onTap});
  final _HazardOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('hazard-cat-${option.type.wireValue}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: option.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(
              color: option.color.withValues(alpha: 0.55),
              width: 0.8,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(option.icon, color: option.color, size: 26),
              const SizedBox(height: 4),
              Text(
                option.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: option.color,
                  height: 1.15,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
