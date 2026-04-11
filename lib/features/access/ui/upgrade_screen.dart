import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/access_provider.dart';

class UpgradeScreen extends StatelessWidget {
  const UpgradeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final access = context.watch<AccessProvider>().safeState;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Ripot Premium')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Current plan: ${access.badgeLabel}', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    access.isEarlyUser
                        ? 'You qualify for an extended premium trial.'
                        : 'Try premium features before deciding.',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _FeatureChip('Remove Ripot branding'),
                      _FeatureChip('Image labels'),
                      _FeatureChip('Custom letterhead'),
                      _FeatureChip('Custom margins'),
                      _FeatureChip('Higher limits'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const _PlanComparison(),
          const SizedBox(height: 16),
          if (!access.isPremiumLike && !access.hasUsedTrial)
            FilledButton.icon(
              onPressed: () async {
                await context.read<AccessProvider>().startTrial();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Premium trial started for ${access.trialLengthDays} days.')),
                );
              },
              icon: const Icon(Icons.rocket_launch_outlined),
              label: Text(access.isEarlyUser ? 'Start ${access.trialLengthDays}-day early trial' : 'Start free trial'),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await context.read<AccessProvider>().markPremium();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Premium enabled for testing.')),
              );
            },
            icon: const Icon(Icons.workspace_premium_outlined),
            label: const Text('Enable premium for testing'),
          ),
          const SizedBox(height: 12),
          Text(
            'Reports remain on-device. Only account, trial, premium status, and structure-only template sync should go to Firebase.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PlanComparison extends StatelessWidget {
  const _PlanComparison();

  @override
  Widget build(BuildContext context) {
    final rows = <List<String>>[
      ['PDF export', 'Yes', 'Yes'],
      ['Ripot branding removed', 'No', 'Yes'],
      ['Image labels', 'No', 'Yes'],
      ['Custom letterhead', 'No', 'Yes'],
      ['Custom margins', 'No', 'Yes'],
      ['Saved templates', '3', '20'],
      ['Saved reports', '10', '100'],
      ['Images per report', '4', '12'],
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(2.3),
            1: FlexColumnWidth(),
            2: FlexColumnWidth(),
          },
          children: [
            const TableRow(
              children: [
                Padding(padding: EdgeInsets.all(8), child: Text('Feature', style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(padding: EdgeInsets.all(8), child: Text('Free', style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(padding: EdgeInsets.all(8), child: Text('Premium', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
            ...rows.map(
              (row) => TableRow(
                children: row
                    .map((cell) => Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(cell),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final String text;
  const _FeatureChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(text));
  }
}
