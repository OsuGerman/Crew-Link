import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branding/crew_link_wordmark.dart';
import '../../../core/models/convoy.dart';
import '../../beta/presentation/beta_feedback_sheet.dart';
import '../../legal/presentation/privacy_policy_screen.dart';
import '../../maps/presentation/convoy_map_screen.dart';
import '../../vehicle/presentation/vehicle_profile_screen.dart';
import '../application/convoy_providers.dart';
import '../application/driver_mode.dart';
import '../application/waypoint_providers.dart';
import '../data/convoy_api.dart';
import 'active_convoy_view.dart';
import 'convoy_create_sheet.dart';
import 'convoy_join_sheet.dart';
import 'driver_active_view.dart';
import 'hazard_quick_sheet.dart';
import 'lobby_view.dart';
import 'route_sheet.dart';

/// Shell widget — owns the Scaffold + AppBar and dispatches into one of
/// three body views (lobby, active, driver-active). Convoy create/join
/// API calls live here because they are cross-cutting and shouldn't
/// drag the lobby widget into the API/provider layer.
class ConvoyHomeScreen extends ConsumerWidget {
  const ConvoyHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convoy = ref.watch(currentConvoyProvider);
    final driverMode = ref.watch(driverModeProvider);
    final isLeader = ref.watch(selfIsLeaderProvider);
    final hasRoute = ref.watch(tourProvider).isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const CrewLinkWordmark(fontSize: 19),
        actions: [
          if (convoy != null)
            // Allen sichtbar — Read-Only-Anzeige für Non-Leader.
            IconButton(
              key: const ValueKey('open-route-sheet'),
              tooltip: hasRoute ? 'Route ändern' : 'Route planen',
              icon: Icon(
                Icons.flag_rounded,
                color: hasRoute
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const RouteSheet(),
              ),
            ),
          if (convoy != null)
            IconButton(
              key: const ValueKey('open-hazard-sheet'),
              tooltip: 'Gefahr melden',
              icon: const Icon(Icons.warning_amber_rounded),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => HazardQuickSheet(convoy: convoy),
              ),
            ),
          if (convoy != null)
            IconButton(
              key: const ValueKey('share-invite'),
              tooltip: 'Einladung teilen',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => _shareInvite(context, convoy),
            ),
          if (convoy != null)
            IconButton(
              key: const ValueKey('open-map'),
              tooltip: 'Karte',
              icon: const Icon(Icons.map_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ConvoyMapScreen(),
                ),
              ),
            ),
          if (convoy != null)
            IconButton(
              key: const ValueKey('toggle-driver-mode'),
              tooltip: driverMode ? 'Driver-Mode aus' : 'Driver-Mode an',
              icon: Icon(
                driverMode
                    ? Icons.directions_car
                    : Icons.directions_car_outlined,
                color: driverMode
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              onPressed: () => ref
                  .read(driverModeProvider.notifier)
                  .state = !driverMode,
            ),
          if (!driverMode)
            IconButton(
              key: const ValueKey('open-vehicle-profile'),
              tooltip: 'Mein Fahrzeug',
              icon: const Icon(Icons.garage_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const VehicleProfileScreen(),
                  ),
                );
              },
            ),
          IconButton(
            key: const ValueKey('open-beta-feedback'),
            tooltip: 'Beta-Feedback',
            icon: const Icon(Icons.feedback_outlined),
            onPressed: () => BetaFeedbackSheet.show(
              context,
              screenContext: 'ConvoyHomeScreen',
            ),
          ),
          IconButton(
            key: const ValueKey('open-privacy-policy'),
            tooltip: 'Datenschutz',
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PrivacyPolicyScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: convoy == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: LobbyView(
                  onCreate: () => _create(context, ref),
                  onJoin: () => _join(context, ref),
                ),
              ),
            )
          : SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: driverMode ? 12 : 16,
                ),
                child: driverMode
                    ? DriverModeActiveView(
                        convoy: convoy,
                        onLeave: () => _leave(context, ref, convoy),
                      )
                    : ActiveConvoyView(
                        convoy: convoy,
                        onLeave: () => _leave(context, ref, convoy),
                      ),
              ),
            ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<CreateConvoyResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ConvoyCreateSheet(),
    );
    if (result == null || !context.mounted) return;
    await _runApi(
      context,
      ref,
      action: (api, token) => api.createConvoy(
        name: result.name,
        authToken: token,
        proximityWarningMeters: result.thresholdMeters,
      ),
    );
  }

  Future<void> _join(BuildContext context, WidgetRef ref) async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ConvoyJoinSheet(),
    );
    if (code == null || !context.mounted) return;
    await _runApi(
      context,
      ref,
      action: (api, token) =>
          api.joinConvoy(inviteCode: code, authToken: token),
    );
  }

  void _shareInvite(BuildContext context, Convoy convoy) {
    final link = 'crewlink://join/${convoy.inviteCode}';
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Einladungslink kopiert!')),
    );
  }

  Future<void> _leave(BuildContext context, WidgetRef ref, Convoy convoy) async {
    final api = ref.read(convoyApiProvider);
    final token = ref.read(authTokenProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.leaveConvoy(convoyId: convoy.id, authToken: token);
      ref.read(currentConvoyProvider.notifier).state = null;
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Future<void> _runApi(
    BuildContext context,
    WidgetRef ref, {
    required Future<Convoy> Function(ConvoyApi api, String token) action,
  }) async {
    final api = ref.read(convoyApiProvider);
    final token = ref.read(authTokenProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final convoy = await action(api, token);
      ref.read(currentConvoyProvider.notifier).state = convoy;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }
}
