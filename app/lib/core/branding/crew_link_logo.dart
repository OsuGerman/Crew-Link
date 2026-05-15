import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Das orange Kreis-Logo mit der stilisierten S-Kurve (zwei umeinander
/// geschlungene Linien) aus dem Design-PDF. CustomPainter, damit keine
/// SVG-Asset-Pipeline + Flutter Web fork-fähig.
class CrewLinkLogo extends StatelessWidget {
  const CrewLinkLogo({
    super.key,
    this.size = 56,
    this.color = AppColors.orange,
    this.background = AppColors.surfaceHigh,
  });

  final double size;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CrewLinkLogoPainter(color: color, background: background),
      ),
    );
  }
}

class _CrewLinkLogoPainter extends CustomPainter {
  const _CrewLinkLogoPainter({required this.color, required this.background});

  final Color color;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);

    // Kreis-Hintergrund
    canvas.drawCircle(
      center,
      w / 2,
      Paint()..color = background,
    );

    // S-Kurve: zwei verschlungene C-Bögen, mit runden Caps. Maße sind
    // relativ zur Bounding-Box (38 % der Breite Radius pro Bogen).
    final stroke = w * 0.11;
    final r = w * 0.18;
    final offset = w * 0.13;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // Oberer Bogen
    final topCenter = Offset(center.dx - offset * 0.4, center.dy - offset);
    canvas.drawArc(
      Rect.fromCircle(center: topCenter, radius: r),
      _radians(160),
      _radians(220),
      false,
      paint,
    );

    // Unterer Bogen (gespiegelt)
    final bottomCenter = Offset(center.dx + offset * 0.4, center.dy + offset);
    canvas.drawArc(
      Rect.fromCircle(center: bottomCenter, radius: r),
      _radians(-20),
      _radians(220),
      false,
      paint,
    );
  }

  static double _radians(double degrees) => degrees * 3.1415926535 / 180.0;

  @override
  bool shouldRepaint(covariant _CrewLinkLogoPainter old) =>
      old.color != color || old.background != background;
}
