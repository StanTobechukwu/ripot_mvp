import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../providers/access_provider.dart';
import '../../auth/providers/auth_provider.dart';

/// Refresh account access on startup, return to the foreground, and during long
/// sessions. The provider coalesces repeated focus changes and network checks.
class AccessRecheck extends StatefulWidget {
  const AccessRecheck({super.key, required this.child});
  final Widget child;

  @override
  State<AccessRecheck> createState() => _AccessRecheckState();
}

class _AccessRecheckState extends State<AccessRecheck>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(const Duration(minutes: 15), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _refresh();
      }
    });
  }

  void _refresh() {
    if (!mounted || !context.read<AuthProvider>().isSignedIn) return;
    unawaited(context.read<AccessProvider>().recheckIfDue());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
