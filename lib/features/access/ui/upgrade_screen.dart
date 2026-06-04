import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/access_state.dart';
import '../providers/access_provider.dart';

class UpgradeScreen extends StatelessWidget {
  const UpgradeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final access = context.watch<AccessProvider>().safeState;
    final theme = Theme.of(context);
    final messageTitle = access.premiumMessageTitle;
    final messageBody = access.premiumMessageBody;

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
                  _AccessStatusText(access: access),
                  if (messageTitle != null || messageBody != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (messageTitle != null)
                            Text(messageTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
                          if (messageTitle != null && messageBody != null) const SizedBox(height: 4),
                          if (messageBody != null) Text(messageBody),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _FeatureChip('Remove Ripot branding'),
                      _FeatureChip('Image labels'),
                      _FeatureChip('Custom letterhead'),
                      _FeatureChip('Custom margins'),
                      _FeatureChip('Records table and filters'),
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
          if (access.canActivatePremiumTrial)
            FilledButton.icon(
              onPressed: () async {
                final activated = await context.read<AccessProvider>().activatePremiumTrial();
                if (!context.mounted) return;
                final updated = context.read<AccessProvider>().safeState;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      activated
                          ? 'Premium Trial activated until ${updated.trialEndDateLabel}.'
                          : 'Premium Trial is already active.',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.rocket_launch_outlined),
              label: Text(
                access.isEarlyUser
                    ? 'Activate ${access.trialLengthDays}-day Premium Trial'
                    : 'Start free trial',
              ),
            )
          else if (access.isPremiumLike)
            Card(
              child: ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('Premium Trial active'),
                subtitle: Text(
                  access.trialEndDateLabel.isEmpty
                      ? '${access.daysRemaining} days remaining'
                      : '${access.daysRemaining} days remaining • Ends ${access.trialEndDateLabel}',
                ),
              ),
            )
          else if (access.hadTrialButExpired)
            Card(
              child: ListTile(
                leading: const Icon(Icons.lock_clock_outlined),
                title: const Text('Premium Trial ended'),
                subtitle: Text(
                  access.premiumBillingEnabled
                      ? 'See Premium Plans to continue using premium features.'
                      : 'Premium billing is not available yet. Please check again after the next update.',
                ),
                trailing: access.premiumBillingEnabled
                    ? FilledButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Premium Plans will be connected to Google Play Billing.')),
                          );
                        },
                        child: const Text('See Premium Plans'),
                      )
                    : null,
              ),
            ),
          if (kDebugMode) ...[
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
          ],
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

class _AccessStatusText extends StatelessWidget {
  final AccessState access;
  const _AccessStatusText({required this.access});

  @override
  Widget build(BuildContext context) {
    if (access.isPremiumLike) {
      return Text(
        access.trialEndDateLabel.isEmpty
            ? 'Premium features are active.'
            : 'Premium Trial is active until ${access.trialEndDateLabel}.',
      );
    }
    if (access.canActivatePremiumTrial && access.isEarlyUser) {
      return Text(
        'You qualify for an extended ${access.trialLengthDays}-day Premium Trial. Activate it to unlock premium features.',
      );
    }
    if (access.hadTrialButExpired) {
      return const Text('Your Premium Trial has ended.');
    }
    return const Text('Try premium features before deciding.');
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
      ['Records table and filters', 'No', 'Yes'],
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
