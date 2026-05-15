import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vehicle_mod.dart';
import '../../../core/models/vehicle_profile.dart';
import '../../../core/theme/app_theme.dart';
import '../application/vehicle_providers.dart';

/// Garage / Mein-Fahrzeug-Screen (Design.pdf Frame 10).
/// Hero-Card oben mit Marke/Modell/Year + Foto-Slot, darunter Specs als
/// 2×2-Grid, Mods als kategorie-gefärbte Chips, Save/Delete CTAs.
class VehicleProfileScreen extends ConsumerWidget {
  const VehicleProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myVehicleProvider);
    return async.when(
      loading: () => const _ScaffoldWith(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => _ScaffoldWith(
        body: _ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(myVehicleProvider),
        ),
      ),
      data: (vehicle) => _VehicleProfileForm(initial: vehicle),
    );
  }
}

class _ScaffoldWith extends StatelessWidget {
  const _ScaffoldWith({required this.body});
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mein Fahrzeug')),
      body: body,
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: AppColors.textMuted),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Fahrzeugdaten konnten nicht geladen werden.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            key: const ValueKey('vehicle-retry'),
            onPressed: onRetry,
            child: const Text('Erneut versuchen'),
          ),
        ],
      ),
    );
  }
}

class _VehicleProfileForm extends ConsumerStatefulWidget {
  const _VehicleProfileForm({required this.initial});
  final VehicleProfile? initial;

  @override
  ConsumerState<_VehicleProfileForm> createState() =>
      _VehicleProfileFormState();
}

class _VehicleProfileFormState extends ConsumerState<_VehicleProfileForm> {
  late final TextEditingController _makeController;
  late final TextEditingController _modelController;
  late final TextEditingController _yearController;
  late final TextEditingController _colorController;
  late final TextEditingController _powerKwController;
  late final TextEditingController _displacementController;
  String? _drivetrain;
  String? _transmissionType;
  late List<VehicleMod> _mods;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  static const int _yearLowerBound = 1900;
  static const int _yearUpperOffsetFromNow = 2;
  static const int _maxMods = 30;

  @override
  void initState() {
    super.initState();
    final v = widget.initial;
    _makeController = TextEditingController(text: v?.make ?? '');
    _modelController = TextEditingController(text: v?.model ?? '');
    _yearController = TextEditingController(text: v?.year?.toString() ?? '');
    _colorController = TextEditingController(text: v?.color ?? '');
    _powerKwController =
        TextEditingController(text: v?.powerKw?.toString() ?? '');
    _displacementController =
        TextEditingController(text: v?.displacement?.toString() ?? '');
    _drivetrain = v?.drivetrain;
    _transmissionType = v?.transmissionType;
    _mods = List<VehicleMod>.from(v?.mods ?? const <VehicleMod>[]);
    // Refresh hero-card when name fields change
    _makeController.addListener(() => setState(() {}));
    _modelController.addListener(() => setState(() {}));
    _yearController.addListener(() => setState(() {}));
    _powerKwController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _colorController.dispose();
    _powerKwController.dispose();
    _displacementController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || _saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(myVehicleProvider.notifier).save(
            make: _makeController.text.trim(),
            model: _modelController.text.trim(),
            year: int.tryParse(_yearController.text.trim()),
            color: _colorController.text.trim().isEmpty
                ? null
                : _colorController.text.trim(),
            powerKw: int.tryParse(_powerKwController.text.trim()),
            drivetrain: _drivetrain,
            displacement: int.tryParse(_displacementController.text.trim()),
            transmissionType: _transmissionType,
            mods: _mods,
          );
      if (mounted) navigator.pop();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addMod() async {
    if (_mods.length >= _maxMods) return;
    final result = await showModalBottomSheet<VehicleMod>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddModSheet(),
    );
    if (result == null || !mounted) return;
    setState(() => _mods = [..._mods, result]);
  }

