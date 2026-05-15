import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../application/beta_feedback_provider.dart';
import '../domain/beta_feedback.dart';

/// Shows a modal bottom sheet for beta testers to submit feedback.
///
/// Usage:
///   BetaFeedbackSheet.show(context, screenContext: 'ActiveConvoyView');
class BetaFeedbackSheet extends ConsumerStatefulWidget {
  const BetaFeedbackSheet({super.key, this.screenContext = ''});

  final String screenContext;

  static Future<void> show(
    BuildContext context, {
    String screenContext = '',
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => BetaFeedbackSheet(screenContext: screenContext),
      );

  @override
  ConsumerState<BetaFeedbackSheet> createState() => _BetaFeedbackSheetState();
}

class _BetaFeedbackSheetState extends ConsumerState<BetaFeedbackSheet> {
  final _controller = TextEditingController();
  var _category = FeedbackCategory.bug;
  String _buildVersion = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _buildVersion = '${info.version}+${info.buildNumber}');
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final submitState = ref.watch(betaFeedbackProvider);
    final notifier = ref.read(betaFeedbackProvider.notifier);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    ref.listen<FeedbackSubmitState>(betaFeedbackProvider, (_, state) {
      if (state == FeedbackSubmitState.success) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feedback gesendet — danke!')),
        );
      } else if (state == FeedbackSubmitState.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Senden. Bitte erneut versuchen.')),
        );
        notifier.reset();
      }
    });

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Beta-Feedback',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<FeedbackCategory>(
            value: _category,
            decoration: const InputDecoration(
              labelText: 'Kategorie',
              border: OutlineInputBorder(),
            ),
            items: FeedbackCategory.values
                .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                .toList(),
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Beschreibung',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: submitState == FeedbackSubmitState.submitting
                ? null
                : () => notifier.submit(
                      category: _category,
                      message: _controller.text,
                      buildVersion: _buildVersion,
                      screenContext: widget.screenContext,
                    ),
            child: submitState == FeedbackSubmitState.submitting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Feedback senden'),
          ),
        ],
      ),
    );
  }
}
