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
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'z. B. Schwarzwald Sonntag',
            labelText: 'Konvoi-Name',
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final (meters, label) in options)
              _ThresholdChip(
                key: ValueKey('threshold-chip-${meters.toInt()}'),
                label: label,
                selected: value == meters,
                onTap: () => onChanged(meters),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadii.button),
            border: Border.all(
              color: AppColors.surfaceOutline,
              width: 0.6,
            ),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.orange, size: 18),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Crew Link warnt akustisch sobald ein Mitglied über '
                  'die Schwelle hinaus abgehängt wurde.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThresholdChip extends StatelessWidget {
  const _ThresholdChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadii.button),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.orange.withValues(alpha: 0.18)
                    : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(AppRadii.button),
                border: Border.all(
                  color: selected
                      ? AppColors.orange
                      : AppColors.surfaceOutline,
                  width: selected ? 1.6 : 0.6,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppColors.orange
                      : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmStep extends StatelessWidget {
  const _ConfirmStep({required this.name, required this.thresholdMeters});
  final String name;
  final double thresholdMeters;

  @override
  Widget build(BuildContext context) {
    final label = thresholdMeters >= 1000
        ? '${(thresholdMeters / 1000).toStringAsFixed(0)} km'
        : '${thresholdMeters.toInt()} m';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.surfaceOutline, width: 0.6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ConfirmRow(label: 'Name', value: name),
          const SizedBox(height: AppSpacing.md),
          const Divider(color: AppColors.surfaceOutline, height: 1),
          const SizedBox(height: AppSpacing.md),
          _ConfirmRow(label: 'Warnabstand', value: label),
        ],
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
