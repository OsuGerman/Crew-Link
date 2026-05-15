import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/carplay/carplay_providers.dart';
import '../../../core/models/convoy.dart';
import '../../../core/models/gps_update.dart';
import '../../push_to_talk/application/ptt_providers.dart';
import '../../push_to_talk/presentation/ptt_button.dart';
import '../application/breach_notification_watcher.dart';
import '../application/convoy_providers.dart';
import '../application/convoy_split_watcher.dart';
import '../application/lost_connection_watcher.dart';
import '../domain/convoy_split_event.dart';
import '../domain/proximity_warning.dart';
import 'connection_status_banner.dart';
import 'convoy_member_list.dart';
import 'convoy_radar_view.dart';
import 'lost_connection_banner.dart';

/// Normal (non-Driver-Mode) active-convoy view. Scrollable so growing
/// member lists / future banner additions don't overflow on small
/// devices.
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
  // Prevents multiple split dialogs from stacking simultaneously.
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
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            convoy.name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Einladungscode: ${convoy.inviteCode}',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Abstandswarnung: ${convoy.proximityWarningMeters.toStringAsFixed(0)} m',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const ConnectionStatusBanner(),
          const LostConnectionBanner(),
          _ProximityBanner(warning: warning),
          const SizedBox(height: 16),
          Consumer(
            builder: (context, innerRef, _) {
              final snapshot =
                  positions.valueOrNull ?? const <String, GpsUpdate>{};
              return ConvoyRadarView(
                selfMemberId: innerRef.watch(selfMemberIdProvider),
                positions: snapshot,
                thresholdMeters: convoy.proximityWarningMeters,
              );
            },
          ),
          const SizedBox(height: 16),
          Consumer(
            builder: (context, innerRef, _) {
              final snapshot =
                  positions.valueOrNull ?? const <String, GpsUpdate>{};
              return ConvoyMemberList(
                convoy: convoy,
                positions: snapshot,
                selfMemberId: innerRef.watch(selfMemberIdProvider),
              );
            },
          ),
          const SizedBox(height: 24),
          const Center(child: PttButton()),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const ValueKey('leave-convoy-btn'),
            onPressed: widget.onLeave,
            icon: const Icon(Icons.logout),
            label: const Text('Konvoi verlassen'),
          ),
        ],
      ),
    );
  }
}

class _ProximityBanner extends StatelessWidget {
  const _ProximityBanner({required this.warning});

  final AsyncValue<ProximityWarning> warning;

  @override
  Widget build(BuildContext context) {
    final value = warning.valueOrNull;
    if (value == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('proximity-banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Abstandswarnung: ${value.otherMemberId} ist '
              '${value.distanceMeters.toStringAsFixed(0)} m entfernt',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
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
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.directions_car_filled_rounded,
          color: scheme.error, size: 40),
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
