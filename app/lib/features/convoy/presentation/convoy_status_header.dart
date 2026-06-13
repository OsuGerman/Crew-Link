import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/convoy.dart';
import '../../../core/realtime/connection_status.dart';
import '../../../core/theme/app_theme.dart';
import '../application/convoy_providers.dart';
import 'invite_share.dart';

/// Kompakter Header über dem Radar — Konvoi-Name + Status-Zeile mit
/// grünem Live-Dot, Mitgliederzahl und Einladungscode (tap-to-copy).
///
/// Designvorlage: Design.pdf Frame 5 ("Schwarzwald Sonntag · TF · 624 PFS").
class ConvoyStatusHeader extends ConsumerWidget {
  const ConvoyStatusHeader({super.key, required this.convoy});

  final Convoy convoy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection =
        ref.watch(convoySocketStatusProvider).valueOrNull;
    final isLive = connection == ConnectionStatus.connected;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            convoy.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LiveDot(isLive: isLive),
              const SizedBox(width: AppSpacing.sm),
              Text(
                isLive ? 'LIVE' : 'OFFLINE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: isLive ? AppColors.success : AppColors.textMuted,
                ),
              ),
              _dot(),
              Text(
                '${convoy.members.length} Member',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              _dot(),
              _CodePill(
                code: convoy.inviteCode,
                onTap: () => unawaited(shareConvoyInvite(
                  context,
                  ref,
                  convoy: convoy,
                  fallbackClipboardText: convoy.inviteCode,
                  fallbackSnackbarText: 'Code ${convoy.inviteCode} kopiert',
                  fallbackSnackbarDuration: const Duration(seconds: 1),
                )),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Text(
          '·',
          style: TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
      );
}

class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.isLive});
  final bool isLive;
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  /// Solider Kern + scharfer Ring mit Luft dazwischen (statt weichem Glow).
  /// Tiefe über Helligkeit: der Ring liest sich als klarer Live-Indikator.
  static const _coreSize = 8.0;
  static const _ringGap = 3.0;
  static const _ringWidth = 1.4;
  static const _minScale = 0.92;
  static const _scaleRange = 0.16;
  static const _ringAlphaBase = 0.35;
  static const _ringAlphaRange = 0.45;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLive) {
      return Container(
        width: _coreSize,
        height: _coreSize,
        decoration: const BoxDecoration(
          color: AppColors.textMuted,
          shape: BoxShape.circle,
        ),
      );
    }
    const ringSize = _coreSize + (_ringGap + _ringWidth) * 2;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => SizedBox(
        width: ringSize,
        height: ringSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Scharfer Ring (kein Glow) — pulst dezent in Helligkeit + Größe.
            Transform.scale(
              scale: _minScale + _scaleRange * _pulse.value,
              child: Container(
                width: ringSize,
                height: ringSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.success.withValues(
                      alpha: _ringAlphaBase + _ringAlphaRange * _pulse.value,
                    ),
                    width: _ringWidth,
                  ),
                ),
              ),
            ),
            const SizedBox(
              width: _coreSize,
              height: _coreSize,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodePill extends StatelessWidget {
  const _CodePill({required this.code, required this.onTap});
  final String code;

  /// Öffnet das System-Share-Sheet mit dem Einladungstext (Fallback:
  /// Code in die Zwischenablage wie früher) — verdrahtet im Header.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AppColors.surfaceOutline,
            width: 0.6,
          ),
        ),
        child: Text(
          code,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
            fontFeatures: [FontFeature.tabularFigures()],
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}
