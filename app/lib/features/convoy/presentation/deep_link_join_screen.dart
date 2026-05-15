import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/convoy_providers.dart';
import '../data/convoy_api.dart';

class DeepLinkJoinScreen extends ConsumerStatefulWidget {
  const DeepLinkJoinScreen({super.key, required this.inviteCode});

  final String inviteCode;

  @override
  ConsumerState<DeepLinkJoinScreen> createState() =>
      _DeepLinkJoinScreenState();
}

class _DeepLinkJoinScreenState extends ConsumerState<DeepLinkJoinScreen> {
  bool _busy = false;

  Future<void> _join() async {
    setState(() => _busy = true);
    final api = ref.read(convoyApiProvider);
    final token = ref.read(authTokenProvider);
    try {
      final convoy = await api.joinConvoy(
        inviteCode: widget.inviteCode,
        authToken: token,
      );
      ref.read(currentConvoyProvider.notifier).state = convoy;
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Einladung')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.group_add_outlined, size: 64),
              const SizedBox(height: 24),
              Text(
                'Du wurdest zum Konvoi eingeladen',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Code: ${widget.inviteCode}',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _busy ? null : _join,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.directions_car),
                label: const Text('Jetzt beitreten'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _busy ? null : () => context.go('/'),
                child: const Text('Abbrechen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
