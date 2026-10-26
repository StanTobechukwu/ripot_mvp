import 'package:flutter/material.dart';

import 'app.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'features/backup/ui/backup_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseBootstrap.initializeIfConfigured();
  runApp(BackupHost(builder: (key) => MyApp(key: key)));
}
