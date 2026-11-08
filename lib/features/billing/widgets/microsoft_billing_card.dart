import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/firebase/account_functions.dart';
import '../../../core/firebase/account_runtime.dart';
import '../../../core/platform/external_url.dart';
import '../../access/providers/access_provider.dart';
import '../providers/microsoft_billing_controller.dart';
import '../services/microsoft_store_client.dart';

class MicrosoftBillingCard extends StatefulWidget {
  const MicrosoftBillingCard({super.key});
  @override
  State<MicrosoftBillingCard> createState() => _MicrosoftBillingCardState();
}

class _MicrosoftBillingCardState extends State<MicrosoftBillingCard> {
  late final MicrosoftBillingController controller;
  @override
  void initState() {
    super.initState();
    final access = context.read<AccessProvider>();
    controller = MicrosoftBillingController(
      store: WindowsMicrosoftStoreClient(),
      call: (name, data) => AccountFunctions.call(name, data: data),
      currentUid: () => AccountRuntime.session?.currentUser?.uid,
      access: () => access.safeState,
      refreshAccess: () => access.refresh(),
    )..addListener(_changed);
    controller.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AccessProvider>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Microsoft Store subscriptions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Premium is linked to your signed-in Ripot account. Your current Free access and saved reports remain available.',
            ),
            if (controller.busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
            if (controller.message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(controller.message!),
              ),
            for (final product in controller.products)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  product.period == 'month'
                      ? 'Monthly Premium'
                      : 'Annual Premium',
                ),
                subtitle: Text('${product.price} / ${product.period}'),
                trailing: FilledButton(
                  onPressed: controller.canBuy
                      ? () => controller.purchase(product)
                      : null,
                  child: const Text('Subscribe'),
                ),
              ),
            if (controller.products.isNotEmpty)
              const Text(
                'Renews automatically until cancelled. Microsoft Store shows the final price and terms before you confirm. Manage or cancel through your Microsoft account.',
              ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: controller.busy ? null : controller.load,
                  child: const Text('Refresh plans'),
                ),
                TextButton(
                  onPressed: controller.enabled && !controller.busy
                      ? controller.restore
                      : null,
                  child: const Text('Restore purchases'),
                ),
                TextButton(
                  onPressed: () =>
                      openExternalUrl('https://account.microsoft.com/services'),
                  child: const Text('Manage subscriptions'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
