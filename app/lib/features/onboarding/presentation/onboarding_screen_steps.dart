part of 'onboarding_screen.dart';

extension _Steps on _OnboardingScreenState {
  Widget _buildSiwaStep() {
    return Padding(
      key: const ValueKey('onboarding-page-siwa'),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.lg),
      child: Column(
        children: [
          const Expanded(child: OnboardingPageView(page: _siwaPage)),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: SignInArea(
              signing: _signing,
              error: _signingError,
              onSignIn: _signInWithApple,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileStep() {
    final trimmed = _nameController.text.trim();
    final initial = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
    return SingleChildScrollView(
      key: const ValueKey('onboarding-page-profile'),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xxl),
          Center(child: _PulsingAvatar(initial: initial)),
          const SizedBox(height: AppSpacing.xl),
          const Text(
            'Wie sollen dich andere\nsehen?',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Dein Anzeigename erscheint in der Live-Karte\nund im Walkie-Talkie.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),
          TextField(
            key: const ValueKey('onboarding-profile-name'),
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              hintText: 'Markus',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (trimmed.isNotEmpty) _advanceToCta();
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            key: const ValueKey('onboarding-profile-next'),
            onPressed: trimmed.isNotEmpty ? _advanceToCta : null,
            child: const Text('Weiter'),
          ),
        ],
      ),
    );
  }

  Widget _buildConvoyCtaStep() {
    return Padding(
      key: const ValueKey('onboarding-page-cta'),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.lg),
      child: Column(
        children: [
          const Expanded(child: OnboardingPageView(page: _ctaPage)),
          FilledButton(
            key: const ValueKey('onboarding-cta-create'),
            onPressed: _completing ? null : _complete,
            child: _completing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Loslegen'),
          ),
        ],
      ),
    );
  }
}

/// Profile-Step Initial-Avatar mit langsamem Orange-Pulse — gibt dem
/// statischen Bildschirm visuelles Leben und unterstreicht den Brand-Akzent.
class _PulsingAvatar extends StatefulWidget {
  const _PulsingAvatar({required this.initial});
  final String initial;

  @override
  State<_PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<_PulsingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final pulse = _ctrl.value;
        return Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.orange, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppColors.orange
                    .withValues(alpha: 0.18 + 0.18 * pulse),
                blurRadius: 40 + 24 * pulse,
                spreadRadius: 2 + 6 * pulse,
              ),
            ],
          ),
          child: Center(
            child: Text(
              widget.initial,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: AppColors.orange,
              ),
            ),
          ),
        );
      },
    );
  }
}
