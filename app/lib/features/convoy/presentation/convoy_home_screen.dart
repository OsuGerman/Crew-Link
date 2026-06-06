import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branding/crew_link_wordmark.dart';
import '../../../core/location/location_permission_service.dart';
import '../../../core/models/convoy.dart';
import '../../../core/observability/app_logger.dart';
import '../../../core/observability/observability_bootstrap.dart';
import '../../auth/application/auth_providers.dart';
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
import 'fuel_sheet.dart';
import 'hazard_quick_sheet.dart';
import 'lobby_view.dart';
import 'route_sheet.dart';

/// Shell widget — owns the Scaffold + AppBar and dispatches into one of
/// three body views (lobby, active, driver-active). Convoy create/join
/// API calls live here because they are cross-cutting and shouldn't
/// drag the lobby widget into the API/provider layer.
/// True while a convoy create/join API call is in flight — drives the lobby's
/// loading state so the screen doesn't look frozen during a Render cold start
/// (the first request after idle can take ~30s).
final _convoyBusyProvider = StateProvider<bool>((ref) => false);

class ConvoyHomeScreen extends ConsumerWidget {
  const ConvoyHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convoy = ref.watch(currentConvoyProvider);
    final driverMode = ref.watch(driverModeProvider);
    final hasRoute = ref.watch(tourProvider).isNotEmpty;
    final busy = ref.watch(_convoyBusyProvider);
    return Scaffold(
      appBar: AppBar(
        // Wordmark only in the lobby; in a convoy the name is in the status
        // header below, so we drop it here to make room for the actions
        // (otherwise the title gets squished into the top-left corner).
        title: convoy == null ? const CrewLinkWordmark(fontSize: 19) : null,
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
          PopupMenuButton<String>(
            key: const ValueKey('overflow-menu'),
            tooltip: 'Mehr',
            onSelected: (value) {
              switch (value) {
                case 'map':
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ConvoyMapScreen(),
                    ),
                  );
                case 'vehicle':
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const VehicleProfileScreen(),
                    ),
                  );
                case 'fuel':
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const FuelSheet(),
                  );
                case 'beta':
                  BetaFeedbackSheet.show(
                    context,
                    screenContext: 'ConvoyHomeScreen',
                  );
                case 'privacy':
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PrivacyPolicyScreen(),
                    ),
                  );
              }
            },
            itemBuilder: (context) => [
              if (convoy != null) ...[
                const PopupMenuItem(
                  key: ValueKey('open-map'),
                  value: 'map',
                  child: Row(
                    children: [
                      Icon(Icons.map_outlined),
                      SizedBox(width: 12),
                      Text('Karte'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  key: ValueKey('open-vehicle-profile'),
                  value: 'vehicle',
                  child: Row(
                    children: [
                      Icon(Icons.garage_outlined),
                      SizedBox(width: 12),
                      Text('Mein Fahrzeug'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'fuel',
                  child: Row(
                    children: [
                      Icon(Icons.local_gas_station_outlined),
                      SizedBox(width: 12),
                      Text('Tankstand'),
                    ],
                  ),
                ),
              ],
              const PopupMenuItem(
                value: 'beta',
                child: Row(
                  children: [
                    Icon(Icons.feedback_outlined),
                    SizedBox(width: 12),
                    Text('Beta-Feedback'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'privacy',
                child: Row(
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 12),
                    Text('Datenschutz'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: convoy == null
          ? (busy
              ? const _ConvoyBusyView()
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: LobbyView(
                      onCreate: () => _create(context, ref),
                      onJoin: () => _join(context, ref),
                    ),
                  ),
                ))
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
    final messenger = ScaffoldMessenger.of(context);
    // Await the Firebase ID token — reading authTokenProvider synchronously can
    // return '' while the token future is still resolving (→ empty Bearer → 401).
    final token = await ref.read(authIdTokenProvider.future) ?? '';
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
    final messenger = ScaffoldMessenger.of(context);
    ref.read(_convoyBusyProvider.notifier).state = true;
    try {
      // Await the Firebase ID token — reading authTokenProvider synchronously
      // can return '' while the token future resolves (→ empty Bearer → 401).
      final token = await ref.read(authIdTokenProvider.future) ?? '';
      final convoy = await action(api, token);
      ref.read(currentConvoyProvider.notifier).state = convoy;
      // Konvoi läuft jetzt → Hintergrund-Tracking braucht "Always".
      // Kontextbezogen (nicht beim App-Start) hochstufen; Fehler dürfen den
      // Beitritt nicht abbrechen, daher unawaited + intern gekapselt.
      unawaited(_escalateLocationPermission());
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      ref.read(_convoyBusyProvider.notifier).state = false;
    }
  }

  /// Stuft die Standort-Berechtigung auf "Always" hoch, sobald ein Konvoi
  /// aktiv ist — sonst suspendiert iOS die Lieferung im Hintergrund und
  /// Android drosselt sie. Best-effort: jeder Fehler wird geloggt, bricht
  /// aber den Konvoi-Beitritt nicht ab.
  Future<void> _escalateLocationPermission() async {
    if (kIsWeb) return;
    try {
      await LocationPermissionService.requestAlways();
    } catch (e, s) {
      appLog.e('LocationAlwaysEscalation', error: e, stackTrace: s);
      try {
        await ObservabilityBootstrap.build().reportError(e, s);
      } catch (_) {
        // Reporter evtl. nicht verfügbar (z. B. Test ohne Firebase) — ignorieren.
      }
    }
  }
}

/// Loading state shown in the lobby while a create/join request is in flight,
/// so a slow (cold-start) backend doesn't look like a frozen screen.
class _ConvoyBusyView extends StatelessWidget {
  const _ConvoyBusyView();

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).textTheme.bodySmall?.color;
    return Center(
      key: const ValueKey('convoy-busy'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          const Text(
            'Konvoi wird vorbereitet …',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Der erste Start nach einer Pause kann kurz dauern.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: hint),
            ),
          ),
        ],
      ),
    );
  }
}
