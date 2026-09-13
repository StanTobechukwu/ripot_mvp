import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../domain/logbook_models.dart';

class LogbookStorage {
  final Directory? directory;
  LogbookStorage({this.directory});
  Future<Directory> _directory() async =>
      directory ??
      Directory(
        '${(await getApplicationSupportDirectory()).path}/ripot_logbook',
      );
  Future<String?> read() async {
    final dir = await _directory();
    var found = false;
    for (final name in ['current.json', 'recovery.json']) {
      final file = File('${dir.path}/$name');
      if (!await file.exists()) continue;
      found = true;
      try {
        final value = await file.readAsString();
        LogbookData.fromJson(object(jsonDecode(value)));
        return value;
      } catch (_) {
        /* Try the last complete local snapshot. */
      }
    }
    if (found) {
      throw const FormatException(
        'Local Logbook could not be read. Restore a backup.',
      );
    }
    return null;
  }

  Future<void> write(String value) async {
    LogbookData.fromJson(object(jsonDecode(value)));
    final dir = await _directory();
    await dir.create(recursive: true);
    final next = File('${dir.path}/pending.json');
    final current = File('${dir.path}/current.json');
    final recovery = File('${dir.path}/recovery.json');
    await next.writeAsString(value, flush: true);
    if (await next.readAsString() != value) {
      throw StateError('Logbook write verification failed');
    }
    // Copy only a valid current snapshot; never replace recovery with corrupt data.
    String? previous;
    if (await current.exists()) {
      try {
        final old = await current.readAsString();
        LogbookData.fromJson(object(jsonDecode(old)));
        previous = old;
      } catch (_) {
        /* Keep the valid recovery file. */
      }
    }
    if (previous != null) {
      final pendingRecovery = File('${dir.path}/recovery.pending');
      await pendingRecovery.writeAsString(previous, flush: true);
      await pendingRecovery.rename(recovery.path);
    }
    await next.rename(current.path);
  }
}
