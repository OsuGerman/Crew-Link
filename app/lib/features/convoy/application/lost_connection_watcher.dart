import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/geo/geo_distance.dart';
import 'breach_notification_watcher.dart';
import 'convoy_providers.dart';

/// Derives which convoy member IDs are currently beyond the proximity
/// threshold relative to the local device. Recomputed on every position
/// update — consumed by [LostConnectionBanner] for a persistent display.
final lostMembersProvider = Provider.autoDispose<Set<String>>((ref) {
  final convoy = ref.watch(currentConvoyProvider);
  final selfId = ref.watch(selfMemberIdProvider);
  final positions = ref.watch(livePositionsProvider).valueOrNull;
  if (convoy == null || positions == null) return const {};
  final selfPos = positions[selfId];
  if (selfPos == null) return const {};

  final threshold = convoy.proximityWarningMeters;
  final lost = <String>{};
  for (final entry in positions.entries) {
    if (entry.key == selfId) continue;
    final dist = haversineMeters(
      lat1: selfPos.latitude,
      lon1: selfPos.longitude,
      lat2: entry.value.latitude,
      lon2: entry.value.longitude,
    );
    if (dist > threshold) lost.add(entry.key);
  }
  return Set.unmodifiable(lost);
});

/// Fires a local notification the first time each convoy member exceeds the
/// proximity threshold. Resets per-member when they return to range, so a
/// future separation triggers a new notification.
///
/// Activate by watching this provider in the active-convoy widget tree.
final lostConnectionWatcherProvider = Provider.autoDispose<void>((ref) {
  final convoy = ref.watch(currentConvoyProvider);
  if (convoy == null) return;

  final service = ref.read(notificationServiceProvider);
  final notified = <String>{};

  ref.listen<Set<String>>(
    lostMembersProvider,
    (_, next) {
      for (final id in next) {
        if (notified.contains(id)) continue;
        notified.add(id);
        final name = convoy.members
                .where((m) => m.id == id)
                .firstOrNull
                ?.displayName ??
            id;
        final notifId = 200000 + id.hashCode.abs() % 100000;
        unawaited(service.showConnectionLost(
          notificationId: notifId,
          memberName: name,
          thresholdMeters: convoy.proximityWarningMeters,
        ));
      }
      // Clear flag for members who returned to range.
      notified.removeWhere((id) => !next.contains(id));
    },
  );
});
