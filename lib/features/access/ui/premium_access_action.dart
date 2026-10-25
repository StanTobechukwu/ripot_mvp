import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../domain/access_state.dart';
import '../providers/access_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/ui/auth_screens.dart';

enum PremiumOffer { signIn, check, reconnect, trial, plans, active }

PremiumOffer premiumOffer({
  required bool signedIn,
  required AccessState access,
}) {
  if (!signedIn) return PremiumOffer.signIn;
  if (access.isPremiumLike) return PremiumOffer.active;
  if (access.needsOnlineVerification) return PremiumOffer.reconnect;
  if (!access.hasCurrentVerification) return PremiumOffer.check;
  return access.canActivatePremiumTrial
      ? PremiumOffer.trial
      : PremiumOffer.plans;
}

/// The trial starts only after an explicit activation tap. Signing in or
/// checking eligibility alone never starts it, and the server remains final.
class PremiumAccessAction extends StatefulWidget {
  const PremiumAccessAction({
    super.key,
    required this.onViewPlans,
    this.onUnlocked,
  });
  final VoidCallback onViewPlans;
  final VoidCallback? onUnlocked;

  @override
  State<PremiumAccessAction> createState() => _PremiumAccessActionState();
}

class _PremiumAccessActionState extends State<PremiumAccessAction> {
  bool _busy = false;
  String? _message;

  Future<void> _run(PremiumOffer offer) async {
    if (_busy) return;
    if (offer == PremiumOffer.plans) {
      widget.onViewPlans();
      return;
    }
    if (offer == PremiumOffer.active) {
      widget.onUnlocked?.call();
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (offer == PremiumOffer.signIn) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (routeContext) => SignInScreen(
              onWelcomeCompleted: () => Navigator.pop(routeContext),
            ),
          ),
        );
        if (!mounted || !context.read<AuthProvider>().isSignedIn) return;
      }
      final auth = context.read<AuthProvider>();
      final uid = auth.currentUser?.uid;
      final provider = context.read<AccessProvider>();
      await provider.refresh();
      if (!mounted || !auth.isSignedIn || auth.currentUser?.uid != uid) return;
      var access = provider.safeState;
      if (access.isPremiumLike) {
        widget.onUnlocked?.call();
        return;
      }
      if (!access.hasCurrentVerification) {
        setState(
          () => _message =
              'Connect to the internet to check your access. Your saved reports and drafts are still available.',
        );
        return;
      }
      // Signing in/checking only reveals the offer; it is never consent to
      // consume the account's one-time trial.
      if (offer != PremiumOffer.trial || !access.canActivatePremiumTrial)
        return;
      final activated = await provider.activatePremiumTrial();
      if (!mounted || !auth.isSignedIn || auth.currentUser?.uid != uid) return;
      access = provider.safeState;
      if (activated && access.isPremiumLike) {
        if (widget.onUnlocked != null) {
          widget.onUnlocked!();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Your free Premium trial is active. Ends ${access.trialEndDateLabel}.',
              ),
            ),
          );
        }
      } else {
        setState(
          () => _message =
              'We could not activate a free trial. Please check your connection and try again.',
        );
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _message =
              'We could not check your access. Please try again when connected.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<AccessProvider>();
    final offer = premiumOffer(
      signedIn: auth.isSignedIn,
      access: provider.safeState,
    );
    final (label, explanation) = switch (offer) {
      PremiumOffer.signIn => (
        'Sign in to check your free trial',
        'Sign in or create an account to check whether a free Premium trial is available. You can keep using Free.',
      ),
      PremiumOffer.check => (
        'Check free trial eligibility',
        'Let’s check the Premium options available for your account.',
      ),
      PremiumOffer.reconnect => (
        'Refresh Premium access',
        'Reconnect so Ripot can confirm your Premium access. Your saved reports and drafts stay available.',
      ),
      PremiumOffer.trial => (
        'Activate your free Premium trial',
        'Try this with your free Premium trial. No payment is required, and it does not become a paid subscription automatically.',
      ),
      PremiumOffer.plans => (
        'View subscription options',
        'Continue with Premium when you’re ready. Your existing reports and drafts remain available on Free.',
      ),
      PremiumOffer.active => ('Continue', 'Your Premium access is active.'),
    };
    final busy = _busy || provider.loading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(explanation),
        if (_message != null) ...[const SizedBox(height: 8), Text(_message!)],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : () => _run(offer),
          child: Text(
            busy ? 'Checking your access…' : label,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
