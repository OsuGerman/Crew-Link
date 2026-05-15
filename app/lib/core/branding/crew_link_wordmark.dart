import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Zwei-farbiges "Crew Link" Wordmark — "Crew" in Text-Primary, "Link" in
/// Marken-Orange. Wird als AppBar-Titel und auf Splash/Onboarding genutzt.
class CrewLinkWordmark extends StatelessWidget {
  const CrewLinkWordmark({
    super.key,
    this.fontSize = 18,
    this.fontWeight = FontWeight.w700,
  });

  final double fontSize;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: -0.2,
      height: 1.05,
    );
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'Crew ',
            style: base.copyWith(color: AppColors.textPrimary),
          ),
          TextSpan(
            text: 'Link',
            style: base.copyWith(color: AppColors.orange),
          ),
        ],
      ),
    );
  }
}
