import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackupFolder {
  static const _channel = MethodChannel('ripot/logbook_files');
  static const _pathKey = 'logbook.backup.folder';
  bool get supportsRotation =>
      Platform.isAndroid ||
      Platform.isLinux ||
      Platform.isMacOS ||
      Platform.isWindows;
  Future<String?> location() async {
    if (Platform.isAndroid) return _channel.invokeMethod<String>('location');
    return (await SharedPreferences.getInstance()).getString(_pathKey);
  }

  Future<String?> choose() async {
    if (Platform.isAndroid) {
      return _channel.invokeMethod<String>('chooseFolder');
    }
    if (!supportsRotation) return null;
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose a Logbook backup folder',
    );
    if (path == null) return null;
    await (await SharedPreferences.getInstance()).setString(_pathKey, path);
    return path;
  }

  Future<String?> write(Uint8List bytes) async {
    if (Platform.isAndroid) {
      return _channel.invokeMethod<String>('writeBackup', bytes);
    }
    if (!supportsRotation) {
      // iOS is not released yet; use the system document export, with no claim
      // that Ripot can rotate files at an arbitrary provider location.
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Save encrypted Logbook backup',
        fileName:
            'ripot-logbook-${DateTime.now().millisecondsSinceEpoch}.ripotbackup',
        bytes: bytes,
      );
      if (saved == null) throw StateError('Backup cancelled');
      return 'Saved a manual backup. Automatic two-file rotation is unavailable on this platform.';
    }
    final path = await location();
    if (path == null) throw StateError('Choose a backup folder first');
    return writeRotatingBackup(Directory(path), bytes);
  }
}

// Only exact Ripot-managed names in this folder are rotated. Other files,
// including manually renamed backup copies, are never deleted.
Future<String?> writeRotatingBackup(
  Directory directory,
  Uint8List bytes,
) async {
  if (!await directory.exists()) throw StateError('Backup folder unavailable');
  final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
  final pending = File('${directory.path}/ripot-logbook-$stamp.pending');
  final finalFile = File('${directory.path}/ripot-logbook-$stamp.ripotbackup');
  try {
    await pending.writeAsBytes(bytes, flush: true);
    final read = await pending.readAsBytes();
    if (!_same(read, bytes)) {
      throw StateError('Backup write verification failed');
    }
    await pending.rename(finalFile.path);
    final verified = await finalFile.readAsBytes();
    if (!_same(verified, bytes)) {
      throw StateError('Backup read verification failed');
    }
  } catch (_) {
    if (await pending.exists()) await pending.delete();
    rethrow;
  }
  final pattern = RegExp(r'^ripot-logbook-\d{16,20}\.ripotbackup$');
  final files = await directory
      .list()
      .where((e) => e is File && pattern.hasMatch(e.uri.pathSegments.last))
      .cast<File>()
      .toList();
  files.sort((a, b) => b.path.compareTo(a.path));
  var cleanupFailed = false;
  for (final old in files.skip(2)) {
    try {
      await old.delete();
    } catch (_) {
      cleanupFailed = true;
    }
  }
  return cleanupFailed
      ? 'Backup saved and checked. Some older backups could not be removed; check the selected folder.'
      : null;
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
