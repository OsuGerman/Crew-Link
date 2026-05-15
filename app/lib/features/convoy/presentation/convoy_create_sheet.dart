import 'package:flutter/material.dart';

part 'convoy_create_steps.dart';

class CreateConvoyResult {
  const CreateConvoyResult({
    required this.name,
    this.thresholdMeters = 500.0,
  });
  final String name;
  final double thresholdMeters;
}

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
        duration: const Duration(milliseconds: 260),
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
    final scheme = Theme.of(context).colorScheme;
    const titles = ['Konvoi erstellen', 'Warnabstand', 'Zusammenfassung'];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24, 16, 24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titles[_step], style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _step ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _step
                        ? scheme.primary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
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
          const SizedBox(height: 16),
          FilledButton(
            key: ValueKey('convoy-create-step$_step-btn'),
            onPressed: switch (_step) {
              0 => _nameValid ? _nextPage : null,
              1 => _nextPage,
              _ => _submit,
            },
            child: Text(_step < 2 ? 'Weiter' : 'Erstellen'),
          ),
        ],
      ),
    );
  }
}
