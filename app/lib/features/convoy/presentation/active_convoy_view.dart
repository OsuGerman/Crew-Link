import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/carplay/carplay_providers.dart';
import '../../../core/models/convoy.dart';
import '../../../core/models/gps_update.dart';
import '../../../core/theme/app_theme.dart';
import '../../push_to_talk/application/ptt_providers.dart';
import '../application/breach_notification_watcher.dart';
import '../application/convoy_providers.dart';
import '../application/convoy_split_watcher.dart';
import '../application/lost_connection_watcher.dart';
import '../domain/convoy_split_event.dart';
import '../domain/proximity_warning.dart';
import 'active_convoy_action_bar.dart';
import 'connection_status_banner.dart';
import 'convoy_member_list.dart';
import 'convoy_radar_view.dart';
import 'convoy_status_header.dart';
import 'hazard_banner_strip.dart';
import 'lost_connection_banner.dart';
import 'waypoint_banner.dart';

/// Active-Convoy-View — Design.pdf Frame 5/6.
/// Layout (von oben nach unten):
///   • Status-Header (Konvoi-Name + Live-Dot + Code-Pill)
///   • Banner-Stack (Connection, LostConnection, Proximity, Waypoint)
///   • Expanded Radar (nimmt den verfügbaren Vertikal-Platz)
///   • Member-Liste kompakt
///   • Fixed Bottom-Bar (Member-Pill · großer PTT · Leave-Icon)
class ActiveConvoyView extends ConsumerStatefulWidget {
  const ActiveConvoyView({
    super.key,
    required this.convoy,
    required this.onLeave,
  });

  final Convoy convoy;
  final VoidCallback onLeave;

  @override
  ConsumerState<ActiveConvoyView> createState() => _ActiveConvoyViewState();
}

class _ActiveConvoyViewState extends ConsumerState<ActiveConvoyView> {
  bool _splitDialogOpen = false;

  @override
  Widget build(BuildContext context) {
    final convoy = widget.convoy;
    ref.watch(breachNotificationWatcherProvider);
    ref.watch(convoySplitWatcherProvider);
    ref.watch(pttFrameRoutingProvider(convoy.id));
    ref.watch(pttReceiverProvider(convoy.id));
    ref.watch(pttPlaybackProvider(convoy.id));
    ref.watch(carPlayPttWiringProvider);
    ref.watch(lostConnectionWatcherProvider);
    ref.listen<ConvoySplitEvent?>(activeSplitProvider, (_, event) {
      if (event == null || _splitDialogOpen) return;
      _splitDialogOpen = true;
      final name = convoy.members
              .where((m) => m.id == event.splitMemberId)
              .firstOrNull
              ?.displayName ??
          event.splitMemberId;
      showDialog<void>(
        context: context,
        builder: (_) => _ConvoySplitDialog(
          memberName: name,
          distanceMeters: event.distanceMeters,
        ),
      ).whenComplete(() => _splitDialogOpen = false);
    });
    final warning = ref.watch(proximityWarningsProvider);
    final positions = ref.watch(livePositionsProvider);
    final snapshot = positions.valueOrNull ?? const <String, GpsUpdate>{};
    final selfId = ref.watch(selfMemberIdProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConvoyStatusHeader(convoy: convoy),
        const ConnectionStatusBanner(),
        const LostConnectionBanner(),
        _ProximityBanner(warning: warning),
        const WaypointBanner(),
        const SizedBox(height: AppSpacing.md),
        const HazardBannerStrip(),
        Expanded(
          child: ConvoyRadarView(
            selfMemberId: selfId,
            positions: snapshot,
            thresholdMeters: convoy.proximityWarningMeters,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ConvoyMemberList(
          convoy: convoy,
          positions: snapshot,
          selfMemberId: selfId,
        ),
        ActiveConvoyActionBar(
          memberCount: convoy.members.length,
          onLeave: widget.onLeave,
        ),
      ],
    );
  }
}

/// Roter Abstands-Banner — bleibt im neuen Design erhalten, neuer Style.
class _ProximityBanner extends StatelessWidget {
  const _ProximityBanner({required this.warning});

  final AsyncValue<ProximityWarning> warning;

  @override
  Widget build(BuildContext context) {
    final value = warning.valueOrNull;
    if (value == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        key: const ValueKey('proximity-banner'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.dangerSurface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: AppColors.danger, width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.danger,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ABSTAND',
                    style: AppTextStyles.sectionLabel.copyWith(
                      fontSize: 10,
                      color: AppColors.danger,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${value.otherMemberId} · '
                    '${value.distanceMeters.toStringAsFixed(0)} m entfernt',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConvoySplitDialog extends StatelessWidget {
  const _ConvoySplitDialog({
    required this.memberName,
    required this.distanceMeters,
  });

  final String memberName;
  final double distanceMeters;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(
        Icons.directions_car_filled_rounded,
        color: AppColors.danger,
        size: 40,
      ),
      title: const Text('Konvoi getrennt!'),
      content: Text(
        '$memberName ist seit über ${ConvoySplitEvent.kSustainedSeconds} s '
        'von der Gruppe getrennt '
        '(${distanceMeters.toStringAsFixed(0)} m entfernt).\n\n'
        'Bitte auf den Rest des Konvois warten.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Verstanden'),
        ),
      ],
    );
  }
}
