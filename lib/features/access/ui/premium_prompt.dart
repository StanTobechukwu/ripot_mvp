import 'package:flutter/material.dart';

import 'upgrade_screen.dart';

enum PremiumFeature {
  moreImages,
  imageLabels,
  customLetterhead,
  removeBranding,
  customMargins,
  records,
  premiumTemplate,
  moreTemplates,
  moreReports,
  advancedLayout,
}

class PremiumPromptContent {
  final String title;
  final String body;
  const PremiumPromptContent({required this.title, required this.body});
}

PremiumPromptContent premiumPromptContent(PremiumFeature feature) {
  switch (feature) {
    case PremiumFeature.moreImages:
      return const PremiumPromptContent(
        title: 'Need more report images?',
        body:
            'Your Free plan supports up to 4 images per report. Premium supports up to 12.',
      );
    case PremiumFeature.imageLabels:
      return const PremiumPromptContent(
        title: 'Add labels to report images',
        body:
            'Image labels are available with Ripot Premium for clearer, more professional reports.',
      );
    case PremiumFeature.customLetterhead:
      return const PremiumPromptContent(
        title: 'Use your own letterhead',
        body:
            'Premium lets you create professional reports with your custom facility letterhead.',
      );
    case PremiumFeature.removeBranding:
      return const PremiumPromptContent(
        title: 'Make the report fully yours',
        body: 'Premium removes Ripot branding from exported reports.',
      );
    case PremiumFeature.customMargins:
      return const PremiumPromptContent(
        title: 'Fine-tune your report layout',
        body: 'Custom margins are available with Ripot Premium.',
      );
    case PremiumFeature.records:
      return const PremiumPromptContent(
        title: 'Turn reports into structured records',
        body:
            'Premium unlocks Records, filtering and structured-data workflows.',
      );
    case PremiumFeature.premiumTemplate:
      return const PremiumPromptContent(
        title: 'Use this Premium template',
        body:
            'Premium specialty templates are available during your trial and with Premium.',
      );
    case PremiumFeature.moreTemplates:
      return const PremiumPromptContent(
        title: 'Save more templates',
        body:
            'You have reached the Free template limit. Premium increases your saved-template allowance.',
      );
    case PremiumFeature.moreReports:
      return const PremiumPromptContent(
        title: 'Save more reports',
        body:
            'You have reached the Free saved-report limit. Premium increases your report allowance.',
      );
    case PremiumFeature.advancedLayout:
      return const PremiumPromptContent(
        title: 'Use advanced report layout',
        body: 'Advanced layout controls are available with Ripot Premium.',
      );
  }
}

Future<void> showPremiumFeatureSheet(
  BuildContext context,
  PremiumFeature feature,
) async {
  final copy = premiumPromptContent(feature);
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.workspace_premium_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      copy.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(copy.body),
              const SizedBox(height: 8),
              Text(
                'Start your available Premium trial or view Premium options.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext, 'premium'),
                child: const Text('See Premium'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext, 'later'),
                child: const Text('Continue with Free'),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (action == 'premium' && context.mounted) {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UpgradeScreen()),
    );
  }
}
