part of 'convoy_create_sheet.dart';

class _NameStep extends StatelessWidget {
  const _NameStep({required this.controller, this.onSubmitted});
  final TextEditingController controller;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Konvoi-Name',
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: onSubmitted != null ? (_) => onSubmitted!() : null,
        ),
      ],
    );
  }
}

class _ThresholdStep extends StatelessWidget {
  const _ThresholdStep({
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final double value;
  final List<(double, String)> options;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ab welchem Abstand soll Crew Link warnen?',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final (meters, label) in options)
              ChoiceChip(
                key: ValueKey('threshold-chip-${meters.toInt()}'),
                label: Text(label),
                selected: value == meters,
                onSelected: (_) => onChanged(meters),
              ),
          ],
        ),
      ],
    );
  }
}

class _ConfirmStep extends StatelessWidget {
  const _ConfirmStep({required this.name, required this.thresholdMeters});
  final String name;
  final double thresholdMeters;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = thresholdMeters >= 1000
        ? '${(thresholdMeters / 1000).toStringAsFixed(0)} km'
        : '${thresholdMeters.toInt()} m';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Name', style: TextStyle(color: scheme.onSurfaceVariant)),
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Warnabstand',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}
