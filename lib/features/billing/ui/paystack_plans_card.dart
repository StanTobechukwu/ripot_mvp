import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/providers/auth_provider.dart';
import '../../access/providers/access_provider.dart';
import '../paystack_billing.dart';

class PaystackPlansCard extends StatefulWidget {
  const PaystackPlansCard({super.key});
  @override
  State<PaystackPlansCard> createState() => _PaystackPlansCardState();
}

class _PaystackPlansCardState extends State<PaystackPlansCard>
    with WidgetsBindingObserver {
  late final PaystackBilling billing;
  String? _uid;
  String? market;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    billing = PaystackBilling(
      currentUid: () => context.read<AuthProvider>().currentUser?.uid,
      refreshAccess: () =>
          context.read<AccessProvider>().refresh(refreshPlay: false),
    )..addListener(_changed);
  }

  void _changed() {
    if (mounted)
      setState(() {
        if (billing.pendingMarket != null) market = billing.pendingMarket;
      });
  }

  Future<void> _openInformation(String path) async {
    try {
      if (await launchUrl(
        Uri.https('ripot.app', path),
        mode: LaunchMode.externalApplication,
      ))
        return;
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Open https://ripot.app$path in your browser.')),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = context.watch<AuthProvider>().currentUser?.uid;
    if (_uid != uid) {
      _uid = uid;
      market = null;
      billing.reset();
      Future<void>.microtask(() {
        if (mounted) billing.load(refreshPayment: true);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted)
      billing.load(refreshPayment: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    billing.removeListener(_changed);
    billing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = billing.plansForCountry(market);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Premium payments', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (billing.busy) const LinearProgressIndicator(),
            if (billing.mode == 'test')
              const Text(
                'Test checkout — no real money is charged.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            if (!billing.enabled && !billing.busy)
              const Text(
                'Web card payments are being prepared. You can continue using Ripot Free and check back here for available plans.',
              ),
            if (billing.enabled) ...[
              if (billing.locked == 'trial')
                const Text(
                  'Your free Premium trial is active. You can subscribe after it ends.',
                ),
              if (billing.locked == 'paid')
                Text(
                  billing.provider == 'google_play'
                      ? 'Premium is already active through Google Play. Manage renewal through Google Play.'
                      : 'Your account already has Premium. You do not need another subscription.',
                ),
              if (billing.subscriptionStatus == 'non-renewing')
                const Text(
                  'Renewal is cancelled. Your remaining paid time stays available.',
                ),
              if (billing.subscriptionStatus == 'attention')
                const Text(
                  'Your renewal payment needs attention. Use Manage subscription to update your payment method.',
                ),
              if (billing.locked == null &&
                  (!billing.canManage ||
                      [
                        'cancelled',
                        'completed',
                        'complete',
                      ].contains(billing.subscriptionStatus))) ...[
                const SizedBox(height: 12),
                Text(
                  'Premium account: ${context.watch<AuthProvider>().email ?? ''}',
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey('billing-country-${billing.pendingMarket}'),
                  initialValue: market,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Billing country / region',
                    hintText: 'Select your country',
                  ),
                  items: [
                    for (final country in billing.countries)
                      DropdownMenuItem(
                        value: country.code,
                        child: Text(
                          country.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: billing.busy || billing.pendingPlanId != null
                      ? null
                      : (value) => setState(() => market = value),
                ),
                const SizedBox(height: 12),
                if (market == null)
                  const Text(
                    'Select your billing country to see its available plans and exact payment currency.',
                  ),
                if (market != null && visible.isEmpty)
                  const Text(
                    'A plan is not available for this country yet. You can keep using Ripot Free. Contact support@ripot.app for updates.',
                  ),
                for (final plan in visible) ...[
                  Text(
                    '${plan.price} ${plan.currency} per ${plan.period}',
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    'Renews every ${plan.period} until cancelled. Charged in ${plan.currency}. Your bank may apply currency conversion and fees.',
                  ),
                  const SizedBox(height: 6),
                  FilledButton(
                    onPressed:
                        billing.busy ||
                            (billing.pendingPlanId != null &&
                                billing.pendingPlanId != plan.id)
                        ? null
                        : () => billing.checkout(plan, market!),
                    child: Text(
                      billing.pendingPlanId == plan.id
                          ? 'Resume checkout'
                          : 'Subscribe ${plan.period == 'month' ? 'monthly' : 'yearly'}',
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                const Text(
                  'Pay securely by card through Paystack. Premium is linked to the Ripot account you are signed in to.',
                ),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: () => _openInformation('/terms.html'),
                      child: const Text('Subscription terms'),
                    ),
                    TextButton(
                      onPressed: () => _openInformation('/privacy.html'),
                      child: const Text('Privacy'),
                    ),
                  ],
                ),
              ],
            ],
            if (billing.canManage)
              OutlinedButton.icon(
                onPressed: billing.busy ? null : billing.manage,
                icon: const Icon(Icons.manage_accounts_outlined),
                label: const Text('Manage subscription'),
              ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: billing.busy
                  ? null
                  : () => billing.load(refreshPayment: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Check payment status'),
            ),
            if (billing.message != null) Text(billing.message!),
            if (billing.error != null)
              Text(
                billing.error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            const SizedBox(height: 8),
            const Text(
              'Reports and registry data stay on each device. Payments do not transfer clinical data.',
            ),
          ],
        ),
      ),
    );
  }
}
