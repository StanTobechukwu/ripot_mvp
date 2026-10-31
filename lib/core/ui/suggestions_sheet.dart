import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> showSuggestionsSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Suggest an improvement',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'Tell us what would make Ripot more useful. Please leave out patient details and clinical images.',
            ),
            const SizedBox(height: 16),
            const SelectableText('support@ripot.app'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Write email'),
                  onPressed: () async {
                    final uri = Uri(
                      scheme: 'mailto',
                      path: 'support@ripot.app',
                      query: 'subject=Ripot%20suggestion',
                    );
                    var opened = false;
                    try {
                      opened = await launchUrl(uri);
                    } catch (_) {}
                    if (!opened && sheetContext.mounted) {
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'No email app opened. Copy the address and use your usual email service.',
                          ),
                        ),
                      );
                    }
                  },
                ),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(
                      const ClipboardData(text: 'support@ripot.app'),
                    );
                    if (sheetContext.mounted)
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        const SnackBar(content: Text('Email address copied')),
                      );
                  },
                  child: const Text('Copy address'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
