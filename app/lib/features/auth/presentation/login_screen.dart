import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:crew_link/features/auth/application/auth_notifier.dart';

/// Root authentication screen — shown when the user is not signed in.
///
/// GoRouter's redirect logic handles navigation away from this screen
/// automatically once auth succeeds; [LoginScreen] never calls
/// `context.go()` itself.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  static const routePath = '/login';

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  _AuthMode _mode = _AuthMode.signIn;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _passwordVisible = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitEmailAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final notifier = ref.read(authNotifierProvider.notifier);
    if (_mode == _AuthMode.signIn) {
      await notifier.signInWithEmail(email, password);
    } else {
      await notifier.signUpWithEmail(email, password);
    }
  }

  Future<void> _submitApple() async {
    await ref.read(authNotifierProvider.notifier).signInWithApple();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.isLoading;
    final errorMessage = authState.errorMessage;

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Logo / title ──────────────────────────────────────────
                Icon(
                  Icons.route_rounded,
                  size: 64,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Crew Link',
                  textAlign: TextAlign.center,
                  style: textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Für Autofahrer, die gemeinsam fahren.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 40),

                // ── Mode toggle ───────────────────────────────────────────
                _ModeToggle(
                  mode: _mode,
                  onChanged: isLoading
                      ? null
                      : (mode) => setState(() => _mode = mode),
                ),
                const SizedBox(height: 28),

                // ── Email field ───────────────────────────────────────────
                TextField(
                  key: const ValueKey('login-email'),
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enabled: !isLoading,
                  decoration: const InputDecoration(
                    labelText: 'E-Mail',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),

                // ── Password field ────────────────────────────────────────
                TextField(
                  key: const ValueKey('login-password'),
                  controller: _passwordController,
                  obscureText: !_passwordVisible,
                  enabled: !isLoading,
                  decoration: InputDecoration(
                    labelText: 'Passwort',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _passwordVisible
                          ? 'Passwort verbergen'
                          : 'Passwort anzeigen',
                      icon: Icon(
                        _passwordVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: isLoading
                          ? null
                          : () => setState(
                                () => _passwordVisible = !_passwordVisible,
                              ),
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: isLoading ? null : (_) => _submitEmailAuth(),
                ),
                const SizedBox(height: 24),

                // ── Primary action button ─────────────────────────────────
                FilledButton(
                  key: const ValueKey('login-submit'),
                  onPressed: isLoading ? null : _submitEmailAuth,
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _mode == _AuthMode.signIn
                              ? 'Anmelden'
                              : 'Registrieren',
                        ),
                ),
                const SizedBox(height: 24),

                // ── "oder" divider ────────────────────────────────────────
                const _OrDivider(),
                const SizedBox(height: 24),

                // ── Sign in with Apple ────────────────────────────────────
                IgnorePointer(
                  ignoring: isLoading,
                  child: Opacity(
                    opacity: isLoading ? 0.5 : 1.0,
                    child: SignInWithAppleButton(
                      key: const ValueKey('login-siwa'),
                      onPressed: _submitApple,
                    ),
                  ),
                ),

                // ── Error message ─────────────────────────────────────────
                if (errorMessage != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    errorMessage,
                    key: const ValueKey('login-error'),
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mode enum ─────────────────────────────────────────────────────────────────

enum _AuthMode { signIn, signUp }

// ── Mode toggle widget ────────────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final _AuthMode mode;
  final ValueChanged<_AuthMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_AuthMode>(
      key: const ValueKey('login-mode-toggle'),
      segments: const [
        ButtonSegment(
          value: _AuthMode.signIn,
          label: Text('Anmelden'),
        ),
        ButtonSegment(
          value: _AuthMode.signUp,
          label: Text('Registrieren'),
        ),
      ],
      selected: {mode},
      onSelectionChanged: onChanged == null
          ? null
          : (selection) => onChanged!(selection.first),
    );
  }
}

// ── "oder" divider ────────────────────────────────────────────────────────────

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return Row(
      children: [
        Expanded(child: Divider(color: color)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'oder',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        Expanded(child: Divider(color: color)),
      ],
    );
  }
}
