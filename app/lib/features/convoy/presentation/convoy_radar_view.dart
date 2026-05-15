import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/geo/geo_distance.dart';
import '../../../core/models/gps_update.dart';

/// Radar-style visualization of where every convoy member is, relative
/// to self. Self sits at the center. Peers are placed by their bearing
/// + distance from self. Three concentric guide rings mark threshold,
/// release band (1.2× threshold) and the outer "far" boundary; peers
/// beyond the outer ring are clamped to its edge with a directional
/// hint so they stay visible without distorting closer distances.
class ConvoyRadarView extends StatelessWidget {
  const ConvoyRadarView({
    super.key,
    required this.selfMemberId,
    required this.positions,
    required this.thresholdMeters,
    this.maxHeight = 240,
  });

  final String selfMemberId;
  final Map<String, GpsUpdate> positions;
  final double thresholdMeters;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Self-constrains to a bounded square so the widget composes safely
    // inside an unbounded-height Column (e.g. the ConvoyHomeScreen
    // active view) — without this, an AspectRatio:1 would demand a
    // height equal to the available width and trigger overflow.
    return SizedBox(
      height: maxHeight,
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            key: const ValueKey('convoy-radar'),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: CustomPaint(
              painter: _RadarPainter(
                selfMemberId: selfMemberId,
                positions: positions,
                thresholdMeters: thresholdMeters,
                primary: scheme.primary,
                onPrimary: scheme.onPrimary,
                warning: scheme.error,
                onWarning: scheme.onError,
                ringColor: scheme.outlineVariant,
                labelColor: scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.selfMemberId,
    required this.positions,
    required this.thresholdMeters,
    required this.primary,
    required this.onPrimary,
    required this.warning,
    required this.onWarning,
    required this.ringColor,
    required this.labelColor,
  });

  final String selfMemberId;
  final Map<String, GpsUpdate> positions;
  final double thresholdMeters;
  final Color primary;
  final Color onPrimary;
  final Color warning;
  final Color onWarning;
  final Color ringColor;
  final Color labelColor;

  static const double _farBandMultiplier = 3.0;
  static const double _releaseBandMultiplier = 1.2;
  static const double _selfRadiusPx = 9;
  static const double _peerRadiusPx = 7;
  static const double _selfStrokePx = 2.5;
  static const double _ringStrokePx = 1.2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = math.min(size.width, size.height) / 2 - 16;
    final farMeters = thresholdMeters * _farBandMultiplier;

    _paintRing(canvas, center, maxR * (1 / _farBandMultiplier),
        _ringStrokePx); // threshold
    _paintRing(canvas, center, maxR * (_releaseBandMultiplier / _farBandMultiplier),
        _ringStrokePx); // release
    _paintRing(canvas, center, maxR, _ringStrokePx); // outer

    final self = positions[selfMemberId];
    if (self == null) {
      _paintHint(canvas, size, 'warte auf GPS …');
      return;
    }

    _paintSelf(canvas, center);

    for (final entry in positions.entries) {
      if (entry.key == selfMemberId) {
        continue;
      }
      final peer = entry.value;
      final distance = haversineMeters(
        lat1: self.latitude,
        lon1: self.longitude,
        lat2: peer.latitude,
        lon2: peer.longitude,
      );
      final bearing = bearingDegrees(
        lat1: self.latitude,
        lon1: self.longitude,
        lat2: peer.latitude,
        lon2: peer.longitude,
      );

      final clampedDistance = math.min(distance, farMeters);
      final ratio = clampedDistance / farMeters;
      final dx = maxR * ratio * math.sin(bearing * math.pi / 180);
      final dy = -maxR * ratio * math.cos(bearing * math.pi / 180);
      final peerCenter = center + Offset(dx, dy);

      final close = distance <= thresholdMeters;
      _paintPeer(canvas, peerCenter, close);
      _paintLabel(canvas, peerCenter, entry.key, distance);
    }
  }

  void _paintRing(Canvas canvas, Offset center, double r, double strokeWidth) {
    final paint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, r, paint);
  }

  void _paintSelf(Canvas canvas, Offset center) {
    final fill = Paint()
      ..color = primary
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, _selfRadiusPx, fill);
    final ring = Paint()
      ..color = onPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = _selfStrokePx;
    canvas.drawCircle(center, _selfRadiusPx + 3, ring);
  }

  void _paintPeer(Canvas canvas, Offset at, bool close) {
    final paint = Paint()
      ..color = close ? warning : primary.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(at, _peerRadiusPx, paint);
  }

  void _paintLabel(
    Canvas canvas,
    Offset at,
    String memberId,
    double distance,
  ) {
    final label = '$memberId · ${distance.toStringAsFixed(0)} m';
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: labelColor,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      at + Offset(_peerRadiusPx + 4, -textPainter.height / 2),
    );
  }

  void _paintHint(Canvas canvas, Size size, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: labelColor.withValues(alpha: 0.6),
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      size.center(Offset.zero) -
          Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_RadarPainter old) {
    return old.positions != positions ||
        old.thresholdMeters != thresholdMeters ||
        old.selfMemberId != selfMemberId;
  }
}
