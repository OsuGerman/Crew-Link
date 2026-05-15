import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/convoy.dart';
import '../../../core/realtime/connection_status.dart';
import '../../../core/theme/app_theme.dart';
import '../application/convoy_providers.dart';

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
              _CodePill(code: convoy.inviteCode),
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
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: AppColors.textMuted,
          shape: BoxShape.circle,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: AppColors.success,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.success.withValues(
                alpha: 0.55 - 0.45 * _pulse.value,
              ),
              blurRadius: 6 + 6 * _pulse.value,
              spreadRadius: 1 + 1 * _pulse.value,
            ),
          ],
        ),
      ),
    );
  }
}

class _CodePill extends StatelessWidget {
  const _CodePill({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: code));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Code $code kopiert'),
            duration: const Duration(seconds: 1),
          ),
        );
      },
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
