import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<File> _journal() async => File(
  '${(await getApplicationSupportDirectory()).path}/ripot-restore-journal.json',
);
Future<String?> readRestoreJournal() async {
  final f = await _journal();
  return await f.exists() ? f.readAsString() : null;
}

Future<void> writeRestoreJournal(String data) async {
  final f = await _journal();
  await f.parent.create(recursive: true);
  final pending = File('${f.path}.pending');
  await pending.writeAsString(data, flush: true);
  if (await pending.readAsString() != data) {
    throw StateError('Restore recovery file could not be verified.');
  }
  await pending.rename(f.path);
}

Future<void> clearRestoreJournal() async {
  final f = await _journal();
  if (await f.exists()) await f.delete();
}
