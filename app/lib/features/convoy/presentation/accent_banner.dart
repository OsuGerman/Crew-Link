import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Gemeinsames Banner-Muster: ruhige [surfaceHigh]-Fläche mit Radius 16 und
/// einem schmalen, farbigen Streifen LINKS als Status-Akzent — statt eines
/// gleichmäßigen Rundum-Rahmens. Der Streifen ist peripher gut lesbar (man
/// erkennt den Status aus dem Augenwinkel), ohne die Fläche einzurahmen.
///
/// Jedes Banner liefert nur seinen Inhalt; die Dekoration (Fläche, Radius,
/// Streifen, Clipping) lebt hier, damit die drei Status-Banner ein
/// einheitliches Bild ergeben.
class AccentBanner extends StatelessWidget {
  const AccentBanner({
    super.key,
    required this.stripeColor,
    required this.child,
    this.bannerKey,
    this.onTap,
    this.fill = AppColors.surfaceHigh,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
  });

  /// Farbe des linken Akzentstreifens (Statusfarbe).
  final Color stripeColor;

  /// Optionaler Key auf dem äußeren Container (Tests hängen daran).
  final Key? bannerKey;

  /// Optionaler Tap-Handler — wenn gesetzt, wird der Inhalt antippbar.
  final VoidCallback? onTap;

  final Color fill;
  final EdgeInsetsGeometry padding;
  final Widget child;

  static const double _stripeWidth = 3;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.card);
    // IntrinsicHeight, damit der Streifen exakt die Inhaltshöhe füllt — ohne
    // ihn würde CrossAxisAlignment.stretch in einer Spalte unbegrenzter Höhe
    // eine unendliche Höhe erzwingen.
    final content = DecoratedBox(
      decoration: BoxDecoration(color: fill),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: _stripeWidth, color: stripeColor),
            Expanded(
              child: Padding(padding: padding, child: child),
            ),
          ],
        ),
      ),
    );
    return Container(
      key: bannerKey,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: radius),
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap, child: content),
            ),
    );
  }
}
