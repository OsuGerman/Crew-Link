import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:crew_link/core/branding/crew_link_logo.dart';
import 'package:crew_link/core/branding/crew_link_wordmark.dart';
import 'package:crew_link/core/theme/app_theme.dart';
import 'package:crew_link/features/auth/application/auth_notifier.dart';

/// Welcome-Screen (Design.pdf Frame 1).
///
/// Primärer Login ist **Email/Passwort** (kostenlos, kein Apple-Developer-
/// Account nötig). „Sign in with Apple" bleibt als Sekundär-Option erhalten —
/// funktioniert erst mit bezahltem Apple-Account + konfiguriertem Provider.
/// Der Router schickt nach erfolgreichem Auth automatisch ins Onboarding.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  static const routePath = '/login';

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final notifier = ref.read(authNotifierProvider.notifier);
    if (_isSignUp) {
      notifier.signUpWithEmail(email, password);
    } else {
      notifier.signInWithEmail(email, password);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.isLoading;
    final errorMessage = authState.errorMessage;
    // "Sign in with Apple" only works on Apple platforms; on Android it throws
    // (webAuthenticationOptions required). Hide it (and its divider) elsewhere.
    final showApple = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xl),
              Center(child: _HeroLogo()),
              const SizedBox(height: AppSpacing.xl),
              const Center(child: CrewLinkWordmark(fontSize: 34)),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Koordiniere deinen Konvoi live. Sieh, wo dein\n'
                'Kreis fährt, sprich mit allen mit einem Tap.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              TextField(
                key: const ValueKey('login-email'),
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enabled: !isLoading,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'E-Mail',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const ValueKey('login-password'),
                controller: _passwordController,
                obscureText: true,
                enabled: !isLoading,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => isLoading ? null : _submit(),
                decoration: const InputDecoration(
                  labelText: 'Passwort',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (errorMessage != null) ...[
                Text(
                  errorMessage,
                  key: const ValueKey('login-error'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              SizedBox(
                height: 54,
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : FilledButton(
                        key: const ValueKey('login-submit'),
                        onPressed: _submit,
                        child: Text(
                          _isSignUp ? 'Konto erstellen' : 'Anmelden',
                        ),
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                key: const ValueKey('login-toggle'),
                onPressed: isLoading
                    ? null
                    : () => setState(() => _isSignUp = !_isSignUp),
                child: Text(
                  _isSignUp
                      ? 'Schon ein Konto? Anmelden'
                      : 'Neu hier? Konto erstellen',
                ),
              ),
              if (showApple) ...[
                const SizedBox(height: AppSpacing.md),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: Text(
                        'oder',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 54,
                  child: SignInWithAppleButton(
                    key: const ValueKey('login-siwa'),
                    onPressed: isLoading
                        ? () {}
                        : () => ref
                            .read(authNotifierProvider.notifier)
                            .signInWithApple(),
                    style: SignInWithAppleButtonStyle.white,
                    borderRadius: BorderRadius.circular(AppRadii.button),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Flach, ohne Orange-Glow — das Logo steht für sich.
    return const SizedBox(
      width: 132,
      height: 132,
      child: Center(child: CrewLinkLogo(size: 96)),
    );
  }
}
