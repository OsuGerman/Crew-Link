import 'package:flutter/material.dart';

class ConvoyJoinSheet extends StatefulWidget {
  const ConvoyJoinSheet({super.key, this.prefillCode});

  final String? prefillCode;

  @override
  State<ConvoyJoinSheet> createState() => _ConvoyJoinSheetState();
}

class _ConvoyJoinSheetState extends State<ConvoyJoinSheet> {
  late final TextEditingController _codeController;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.prefillCode);
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Konvoi beitreten',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            autofocus: widget.prefillCode == null,
            decoration: const InputDecoration(
              labelText: 'Einladungscode',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submit,
            child: const Text('Beitreten'),
          ),
        ],
      ),
    );
  }
}
