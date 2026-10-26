import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

class BackupDestination {
  static const _channel = MethodChannel('ripot/backup_files');
  static const _path = 'backup.folder.v1';
  static RandomAccessFile? _lock;
  bool get supported =>
      Platform.isAndroid ||
      Platform.isWindows ||
      Platform.isLinux ||
      Platform.isMacOS;
  bool get needsDownloadConfirmation => !supported;
  Future<String?> location() async => Platform.isAndroid
      ? await _channel.invokeMethod<String>('location')
      : (await SharedPreferences.getInstance()).getString(_path);
  Future<String?> choose() async {
    if (Platform.isAndroid) {
      return _channel.invokeMethod<String>('chooseFolder');
    }
    if (!supported) return null;
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose your Ripot Backups folder',
    );
    if (path != null) {
      await (await SharedPreferences.getInstance()).setString(_path, path);
    }
    return path;
  }

  Future<bool> acquire() async {
    if (Platform.isAndroid) {
      return await _channel.invokeMethod<bool>('acquireLock') ?? false;
    }
    if (_lock != null) return false;
    final f = await File(
      '${(await getApplicationSupportDirectory()).path}/ripot-backup.lock',
    ).open(mode: FileMode.append);
    try {
      await f.lock(FileLock.exclusive);
      _lock = f;
      return true;
    } catch (_) {
      await f.close();
      return false;
    }
  }

  Future<void> release() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('releaseLock');
      return;
    }
    final f = _lock;
    _lock = null;
    await f?.unlock();
    await f?.close();
  }

  Future<String> write(Uint8List bytes, String scope, int keep) async {
    if (Platform.isAndroid) {
      return (await _channel.invokeMethod<String>('writeBackup', {
        'bytes': bytes,
        'scope': scope,
        'keep': keep,
      }))!;
    }
    final name =
        'Ripot-$scope-${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.ripotbackup';
    if (!supported) {
      final saved = await FilePicker.platform.saveFile(
        fileName: name,
        bytes: bytes,
        dialogTitle: 'Save encrypted Ripot backup',
      );
      if (saved == null) throw StateError('Backup cancelled.');
      return name;
    }
    final path = await location();
    if (path == null) throw StateError('Choose a backup folder first.');
    return writeManagedBackup(Directory(path), bytes, scope, keep, name);
  }
}

Future<String> writeManagedBackup(
  Directory dir,
  Uint8List bytes,
  String scope,
  int keep,
  String name,
) async {
  if (!await dir.exists() ||
      keep < 3 ||
      keep > 10 ||
      (!name.startsWith('Ripot-$scope-') ||
          !RegExp(
            r'^Ripot-[a-z]+-[A-Za-z0-9.:-]+\.ripotbackup$',
          ).hasMatch(name))) {
    throw StateError('Invalid backup folder or name.');
  }
  final pending = File('${dir.path}/$name.pending'),
      finalFile = File('${dir.path}/$name');
  if (await finalFile.exists()) {
    throw StateError('A backup with this name already exists.');
  }
  final hash = sha256.convert(bytes).toString();
  try {
    await pending.writeAsBytes(bytes, flush: true);
    if (sha256.convert(await pending.readAsBytes()).toString() != hash) {
      throw StateError('Backup write verification failed.');
    }
    await pending.rename(finalFile.path);
    if (sha256.convert(await finalFile.readAsBytes()).toString() != hash) {
      throw StateError('Backup verification failed.');
    }
  } catch (_) {
    if (await pending.exists()) await pending.delete();
    rethrow;
  }
  final p = await SharedPreferences.getInstance(),
      key =
          'backup.managed.${sha256.convert(utf8.encode(dir.absolute.path))}.$scope';
  final owned = [...p.getStringList(key) ?? <String>[], name];
  if (!await p.setStringList(key, owned)) {
    return '$name (saved; rotation unavailable)';
  }
  final failed = <String>[];
  for (final old in owned.take((owned.length - keep).clamp(0, owned.length))) {
    // Even corrupted preferences must never delete a path outside this folder.
    if (!old.startsWith('Ripot-$scope-') ||
        !RegExp(r'^Ripot-[a-z]+-[A-Za-z0-9.:-]+\.ripotbackup$').hasMatch(old)) {
      failed.add(old);
      continue;
    }
    try {
      final f = File('${dir.path}/$old');
      if (await f.exists()) await f.delete();
    } catch (_) {
      failed.add(old);
    }
  }
  await p.setStringList(key, [
    ...failed,
    ...owned.skip((owned.length - keep).clamp(0, owned.length)),
  ]);
  return failed.isEmpty
      ? name
      : '$name (saved; some older copies could not be removed)';
}
