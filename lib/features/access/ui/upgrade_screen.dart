import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/access_state.dart';
import '../providers/access_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/ui/auth_screens.dart';

class UpgradeScreen extends StatelessWidget {
  const UpgradeScreen({super.key});

  Future<void> _startTrial(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isSignedIn) {
      await openAccountSheet(context);
      if (!context.mounted) return;
      if (!context.read<AuthProvider>().isSignedIn) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Signed in. Tap Start Premium trial when you are ready.',
          ),
        ),
      );
      return;
    }

    await context.read<AccessProvider>().refresh();
    if (!context.mounted) return;
    final access = context.read<AccessProvider>().safeState;
    if (!access.canActivatePremiumTrial) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            access.hadTrialButExpired
                ? 'This account has already used its Premium trial.'
                : 'Premium access is already active.',
          ),
        ),
      );
      return;
    }

    final activated = await context
        .read<AccessProvider>()
        .activatePremiumTrial();
    if (!context.mounted) return;
    final updated = context.read<AccessProvider>().safeState;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          activated
              ? 'Premium Trial started. Ends ${updated.trialEndDateLabel}.'
              : 'Premium Trial could not be started.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<AccessProvider>().safeState;
    final auth = context.watch<AuthProvider>();
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
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                          access.isPremiumLike
                              ? access.badgeLabel
                              : 'Get more from Ripot Premium',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _AccessStatusText(access: access),
                  if (access.isFounding100) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Founding 100 • Founder #${access.founderNumber} • '
                      '${access.founderFirstYearDiscountPercent}% off your first paid year',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (messageTitle != null || messageBody != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withOpacity(0.55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (messageTitle != null)
                            Text(
                              messageTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (messageTitle != null && messageBody != null)
                            const SizedBox(height: 4),
                          if (messageBody != null) Text(messageBody),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FeatureChip('Up to 12 report images'),
                      _FeatureChip('Image labels'),
                      _FeatureChip('Custom letterhead'),
                      _FeatureChip('Remove Ripot branding'),
                      _FeatureChip('Advanced layout'),
                      _FeatureChip('Records and filters'),
                      _FeatureChip('Higher report/template limits'),
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
              onPressed: () => _startTrial(context),
              icon: const Icon(Icons.workspace_premium_outlined),
              label: Text(
                auth.isSignedIn
                    ? 'Start ${access.trialLengthDays}-day Premium trial'
                    : 'Sign in to start ${access.trialLengthDays}-day Premium trial',
              ),
            )
          else if (access.isPremiumLike)
            Card(
              child: ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text(
                  access.plan == RipotPlan.premium
                      ? 'Premium active'
                      : 'Premium trial active',
                ),
                subtitle: access.plan == RipotPlan.premium
                    ? const Text('Your Premium features are active.')
                    : Text(
                        access.trialEndDateLabel.isEmpty
                            ? '${access.daysRemaining} days remaining'
                            : '${access.daysRemaining} days remaining • Ends ${access.trialEndDateLabel}',
                      ),
              ),
            )
          else if (access.hadTrialButExpired && auth.isSignedIn)
            Card(
              child: ListTile(
                leading: const Icon(Icons.lock_clock_outlined),
                title: const Text('Premium Trial ended'),
                subtitle: Text(
                  access.premiumBillingEnabled
                      ? 'Choose a Premium plan to continue using premium features.'
                      : 'Premium subscriptions are being prepared for Google Play.',
                ),
                trailing: access.premiumBillingEnabled
                    ? FilledButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Premium Plans will be connected to Google Play Billing.',
                              ),
                            ),
                          );
                        },
                        child: const Text('View plans'),
                      )
                    : null,
              ),
            ),
          if (!access.isPremiumLike && access.canActivatePremiumTrial) ...[
            const SizedBox(height: 8),
            Text(
              'No payment is required to start the trial. One trial is available per Ripot account.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
          if (kDebugMode) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                await context.read<AccessProvider>().markPremium();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Premium enabled for testing.')),
                );
              },
              icon: const Icon(Icons.science_outlined),
              label: const Text('Enable premium for testing'),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Privacy note: Your reports remain on your device. Only basic account, subscription, and template information may be synced securely.',
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
    final auth = context.watch<AuthProvider>();

    if (!auth.isSignedIn) {
      return const Text(
        'Sign in to view your Premium status. Premium trials and subscriptions are linked to your Ripot account.',
      );
    }
    if (access.plan == RipotPlan.premium) {
      return const Text('Premium features are active.');
    }
    if (access.isTrialActive) {
      return Text(
        'Premium trial • ${access.daysRemaining} days remaining'
        '${access.trialEndDateLabel.isEmpty ? '' : ' • Ends ${access.trialEndDateLabel}'}',
      );
    }
    if (access.canActivatePremiumTrial) {
      return Text(
        'Try all Premium features free for ${access.trialLengthDays} days when you are ready.',
      );
    }
    if (access.hadTrialButExpired) {
      return const Text('This account has already used its Premium trial.');
    }
    return const Text('Free plan');
  }
}

class _PlanComparison extends StatelessWidget {
  const _PlanComparison();

  @override
  Widget build(BuildContext context) {
    final rows = <List<String>>[
      ['Core report creation', 'Yes', 'Yes'],
      ['Numeric fields + units', 'Yes', 'Yes'],
      ['PDF export', 'Yes', 'Yes'],
      ['Images per report', '4', '12'],
      ['Image labels', 'No', 'Yes'],
      ['Custom letterhead', 'No', 'Yes'],
      ['Ripot branding removed', 'No', 'Yes'],
      ['Advanced layout/margins', 'No', 'Yes'],
      ['Saved templates', '3', '20'],
      ['Saved reports', '10', '100'],
      ['Records table and filters', 'No', 'Yes'],
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
                Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'Feature',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'Free',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'Premium',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            ...rows.map(
              (row) => TableRow(
                children: row
                    .map(
                      (cell) => Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(cell),
                      ),
                    )
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
  Widget build(BuildContext context) => Chip(label: Text(text));
}
