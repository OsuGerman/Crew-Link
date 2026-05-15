import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vehicle_mod.dart';
import '../../../core/models/vehicle_profile.dart';
import '../application/vehicle_providers.dart';

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
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 12),
          Text(
            'Fahrzeugdaten konnten nicht geladen werden.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
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
    if (!(_formKey.currentState?.validate() ?? false) || _saving) {
      return;
    }
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
    final result = await showDialog<VehicleMod>(
      context: context,
      builder: (_) => const _AddModDialog(),
    );
    if (result == null || !mounted) return;
    setState(() => _mods = [..._mods, result]);
  }

  void _removeMod(VehicleMod mod) {
    setState(() => _mods = _mods.where((m) => m.id != mod.id).toList());
  }

  Future<void> _remove() async {
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
    if (value == null || value.trim().isEmpty) {
      return '$label angeben';
    }
    return null;
  }

  String? _validatePositiveInt(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return 'Positive Ganzzahl erwartet';
    return null;
  }

  String? _validateYear(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return 'Ganzzahl erwartet';
    final maxYear = DateTime.now().year + _yearUpperOffsetFromNow;
    if (parsed < _yearLowerBound || parsed > maxYear) {
      return 'Zwischen $_yearLowerBound und $maxYear';
    }
    return null;
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
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _remove,
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('vehicle-make'),
                  controller: _makeController,
                  decoration: const InputDecoration(
                    labelText: 'Marke',
                    helperText: 'z. B. Tesla, BMW, Porsche',
                  ),
                  validator: (v) => _validateRequired(v, 'Marke'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('vehicle-model'),
                  controller: _modelController,
                  decoration: const InputDecoration(
                    labelText: 'Modell',
                    helperText: 'z. B. Model 3 Performance, M2, 911 GT3',
                  ),
                  validator: (v) => _validateRequired(v, 'Modell'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('vehicle-year'),
                  controller: _yearController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Baujahr (optional)',
                  ),
                  validator: _validateYear,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('vehicle-color'),
                  controller: _colorController,
                  decoration: const InputDecoration(
                    labelText: 'Farbe (optional)',
                    helperText: 'z. B. Nardograu, Indigoblau, Schwarz',
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Spezifikationen (optional)',
                  key: const ValueKey('vehicle-specs-header'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('vehicle-power-kw'),
                  controller: _powerKwController,
                  keyboardType: TextInputType.number,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Leistung (kW)',
                    helperText: 'z. B. 375 für ~510 PS',
                  ),
                  validator: _validatePositiveInt,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('vehicle-displacement'),
                  controller: _displacementController,
                  keyboardType: TextInputType.number,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Hubraum (ccm)',
                    helperText: 'z. B. 2997 für einen 3,0-Liter-Motor',
                  ),
                  validator: _validatePositiveInt,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const ValueKey('vehicle-drivetrain'),
                  initialValue: _drivetrain,
                  decoration: const InputDecoration(labelText: 'Antrieb'),
                  items: const [
                    DropdownMenuItem(
                        value: 'FWD',
                        child: Text('Vorderradantrieb (FWD)')),
                    DropdownMenuItem(
                        value: 'RWD',
                        child: Text('Hinterradantrieb (RWD)')),
                    DropdownMenuItem(
                        value: 'AWD', child: Text('Allradantrieb (AWD)')),
                    DropdownMenuItem(
                        value: '4WD',
                        child: Text('Allrad mit Sperre (4WD)')),
                  ],
                  onChanged:
                      _saving ? null : (v) => setState(() => _drivetrain = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const ValueKey('vehicle-transmission'),
                  initialValue: _transmissionType,
                  decoration: const InputDecoration(labelText: 'Getriebe'),
                  items: const [
                    DropdownMenuItem(
                        value: 'manual', child: Text('Schaltgetriebe')),
                    DropdownMenuItem(
                        value: 'automatic', child: Text('Automatik')),
                    DropdownMenuItem(
                        value: 'dct',
                        child: Text('Doppelkupplungsgetriebe (DCT)')),
                    DropdownMenuItem(
                        value: 'cvt',
                        child: Text('Stufenlosgetriebe (CVT)')),
                    DropdownMenuItem(
                        value: 'electric', child: Text('Elektroantrieb')),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _transmissionType = v),
                ),
                const SizedBox(height: 24),
                _ModsSection(
                  mods: _mods,
                  onAdd: _addMod,
                  onRemove: _removeMod,
                  maxMods: _maxMods,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const ValueKey('vehicle-save'),
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check),
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

  @override
  Widget build(BuildContext context) {
    final canAdd = mods.length < maxMods;
    return Container(
      key: const ValueKey('vehicle-mods-section'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, size: 20),
              const SizedBox(width: 6),
              Text(
                'Mods (${mods.length})',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton.icon(
                key: const ValueKey('vehicle-mods-add'),
                onPressed: canAdd ? onAdd : null,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Hinzufügen'),
              ),
            ],
          ),
          if (mods.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: Text(
                'Noch keine Mods. Tippe auf „Hinzufügen", um deine erste hinzuzufügen.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            )
          else
            for (final mod in mods)
              ListTile(
                key: ValueKey('vehicle-mod-row-${mod.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(mod.name,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                subtitle: _modSubtitle(mod) == null
                    ? null
                    : Text(_modSubtitle(mod)!),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Mod entfernen',
                  onPressed: () => onRemove(mod),
                ),
              ),
        ],
      ),
    );
  }

  String? _modSubtitle(VehicleMod mod) {
    final parts = <String>[];
    if (mod.category != null && mod.category!.trim().isNotEmpty) {
      parts.add(mod.category!);
    }
    if (mod.description != null && mod.description!.trim().isNotEmpty) {
      parts.add(mod.description!);
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

class _AddModDialog extends StatefulWidget {
  const _AddModDialog();

  @override
  State<_AddModDialog> createState() => _AddModDialogState();
}

class _AddModDialogState extends State<_AddModDialog> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String? _category;

  static const _categories = <String>[
    'engine',
    'wheels',
    'exterior',
    'interior',
    'audio',
    'electronics',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mod hinzufügen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('add-mod-name'),
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const ValueKey('add-mod-category'),
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Kategorie'),
            items: _categories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('add-mod-description'),
            controller: _descController,
            decoration: const InputDecoration(labelText: 'Beschreibung'),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const ValueKey('add-mod-submit'),
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop(VehicleMod(
              id: 'draft-${DateTime.now().microsecondsSinceEpoch}',
              name: name,
              description: _descController.text.trim().isEmpty
                  ? null
                  : _descController.text.trim(),
              category: _category,
            ));
          },
          child: const Text('Hinzufügen'),
        ),
      ],
    );
  }
}
