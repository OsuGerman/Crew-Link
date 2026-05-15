import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Datenschutz')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        children: [
          Text('Datenschutzerklärung', style: textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Stand: Mai 2026',
            style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          const _Section(
            title: 'Verantwortlicher',
            body: 'Adrian Mirwaldt\nadrian.mirwaldt21@gmail.com',
          ),
          const _Section(
            title: 'Welche Daten wir erheben',
            body:
                '• Standortdaten (GPS) – nur während einer aktiven Konvoi-Session\n'
                '• Audiosignal – nur solange die PTT-Taste gedrückt ist\n'
                '• Fahrzeugprofil – von dir freiwillig eingegeben\n'
                '• Apple-Nutzer-ID (anonymisiert) – für die Konvoi-Zugehörigkeit',
          ),
          const _Section(
            title: 'Zweck der Datenverarbeitung',
            body:
                'GPS-Koordinaten werden ausschließlich für die Echtzeit-Karte '
                'innerhalb eines aktiven Konvois verwendet. Sie werden nicht '
                'dauerhaft gespeichert und nach Ende der Session automatisch '
                'gelöscht. Audiodaten werden nicht aufgezeichnet; sie werden '
                'als verschlüsselter Live-Stream (WebRTC/Opus) direkt an die '
                'Konvoi-Mitglieder übertragen.',
          ),
          const _Section(
            title: 'Weitergabe an Dritte',
            body:
                'Deine Daten werden nicht an Dritte verkauft oder für Werbung '
                'genutzt. Für den Betrieb der Echtzeit-Infrastruktur nutzen '
                'wir Firebase (Google LLC, USA) mit angemessenem Datenschutzniveau '
                'gemäß EU-Standardvertragsklauseln.',
          ),
          const _Section(
            title: 'Speicherdauer',
            body:
                'GPS-Positionen: keine persistente Speicherung – In-Memory während '
                'der Session.\n'
                'Fahrzeugprofile und Konvoi-Metadaten: bis zur Löschung durch '
                'den Nutzer.',
          ),
          const _Section(
            title: 'Deine Rechte',
            body:
                'Du hast das Recht auf Auskunft, Berichtigung, Löschung und '
                'Einschränkung der Verarbeitung. Für Anfragen wende dich an '
                'adrian.mirwaldt21@gmail.com.\n\n'
                'Du kannst die App-Berechtigungen (Standort, Mikrofon) jederzeit '
                'in den iOS-Einstellungen widerrufen.',
          ),
          const _Section(
            title: 'Kontakt',
            body: 'adrian.mirwaldt21@gmail.com',
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: textTheme.bodyMedium?.copyWith(
              height: 1.55,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
