import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';

/// Bottom-Sheet zum Konvoi-Beitritt via 6-stelligem Einladungscode.
/// Designvorlage: Design.pdf Frame 5 (Join · Invite-Code) — Pull-Handle,
/// 6 große Mono-Code-Boxen, Paste-Button, "Beitreten"-CTA.
class ConvoyJoinSheet extends StatefulWidget {
  const ConvoyJoinSheet({super.key, this.prefillCode});

  final String? prefillCode;

  @override
  State<ConvoyJoinSheet> createState() => _ConvoyJoinSheetState();
}

class _ConvoyJoinSheetState extends State<ConvoyJoinSheet> {
  late final TextEditingController _codeController;
  final _focusNode = FocusNode();

  /// Server vergibt 6-stellige Codes — vgl. backend/src/util/invite_code.ts
  static const _codeLength = 6;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(
      text: (widget.prefillCode ?? '').toUpperCase(),
    );
    _codeController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _codeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _codeController.text.trim().length == _codeLength;

  void _submit() {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != _codeLength) return;
    Navigator.of(context).pop(code);
  }

  Future<void> _pasteCode() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = clip?.text?.trim() ?? '';
    if (raw.isEmpty) return;
    // Akzeptiere Codes mit/ohne Bindestriche/Spaces
    final cleaned =
        raw.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
    final code = cleaned.length > _codeLength
        ? cleaned.substring(0, _codeLength)
        : cleaned;
    _codeController.value = TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
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
            // Pull-Handle
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
            Text(
              'KONVOI BEITRETEN',
              style: AppTextStyles.sectionLabel,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Einladungscode',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              '6 Zeichen vom Crew-Leader. Beim Tippen wird\n'
              'automatisch UPPERCASE.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            // 6 Visual-Boxes über dem unsichtbaren TextField
            _CodeBoxRow(
              code: _codeController.text,
              length: _codeLength,
              onTap: () => _focusNode.requestFocus(),
            ),
            // Hidden input that the boxes mirror
            Offstage(
              child: TextField(
                key: const ValueKey('convoy-join-code-input'),
                controller: _codeController,
                focusNode: _focusNode,
                autofocus: widget.prefillCode == null,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                maxLength: _codeLength,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]')),
                  _UpperCaseTextFormatter(),
                ],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton.icon(
              key: const ValueKey('convoy-join-paste'),
              icon: const Icon(Icons.content_paste_rounded, size: 18),
              label: const Text('Aus Zwischenablage einfügen'),
              onPressed: _pasteCode,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              key: const ValueKey('convoy-join-submit'),
              onPressed: _canSubmit ? _submit : null,
              child: const Text('Beitreten'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeBoxRow extends StatelessWidget {
  const _CodeBoxRow({
    required this.code,
    required this.length,
    required this.onTap,
  });

  final String code;
  final int length;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < length; i++)
            _CodeBox(
              char: i < code.length ? code[i] : null,
              focused: code.length == i,
            ),
        ],
      ),
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.char, required this.focused});

  final String? char;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final filled = char != null;
    final accent = filled || focused;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 44,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled
            ? AppColors.orange.withValues(alpha: 0.16)
            : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadii.button),
        border: Border.all(
          color: accent ? AppColors.orange : AppColors.surfaceOutline,
          width: accent ? 1.6 : 0.8,
        ),
      ),
      child: Text(
        char ?? '',
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          fontFeatures: [FontFeature.tabularFigures()],
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
