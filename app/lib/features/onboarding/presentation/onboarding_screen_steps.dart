part of 'onboarding_screen.dart';

extension _Steps on _OnboardingScreenState {
  Widget _buildSiwaStep() {
    return Padding(
      key: const ValueKey('onboarding-page-siwa'),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Column(
        children: [
          const Expanded(child: OnboardingPageView(page: _siwaPage)),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
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
    final scheme = Theme.of(context).colorScheme;
    final trimmed = _nameController.text.trim();
    final initial = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
    return SingleChildScrollView(
      key: const ValueKey('onboarding-page-profile'),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Dein Profil',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Dein Name ist für andere Mitglieder deines Konvois sichtbar.',
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          TextField(
            key: const ValueKey('onboarding-profile-name'),
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Dein Name',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (trimmed.isNotEmpty) _advanceToCta();
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(
              key: const ValueKey('onboarding-profile-next'),
              onPressed: trimmed.isNotEmpty ? _advanceToCta : null,
              child: const Text(
                'Weiter',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConvoyCtaStep() {
    return Padding(
      key: const ValueKey('onboarding-page-cta'),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Column(
        children: [
          const Expanded(child: OnboardingPageView(page: _ctaPage)),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('onboarding-cta-create'),
              onPressed: _completing ? null : _complete,
              child: _completing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Neuen Konvoi erstellen',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: OutlinedButton(
              key: const ValueKey('onboarding-cta-join'),
              onPressed: _completing ? null : _complete,
              child: const Text(
                'Konvoi beitreten',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