  void _removeMod(VehicleMod mod) {
    setState(() => _mods = _mods.where((m) => m.id != mod.id).toList());
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Fahrzeug entfernen?'),
        content: const Text('Dein Fahrzeug-Profil wird gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(myVehicleProvider.notifier).clear();
      if (mounted) navigator.pop();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Entfernen fehlgeschlagen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateRequired(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label angeben';
    return null;
  }

  String? _validatePositiveInt(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return 'Positive Ganzzahl erwartet';
    return null;
  }

  String? _validateYear(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return 'Ganzzahl erwartet';
    final maxYear = DateTime.now().year + _yearUpperOffsetFromNow;
    if (parsed < _yearLowerBound || parsed > maxYear) {
      return 'Zwischen $_yearLowerBound und $maxYear';
    }
    return null;
  }

  int? _powerPs() {
    final kw = int.tryParse(_powerKwController.text.trim());
    if (kw == null) return null;
    return (kw * 1.35962).round();
  }

  @override
  Widget build(BuildContext context) {
    final hasExisting = widget.initial != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mein Fahrzeug'),
        actions: [
          if (hasExisting)
            IconButton(
              key: const ValueKey('vehicle-remove'),
              tooltip: 'Fahrzeug entfernen',
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.danger),
              onPressed: _saving ? null : _remove,
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeroCard(
                  make: _makeController.text.trim(),
                  model: _modelController.text.trim(),
                  year: _yearController.text.trim(),
                  powerPs: _powerPs(),
                ),
                const SizedBox(height: AppSpacing.xl),
                _SectionLabel(label: 'FAHRZEUG'),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const ValueKey('vehicle-make'),
                  controller: _makeController,
                  decoration: const InputDecoration(
                    labelText: 'Marke',
                    hintText: 'z. B. Tesla, BMW, Porsche',
                  ),
                  validator: (v) => _validateRequired(v, 'Marke'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const ValueKey('vehicle-model'),
                  controller: _modelController,
                  decoration: const InputDecoration(
                    labelText: 'Modell',
                    hintText: 'z. B. Model 3, M2, 911 GT3',
                  ),
                  validator: (v) => _validateRequired(v, 'Modell'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('vehicle-year'),
                        controller: _yearController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Baujahr',
                        ),
                        validator: _validateYear,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('vehicle-color'),
                        controller: _colorController,
                        decoration: const InputDecoration(
                          labelText: 'Farbe',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                _SectionLabel(label: 'SPEZIFIKATIONEN'),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('vehicle-power-kw'),
                        controller: _powerKwController,
                        keyboardType: TextInputType.number,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'Leistung (kW)',
                          hintText: '375',
                        ),
                        validator: _validatePositiveInt,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('vehicle-displacement'),
                        controller: _displacementController,
                        keyboardType: TextInputType.number,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'Hubraum (ccm)',
                          hintText: '2997',
                        ),
                        validator: _validatePositiveInt,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  key: const ValueKey('vehicle-drivetrain'),
                  initialValue: _drivetrain,
                  decoration: const InputDecoration(labelText: 'Antrieb'),
                  items: const [
                    DropdownMenuItem(value: 'FWD', child: Text('FWD · Vorderrad')),
                    DropdownMenuItem(value: 'RWD', child: Text('RWD · Hinterrad')),
                    DropdownMenuItem(value: 'AWD', child: Text('AWD · Allrad')),
                    DropdownMenuItem(value: '4WD', child: Text('4WD · Allrad gesperrt')),
                  ],
                  onChanged:
                      _saving ? null : (v) => setState(() => _drivetrain = v),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  key: const ValueKey('vehicle-transmission'),
                  initialValue: _transmissionType,
                  decoration: const InputDecoration(labelText: 'Getriebe'),
                  items: const [
                    DropdownMenuItem(value: 'manual', child: Text('Schaltgetriebe')),
                    DropdownMenuItem(value: 'automatic', child: Text('Automatik')),
                    DropdownMenuItem(value: 'dct', child: Text('DCT · Doppelkupplung')),
                    DropdownMenuItem(value: 'cvt', child: Text('CVT · Stufenlos')),
                    DropdownMenuItem(value: 'electric', child: Text('Elektroantrieb')),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _transmissionType = v),
                ),
                const SizedBox(height: AppSpacing.xl),
                _ModsSection(
                  mods: _mods,
                  onAdd: _addMod,
                  onRemove: _removeMod,
                  maxMods: _maxMods,
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  key: const ValueKey('vehicle-save'),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  onPressed: _saving ? null : _save,
                  label: Text(_saving ? 'Speichern …' : 'Speichern'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Orange section label im All-Caps-Look. Wird mehrfach verwendet im Screen.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) =>
      Text(label, style: AppTextStyles.sectionLabel);
}

/// Hero-Car-Card oben am Screen — orange-akzentuiert mit Auto-Icon-Placeholder
/// und Live-Preview von Marke + Modell + Baujahr + PS-Angabe.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.make,
    required this.model,
    required this.year,
    required this.powerPs,
  });

  final String make;
  final String model;
  final String year;
  final int? powerPs;

  @override
  Widget build(BuildContext context) {
    final hasName = make.isNotEmpty || model.isNotEmpty;
    final title = hasName
        ? '${make.isNotEmpty ? make : ''}${make.isNotEmpty && model.isNotEmpty ? ' ' : ''}$model'
        : 'Neues Fahrzeug';
    final subtitle = [
      if (year.isNotEmpty) year,
      if (powerPs != null) '$powerPs PS',
    ].join(' · ');

    return Container(
      key: const ValueKey('vehicle-hero-card'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.orange.withValues(alpha: 0.16),
            AppColors.surfaceHigh,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.orange, width: 1.4),
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border:
                  Border.all(color: AppColors.surfaceOutline, width: 0.6),
            ),
            child: const Icon(
              Icons.directions_car_filled_rounded,
              color: AppColors.orange,
              size: 36,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'MEIN FAHRZEUG',
                  style: AppTextStyles.sectionLabel.copyWith(fontSize: 10),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mods-Sektion: Header mit Counter + "Hinzufügen"-Button, darunter
/// kategorie-gefärbte Chips als Wrap. Empty-State mit Hint.
class _ModsSection extends StatelessWidget {
  const _ModsSection({
    required this.mods,
    required this.onAdd,
    required this.onRemove,
    required this.maxMods,
  });

  final List<VehicleMod> mods;
  final VoidCallback onAdd;
  final void Function(VehicleMod) onRemove;
  final int maxMods;

  static const _categoryColors = <String, Color>{
    'engine': Color(0xFFE94560), // Coral-red
    'wheels': Color(0xFF4F8DFD), // Blue
    'exterior': Color(0xFFFF6B2C), // Orange (brand)
    'interior': Color(0xFFA855F7), // Purple
    'audio': Color(0xFF06B6D4), // Teal
    'electronics': Color(0xFF22C55E), // Green
  };

  Color _colorFor(String? category) {
    if (category == null) return AppColors.textMuted;
    return _categoryColors[category] ?? AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = mods.length < maxMods;
    return Column(
      key: const ValueKey('vehicle-mods-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const _SectionLabel(label: 'MODS'),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${mods.length}/$maxMods',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            TextButton.icon(
              key: const ValueKey('vehicle-mods-add'),
              onPressed: canAdd ? onAdd : null,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Hinzufügen'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (mods.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(
                color: AppColors.surfaceOutline,
                width: 0.6,
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.tune_rounded,
                    color: AppColors.textMuted, size: 22),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Noch keine Mods. Tippe Hinzufügen, um z. B. dein '
                    'Sport-Fahrwerk zu ergänzen.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final mod in mods)
                _ModChip(
                  key: ValueKey('vehicle-mod-row-${mod.id}'),
                  mod: mod,
                  color: _colorFor(mod.category),
                  onRemove: () => onRemove(mod),
                ),
            ],
          ),
      ],
    );
  }
}

class _ModChip extends StatelessWidget {
  const _ModChip({
    super.key,
    required this.mod,
    required this.color,
    required this.onRemove,
  });

  final VehicleMod mod;
  final Color color;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            mod.name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            iconSize: 16,
            icon: Icon(Icons.close_rounded, color: color),
            tooltip: 'Mod entfernen',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Bottom-Sheet zum Mod-Hinzufügen — ersetzt den alten Dialog für ein
/// iOS-style Look-and-Feel. Kategorie-Pillen statt Dropdown.
class _AddModSheet extends StatefulWidget {
  const _AddModSheet();

  @override
  State<_AddModSheet> createState() => _AddModSheetState();
}

class _AddModSheetState extends State<_AddModSheet> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String? _category;

  static const _categories = <(String, String, Color)>[
    ('engine', 'Motor', Color(0xFFE94560)),
    ('wheels', 'Räder', Color(0xFF4F8DFD)),
    ('exterior', 'Außen', Color(0xFFFF6B2C)),
    ('interior', 'Innen', Color(0xFFA855F7)),
    ('audio', 'Audio', Color(0xFF06B6D4)),
    ('electronics', 'Elektronik', Color(0xFF22C55E)),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  bool get _canSubmit => _nameController.text.trim().isNotEmpty;

  void _submit() {
    Navigator.of(context).pop(VehicleMod(
      id: 'draft-${DateTime.now().microsecondsSinceEpoch}',
      name: _nameController.text.trim(),
      description: _descController.text.trim().isEmpty
          ? null
          : _descController.text.trim(),
      category: _category,
    ));
  }

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
            const _SectionLabel(label: 'MOD HINZUFÜGEN'),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Was hast du am Auto modifiziert?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              key: const ValueKey('add-mod-name'),
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'z. B. KW V3 Fahrwerk',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final (key, label, color) in _categories)
                  _CategoryChip(
                    key: ValueKey('add-mod-cat-$key'),
                    label: label,
                    color: color,
                    selected: _category == key,
                    onTap: () => setState(
                      () => _category = _category == key ? null : key,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('add-mod-description'),
              controller: _descController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Beschreibung (optional)',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              key: const ValueKey('add-mod-submit'),
              onPressed: _canSubmit ? _submit : null,
              child: const Text('Hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.22)
                : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
              color: selected ? color : AppColors.surfaceOutline,
              width: selected ? 1.4 : 0.6,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? color : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
