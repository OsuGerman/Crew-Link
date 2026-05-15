import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/geo/distance_engine.dart';
import 'convoy_providers.dart';

/// A [DistanceEngine] pre-configured with the active convoy's proximity
/// threshold (500 m by default when no convoy is joined).
///
/// Invalidated automatically whenever the convoy changes, so any provider
/// that watches this also rebuilds.
final distanceEngineProvider = Provider.autoDispose<DistanceEngine>((ref) {
  final threshold =
      ref.watch(currentConvoyProvider)?.proximityWarningMeters ?? 500.0;
  return DistanceEngine(thresholdMeters: threshold);
});

/// All unique member pairings that currently exceed the convoy's proximity
/// threshold, re-evaluated on every live-positions snapshot.
///
/// Returns an empty list when:
/// - fewer than two positions are available, or
/// - no pair exceeds the threshold.
///
/// Consumers (e.g. [LostConnectionBanner]) watch this provider instead of
/// calling [DistanceEngine.evaluate] directly so threshold changes propagate
/// automatically.
final distancePairingsProvider =
    Provider.autoDispose<List<DistancePairing>>((ref) {
  final engine = ref.watch(distanceEngineProvider);
  final positions = ref.watch(livePositionsProvider).valueOrNull ?? const {};
  return engine.evaluate(positions);
});
