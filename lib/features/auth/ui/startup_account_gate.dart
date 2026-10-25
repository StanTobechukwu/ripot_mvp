import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
import 'auth_screens.dart';

/// A one-time introduction, not a login requirement for local reporting.
class StartupAccountGate extends StatefulWidget {
  const StartupAccountGate({super.key, required this.child});
  final Widget child;
  static const completedKey = 'account.welcomeCompleted.v1';

  @override
  State<StartupAccountGate> createState() => _StartupAccountGateState();
}

class _StartupAccountGateState extends State<StartupAccountGate> {
  bool _ready = false;
  bool _showWelcome = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var show = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      show = auth.authAvailable && !auth.isSignedIn &&
          prefs.getBool(StartupAccountGate.completedKey) != true;
      if (auth.isSignedIn) {
        await prefs.setBool(StartupAccountGate.completedKey, true);
      }
    } catch (_) {
      // Account onboarding must never make local reports inaccessible.
    }
    if (!mounted) return;
    setState(() { _ready = true; _showWelcome = show; });
  }

  Future<void> _complete() async {
    if (!mounted) return;
    setState(() => _showWelcome = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(StartupAccountGate.completedKey, true);
    } catch (_) {
      // The user can still continue in this session if preferences fail.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _showWelcome
        ? SignInScreen(onWelcomeCompleted: _complete)
        : widget.child;
  }
}
