import 'package:shared_preferences/shared_preferences.dart';

const _key = 'backup.restore.recovery.v1';
Future<String?> readRestoreJournal() async =>
    (await SharedPreferences.getInstance()).getString(_key);
Future<void> writeRestoreJournal(String data) async {
  final p = await SharedPreferences.getInstance();
  if (!await p.setString(_key, data) || p.getString(_key) != data) {
    throw StateError(
      'Not enough browser storage for a safe restore. Existing data was kept.',
    );
  }
}

Future<void> clearRestoreJournal() async {
  if (!await (await SharedPreferences.getInstance()).remove(_key)) {
    throw StateError('Could not finish restore recovery.');
  }
}
