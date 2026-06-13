import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/carplay/carplay_providers.dart';
import '../../../core/location/location_permission_service.dart';
import '../../../core/models/convoy.dart';
import '../../../core/models/gps_update.dart';
import '../../../core/theme/app_theme.dart';
import '../../maps/presentation/convoy_map_widget.dart';
import '../../push_to_talk/application/livekit_ptt_session.dart';
import '../../push_to_talk/application/ptt_providers.dart';
import '../application/breach_notification_watcher.dart';
import '../application/convoy_providers.dart';
import '../application/convoy_split_watcher.dart';
import '../application/lost_connection_watcher.dart';
import '../application/wakelock_provider.dart';
import '../application/waypoint_providers.dart';
import '../domain/convoy_split_event.dart';
import 'active_convoy_action_bar.dart';
import 'connection_status_banner.dart';
import 'convoy_invite_cta.dart';
import 'convoy_member_list.dart';
import 'convoy_status_header.dart';
import 'gps_readiness_banner.dart';
import 'hazard_banner_strip.dart';
import 'invite_share.dart';
import 'leader_route_cta.dart';
import 'lost_connection_banner.dart';
import 'members_sheet_pill.dart';
import 'proximity_banner.dart';
import 'quick_actions_row.dart';
import 'route_sheet.dart';
import 'sos_hold_button.dart';
import 'waypoint_banner.dart';

/// Active-Convoy-View — Design.pdf Frame 5/6.
/// Layout (von oben nach unten):
///   • Status-Header (Konvoi-Name + Live-Dot + Code-Pill)
///   • Banner-Stack (Connection, LostConnection, Proximity, Waypoint)
///   • Leader-Route-CTA (nur Leader, solange noch kein Ziel gesetzt ist)
///   • Expanded Live-Karte (nimmt den verfügbaren Vertikal-Platz)
///   • Mitglieder-Pille (öffnet die volle Liste in einem Bottom-Sheet)
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
  void initState() {
    super.initState();
    // Entering a convoy: ensure device location is on + permitted so the user
    // appears on the map immediately (and the rest of the convoy sees them).
    if (!kIsWeb) {
      unawaited(LocationPermissionService.ensureReady());
    }
  }

  @override
  Widget build(BuildContext context) {
    final convoy = widget.convoy;
    // These side-effect providers wire native plugins (CarPlay method channel,
    // WebRTC/Firebase-Database PTT, FCM notifications) that throw on web. The
    // web build is for testing the auth/convoy/GPS flow — skip them there.
    if (!kIsWeb) {
      // Publishes THIS device's GPS to the convoy WebSocket so everyone else
      // sees it. Without this watch the publisher never starts → every member
      // shows up as "kein GPS-Signal" to every other member (each only ever
      // saw their own local stream).
      ref.watch(locationPublisherProvider);
      ref.watch(convoyRosterRefreshProvider);
      ref.watch(breachNotificationWatcherProvider);
      ref.watch(convoySplitWatcherProvider);
      ref.watch(pttFrameRoutingProvider(convoy.id));
      // Geteilte LiveKit-Session: EIN gemuteter Raum-Join pro Konvoi (Hörer
      // hören Remote-Audio automatisch, PTT-Druck togglet nur das Mikro).
      // Bei 503 (LiveKit-Env fehlt) bleibt der P2P-Pfad darunter zuständig.
      ref.watch(livekitPttSessionProvider(convoy.id));
      ref.watch(pttReceiverProvider(convoy.id));
      ref.watch(pttPlaybackProvider(convoy.id));
      ref.watch(carPlayConvoyStateWiringProvider);
      ref.watch(lostConnectionWatcherProvider);
      // Display anlassen, solange der Konvoi läuft — Karte + PTT müssen am
      // Lenker ohne erneutes Entsperren sichtbar bleiben.
      ref.watch(convoyWakelockProvider);
    }
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
    final positions = ref.watch(livePositionsProvider);
    final snapshot = positions.valueOrNull ?? const <String, GpsUpdate>{};
    final selfId = ref.watch(selfMemberIdProvider);
    final tourIsEmpty = ref.watch(tourProvider).isEmpty;
    final isLeader = ref.watch(selfIsLeaderProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConvoyStatusHeader(convoy: convoy),
        const ConnectionStatusBanner(),
        const LostConnectionBanner(),
        if (snapshot[selfId] == null)
          GpsReadinessBanner(
            onActivate: () =>
                unawaited(LocationPermissionService.ensureReady()),
          ),
        const ProximityBanner(),
        const WaypointBanner(),
        const SizedBox(height: AppSpacing.md),
        const HazardBannerStrip(),
        const QuickActionBanner(),
        // Leader-only call-to-action: the road route is only drawn once a
        // destination is set, but that entry is otherwise hidden behind a small
        // app-bar flag icon. Surface it prominently while the tour is empty.
        // Smart, context-aware CTA — always surface the single most useful next
        // action: invite people while alone, otherwise plan a route.
        if (convoy.members.length <= 1)
          ConvoyInviteCta(
            onInvite: () => _shareInvite(context, convoy),
          )
        else if (isLeader && tourIsEmpty)
          LeaderRouteCta(onPlanRoute: () => _openRouteSheet(context)),
        // Full-size live map — the main view. The pins already show everyone,
        // so the member list moves into a tap-away sheet (members pill below).
        const Expanded(child: ConvoyMapWidget()),
        const SizedBox(height: AppSpacing.sm),
        MembersSheetPill(
          convoy: convoy,
          onTap: () => _openMembersSheet(context, convoy, snapshot, selfId),
        ),
        const SizedBox(height: AppSpacing.sm),
        const QuickActionsRow(),
        const SizedBox(height: AppSpacing.sm),
        SosHoldButton(
          onTriggered: snapshot[selfId] == null
              ? null
              : () => broadcastSos(
                    context,
                    ref,
                    convoyId: convoy.id,
                    selfPos: snapshot[selfId]!,
                    selfId: selfId,
                  ),
        ),
        ActiveConvoyActionBar(
          memberCount: convoy.members.length,
          onLeave: widget.onLeave,
        ),
      ],
    );
  }

  void _openRouteSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const RouteSheet(),
    );
  }

  void _shareInvite(BuildContext context, Convoy convoy) {
    unawaited(shareConvoyInvite(
      context,
      ref,
      convoy: convoy,
      fallbackClipboardText: 'crewlink://join/${convoy.inviteCode}',
      fallbackSnackbarText:
          'Einladungslink kopiert (Code ${convoy.inviteCode}) — '
          'z. B. in WhatsApp einfügen.',
    ));
  }

  void _openMembersSheet(
    BuildContext context,
    Convoy convoy,
    Map<String, GpsUpdate> positions,
    String selfId,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg,
          ),
          child: ConvoyMemberList(
            convoy: convoy,
            positions: positions,
            selfMemberId: selfId,
          ),
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
