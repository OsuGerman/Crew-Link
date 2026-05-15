import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/geo/geo_distance.dart';
import '../../../core/models/convoy.dart';
import '../../../core/models/gps_update.dart';
import '../../../core/notifications/notification_service.dart';
import '../domain/convoy_split_event.dart';
import 'breach_notification_watcher.dart';
import 'convoy_providers.dart';

// Split notification IDs occupy 100000–199999 to avoid collision with
// breach notification IDs (0–99999) in breach_notification_watcher.dart.
const int _kSplitNotifOffset = 100000;

// After a split fires, wait this long before re-alarming the same member.
const int _kCooldownSeconds = 300;

/// Holds the most-recently detected split event (null = convoy intact).
/// UI consumers use [ref.listen] on this provider to show an in-app alert.
final activeSplitProvider = StateProvider<ConvoySplitEvent?>((ref) => null);

/// Watches live member positions and declares a [ConvoySplitEvent] when any
/// member stays beyond [Convoy.proximityWarningMeters] for at least
/// [ConvoySplitEvent.kSustainedSeconds] seconds.
///
/// On detection:
///   • updates [activeSplitProvider] (triggers in-app alert)
///   • fires a local push notification via [NotificationService.showSplit]
///
/// The same member cannot re-trigger a split within [_kCooldownSeconds] (5 min)
/// to avoid notification spam during prolonged separation.
///
/// Activate by watching this provider inside the active-convoy widget tree.
final convoySplitWatcherProvider = Provider.autoDispose<void>((ref) {
  final selfId = ref.watch(selfMemberIdProvider);
  final convoy = ref.watch(currentConvoyProvider);
  if (convoy == null) return;

  final service = ref.read(notificationServiceProvider);
  final clock = ref.read(clockProvider);

  // Tracks when each member first exceeded the threshold in the current breach.
  final breachStart = <String, DateTime>{};
  // Tracks when a split was last declared per member (for cooldown).
  final lastSplit = <String, DateTime>{};

  ref.listen<AsyncValue<Map<String, GpsUpdate>>>(
    livePositionsProvider,
    (_, next) {
      next.whenData((positions) {
        final selfPos = positions[selfId];
        if (selfPos == null) return;
        final now = clock();

        for (final entry in positions.entries) {
          if (entry.key == selfId) continue;
          final dist = haversineMeters(
            lat1: selfPos.latitude,
            lon1: selfPos.longitude,
            lat2: entry.value.latitude,
            lon2: entry.value.longitude,
          );

          if (dist > convoy.proximityWarningMeters) {
            breachStart[entry.key] ??= now;
            final elapsed = now.difference(breachStart[entry.key]!);
            if (elapsed.inSeconds >= ConvoySplitEvent.kSustainedSeconds) {
              final sinceLastSplit = lastSplit[entry.key];
              final cooldownExpired = sinceLastSplit == null ||
                  now.difference(sinceLastSplit).inSeconds >= _kCooldownSeconds;
              if (cooldownExpired) {
                ref.read(activeSplitProvider.notifier).state = ConvoySplitEvent(
                  splitMemberId: entry.key,
                  distanceMeters: dist,
                  detectedAt: now,
                );
                unawaited(service.showSplit(
                  id: _kSplitNotifOffset +
                      entry.key.hashCode.abs() % _kSplitNotifOffset,
                  memberName: _memberName(convoy, entry.key),
                  distanceMeters: dist,
                ));
                lastSplit[entry.key] = now;
              }
              // Reset breach timer so the elapsed counter restarts.
              breachStart[entry.key] = now;
            }
          } else {
            breachStart.remove(entry.key);
          }
        }
      });
    },
  );

  ref.onDispose(() {
    breachStart.clear();
    lastSplit.clear();
  });
});


String _memberName(Convoy convoy, String memberId) =>
    convoy.members
        .where((m) => m.id == memberId)
        .firstOrNull
        ?.displayName ??
    memberId;
