import 'dart:async';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import '../data/backup_service.dart';

class BackupHost extends StatefulWidget {
  const BackupHost({required this.builder, super.key});
  final Widget Function(Key key) builder;
  @override
  State<BackupHost> createState() => _BackupHostState();
}

class _BackupHostState extends State<BackupHost> with WidgetsBindingObserver {
  final service = BackupService();
  Timer? timer;
  bool ready = false, failed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    backupAppRevision.addListener(_restart);
    _start();
  }

  void _restart() {
    timer?.cancel();
    setState(() => ready = false);
    _start();
  }

  Future<void> _start() async {
    setState(() => failed = false);
    try {
      await service.recoverAtStartup();
    } catch (_) {
      if (mounted) setState(() => failed = true);
      return;
    }
    if (!mounted) return;
    setState(() => ready = true);
    try {
      if (service.backgroundAndroid) {
        await Workmanager().initialize(backupDispatcher);
      }
    } catch (_) {
      /* Foreground retry remains available. */
    }
    if (!mounted) return;
    unawaited(service.runIfDue());
    timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(service.runIfDue()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (ready && state == AppLifecycleState.resumed) {
      unawaited(service.runIfDue());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    backupAppRevision.removeListener(_restart);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ready) return widget.builder(ValueKey(backupAppRevision.value));
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: failed
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'An interrupted restore needs recovery before Ripot can open. Check available storage and close other Ripot windows, then retry. Your recovery copy has been kept.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _start,
                        child: const Text('Retry recovery'),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      ),
    );
  }
}
