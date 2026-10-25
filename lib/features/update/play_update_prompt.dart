import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';

/// Checks Google Play for a newer Android release after account onboarding.
///
/// This does nothing on web, Windows, macOS and iOS. Google Play's in-app
/// update API only works for an Android install delivered through Google Play.
class PlayUpdatePrompt extends StatefulWidget {
  const PlayUpdatePrompt({super.key, required this.child});

  final Widget child;

  @override
  State<PlayUpdatePrompt> createState() => _PlayUpdatePromptState();
}

class _PlayUpdatePromptState extends State<PlayUpdatePrompt> {
  bool _checkedThisSession = false;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    if (_checkedThisSession ||
        _dialogOpen ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    _checkedThisSession = true;

    try {
      final info = await InAppUpdate.checkForUpdate();
      if (!mounted ||
          info.updateAvailability != UpdateAvailability.updateAvailable) {
        return;
      }

      _dialogOpen = true;
      final updateNow = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Update available'),
          content: const Text(
            'A newer version of Ripot is available on Google Play. '
            'Update now to get the latest improvements and fixes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Update now'),
            ),
          ],
        ),
      );
      _dialogOpen = false;

      if (updateNow != true || !mounted) return;

      if (info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
        return;
      }

      if (info.flexibleUpdateAllowed) {
        await InAppUpdate.startFlexibleUpdate();
        await InAppUpdate.completeFlexibleUpdate();
      }
    } catch (_) {
      // Update checks must never block access to Ripot. This can fail when the
      // app was installed locally rather than through Google Play.
    } finally {
      _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
