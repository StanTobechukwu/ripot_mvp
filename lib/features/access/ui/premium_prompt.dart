import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../providers/access_provider.dart';
import 'premium_access_action.dart';
import 'upgrade_screen.dart';

enum PremiumFeature {
  moreImages,
  imageLabels,
  customLetterhead,
  removeBranding,
  customMargins,
  records,
  registry,
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
        title: 'Records is included with Premium',
        body:
            'Organize finalized reports in searchable tables, with filters to help you find them.',
      );
    case PremiumFeature.registry:
      return const PremiumPromptContent(
        title: 'Registry is included with Premium',
        body:
            'Keep patient details and dated updates together in your registry.',
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
            'Free keeps up to 10 finalized reports on this device; Premium keeps up to 100. Drafts do not count. Your existing reports stay available.',
      );
    case PremiumFeature.advancedLayout:
      return const PremiumPromptContent(
        title: 'Use advanced report layout',
        body: 'Advanced layout controls are available with Ripot Premium.',
      );
  }
}

Future<bool> showPremiumFeatureSheet(
  BuildContext context,
  PremiumFeature feature, {
  String? message,
}) async {
  if (context.read<AccessProvider>().safeState.isPremiumLike) return true;
  final copy = premiumPromptContent(feature);
  final unlocked = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              copy.title,
              style: Theme.of(
                sheetContext,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (message != null) ...[Text(message), const SizedBox(height: 8)],
            Text(copy.body),
            const SizedBox(height: 12),
            PremiumAccessAction(
              onUnlocked: () => Navigator.pop(sheetContext, true),
              onViewPlans: () async {
                await Navigator.push(
                  sheetContext,
                  MaterialPageRoute<void>(
                    builder: (_) => const UpgradeScreen(),
                  ),
                );
                if (sheetContext.mounted &&
                    sheetContext
                        .read<AccessProvider>()
                        .safeState
                        .isPremiumLike) {
                  Navigator.pop(sheetContext, true);
                }
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext, false),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    ),
  );
  return unlocked == true &&
      context.mounted &&
      context.read<AccessProvider>().safeState.isPremiumLike;
}
