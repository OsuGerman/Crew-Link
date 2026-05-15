import 'package:flutter/material.dart';

/// Idle/lobby screen — two big actions for create vs. join. The actual
/// API plumbing lives in `ConvoyHomeScreen` so this widget stays
/// transport-agnostic and easy to swap for a future onboarding flow.
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
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Konvoi starten oder beitreten',
          style: TextStyle(fontSize: 20),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const ValueKey('create-convoy-btn'),
          onPressed: onCreate,
          icon: const Icon(Icons.add),
          label: const Text('Neuen Konvoi erstellen'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onJoin,
          icon: const Icon(Icons.group_add),
          label: const Text('Konvoi beitreten'),
        ),
      ],
    );
  }
}

// Legacy `CreateConvoyDialog` + `JoinConvoyDialog` (plus a duplicate
// `CreateConvoyResult`) wurden entfernt — der Home-Screen nutzt
// inzwischen `ConvoyCreateSheet` und `ConvoyJoinSheet`. Der Doppel-Typ
// hat den Build mit "imported from both …" gebrochen.
