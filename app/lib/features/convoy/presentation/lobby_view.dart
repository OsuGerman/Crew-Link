import 'package:flutter/material.dart';

import '../../../core/branding/crew_link_logo.dart';
import '../../../core/theme/app_theme.dart';

/// Idle/Lobby-Screen — Hero-Logo + großer Titel + zwei Aktionen.
/// Designvorlage: Design.pdf Frame 1 + 5 ("Lobby · kein aktiver Konvoi").
class LobbyView extends StatelessWidget {
  const LobbyView({
    super.key,
    required this.onCreate,
    required this.onJoin,
  });

  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          // Hero-Logo (orange Kreis mit S-Kurve, Glow)
          Center(
            child: _LogoWithGlow(),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Willkommen bei Crew Link',
            textAlign: TextAlign.center,
            style: theme.textTheme.displayLarge?.copyWith(fontSize: 30),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Koordiniere deinen Konvoi live, sieh wo dein\nKreis fährt, sprich mit allen mit einem Tap.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const Spacer(),
          FilledButton(
            key: const ValueKey('create-convoy-btn'),
            onPressed: onCreate,
            child: const Text('Neuen Konvoi starten'),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            onPressed: onJoin,
            child: const Text('Konvoi beitreten'),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

class _LogoWithGlow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      height: 132,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.orange.withValues(alpha: 0.22),
            blurRadius: 60,
            spreadRadius: 6,
          ),
        ],
      ),
      child: const CrewLinkLogo(size: 96),
    );
  }
}
