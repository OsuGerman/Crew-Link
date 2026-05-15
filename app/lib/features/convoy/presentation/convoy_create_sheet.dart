import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

part 'convoy_create_steps.dart';

class CreateConvoyResult {
  const CreateConvoyResult({
    required this.name,
    this.thresholdMeters = 500.0,
  });
  final String name;
  final double thresholdMeters;
}

/// 3-Step-Bottom-Sheet zum Konvoi-Erstellen.
/// Designvorlage: Design.pdf Frame 5 (Erstellen-Sheet, 3 Schritte mit
/// Progress-Dots: Name → Warnabstand → Zusammenfassung).
class ConvoyCreateSheet extends StatefulWidget {
  const ConvoyCreateSheet({super.key});

  @override
  State<ConvoyCreateSheet> createState() => _ConvoyCreateSheetState();
}

class _ConvoyCreateSheetState extends State<ConvoyCreateSheet> {
  final _nameController = TextEditingController();
  final _pageController = PageController();
  int _step = 0;
  double _thresholdMeters = 500;

  static const _thresholdOptions = <(double, String)>[
    (300, '300 m'),
    (500, '500 m'),
    (1000, '1 km'),
  ];

  static const _titles = ['Konvoi starten', 'Warnabstand', 'Zusammenfassung'];
  static const _subtitles = [
    'Wähle einen Namen — den sehen alle die beitreten.',
    'Ab welchem Abstand soll Crew Link warnen?',
    'Prüfe nochmal, dann erstellen wir den Konvoi.',
  ];

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  bool get _nameValid => _nameController.text.trim().isNotEmpty;

  void _nextPage() => _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );

  void _prevPage() => _pageController.previousPage(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );

  void _submit() => Navigator.of(context).pop(
        CreateConvoyResult(
          name: _nameController.text.trim(),
          thresholdMeters: _thresholdMeters,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.md, AppSpacing.xl,
          MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Pull-handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surfaceOutline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Section-label "STEP X · ..."
            Text(
              'SCHRITT ${_step + 1} · ${_titles[_step].toUpperCase()}',
              style: AppTextStyles.sectionLabel,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            // Big title
            Text(
              _titles[_step],
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            // Subtitle
            Text(
              _subtitles[_step],
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            // Progress dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 3; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _step ? 28 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _step
                          ? AppColors.orange
                          : AppColors.surfaceOutline,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            // Step content
            SizedBox(
              height: 196,
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _step = i),
                children: [
                  _NameStep(
                    controller: _nameController,
                    onSubmitted: _nameValid ? _nextPage : null,
                  ),
                  _ThresholdStep(
                    value: _thresholdMeters,
                    options: _thresholdOptions,
                    onChanged: (v) => setState(() => _thresholdMeters = v),
                  ),
                  _ConfirmStep(
                    name: _nameController.text.trim(),
                    thresholdMeters: _thresholdMeters,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // CTA row: Zurück + Primary
            Row(
              children: [
                if (_step > 0)
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('convoy-create-back-btn'),
                      onPressed: _prevPage,
                      child: const Text('Zurück'),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: _step > 0 ? 2 : 1,
                  child: FilledButton(
                    key: ValueKey('convoy-create-step$_step-btn'),
                    onPressed: switch (_step) {
                      0 => _nameValid ? _nextPage : null,
                      1 => _nextPage,
                      _ => _submit,
                    },
                    child: Text(_step < 2 ? 'Weiter' : 'Konvoi erstellen'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
