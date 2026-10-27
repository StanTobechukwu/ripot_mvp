import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../platform/backup_destination.dart';
import '../platform/backup_local.dart';
import 'backup_cipher.dart';
import 'backup_schedule.dart';
import 'backup_snapshot.dart';

const _scheduleKey = 'backup.schedule.v1';
const _secretKey = 'ripot.automaticBackup.passphrase.v1';
const _job = 'ripot.scheduledBackup.v1';
final backupAppRevision = ValueNotifier<int>(0);

@pragma('vm:entry-point')
void backupDispatcher() {
  Workmanager().executeTask((task, input) async {
    if (task != _job) return true;
    await BackupService().runIfDue();
    return true; // Failures are retained in status and retried after 15 minutes.
  });
}

class BackupResult {
  const BackupResult(this.name, this.snapshot, this.needsConfirmation);
  final String name;
  final BackupSnapshot snapshot;
  final bool needsConfirmation;
}

class BackupService {
  BackupService({BackupDestination? destination, BackupSnapshots? snapshots})
    : destination = destination ?? BackupDestination(),
      snapshots = snapshots ?? BackupSnapshots();
  final BackupDestination destination;
  final BackupSnapshots snapshots;
  static const _secure = FlutterSecureStorage();
  static String? _webPassphrase;
  static bool _checking = false;
  bool get backgroundAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get sessionUnlocked => !kIsWeb || _webPassphrase != null;
  bool get needsSessionPassword => kIsWeb && !sessionUnlocked;
  Future<SharedPreferences> _prefs() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return p;
  }

  Future<BackupSchedule> schedule() async {
    final raw = (await _prefs()).getString(_scheduleKey);
    return raw == null
        ? const BackupSchedule()
        : BackupSchedule.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _storeSchedule(BackupSchedule s) async {
    if (!await (await _prefs()).setString(
      _scheduleKey,
      jsonEncode(s.toJson()),
    )) {
      throw StateError('Schedule could not be saved.');
    }
  }

  Future<void> setRetention(int keep) async {
    if (keep < 3 || keep > 10) {
      throw const FormatException('Keep between 3 and 10 copies.');
    }
    if (!await destination.acquire()) {
      throw StateError('Another backup or restore is running.');
    }
    try {
      final s = await schedule();
      await _storeSchedule(
        BackupSchedule(
          enabled: s.enabled,
          hour: s.hour,
          minute: s.minute,
          weekday: s.weekday,
          keep: keep,
          nextDue: s.nextDue,
        ),
      );
    } finally {
      await destination.release();
    }
  }

  Future<void> chooseFolder() async {
    // Invoke the picker immediately: browsers require a live user gesture.
    final selected = await destination.choose();
    if (selected != null) {
      final p = await _prefs();
      // The previous baseline belongs to the old destination. Even unchanged
      // data needs a first copy in a newly selected folder.
      await p.remove('backup.baseline');
      await p.remove('backup.retryAfter');
    }
  }

  // Null reuses the password already held for an enabled automatic schedule.
  Future<void> configure(BackupSchedule input, String? passphrase) async {
    if (!await destination.acquire()) {
      throw StateError('Another backup or restore is running.');
    }
    try {
      if (!input.enabled) {
        await _storeSchedule(input);
        _webPassphrase = null;
        if (!kIsWeb) await _secure.delete(key: _secretKey);
        if (backgroundAndroid) await Workmanager().cancelByUniqueName(_job);
        return;
      }
      if (!destination.supported || await destination.location() == null) {
        throw StateError('Choose a backup folder first.');
      }
      final reusePassword = passphrase == null;
      if (reusePassword) {
        if (!(await schedule()).enabled) {
          throw StateError('Choose a backup password to set up automatic backups.');
        }
        passphrase = kIsWeb
            ? _webPassphrase
            : await _secure.read(key: _secretKey);
        if (passphrase == null) {
          throw StateError('Your backup password is unavailable. Enter it again on the web, or turn automatic backups off and set them up again on this device.');
        }
      }
      if (passphrase == null) throw StateError('Enter your backup password.');
      if (passphrase.length < 12 || passphrase.length > 1024) {
        throw const FormatException(
          'Use a backup password of 12 to 1024 characters.',
        );
      }
      // Store locally only after the user explicitly enables automatic backup.
      if (!reusePassword && kIsWeb) {
        final check = await BackupCipher.encrypt({
          'purpose': 'ripot-backup-session',
        }, passphrase);
        await (await _prefs()).setString(
          'backup.sessionCheck',
          base64Encode(check),
        );
        _webPassphrase = passphrase;
      } else if (!reusePassword) {
        await _secure.write(key: _secretKey, value: passphrase);
      }
      if (backgroundAndroid) {
        await Workmanager().registerPeriodicTask(
          _job,
          _job,
          frequency: const Duration(minutes: 15),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        );
      }
      await _storeSchedule(input.advance(DateTime.now()));
      await (await _prefs()).remove('backup.retryAfter');
    } finally {
      await destination.release();
    }
  }

  Future<void> unlockSession(String passphrase) async {
    if (passphrase.length < 12 || passphrase.length > 1024) {
      throw const FormatException('Enter your backup password.');
    }
    final check = (await _prefs()).getString('backup.sessionCheck');
    if (check == null) {
      throw StateError('Turn automatic backups off and set them up again to choose a backup password.');
    }
    await BackupCipher.decrypt(base64Decode(check), passphrase);
    _webPassphrase = passphrase;
    await (await _prefs()).remove('backup.retryAfter');
  }

  Future<void> recoverAtStartup() async {
    if (await readRestoreJournal() == null) return;
    if (!await destination.acquire()) {
      throw StateError(
        'A restore is running in another window. Close that window, then retry.',
      );
    }
    try {
      await snapshots.recover();
    } finally {
      await destination.release();
    }
  }

  Future<BackupResult> backUp(
    BackupScope scope,
    String passphrase,
    int keep,
  ) async {
    if (!await destination.acquire()) {
      throw StateError('Another backup or restore is running.');
    }
    try {
      if (await readRestoreJournal() != null) {
        throw StateError(
          'Restart Ripot to finish interrupted restore recovery first.',
        );
      }
      final snapshot = await snapshots.capture(scope);
      final bytes = await BackupCipher.encrypt(snapshot.toJson(), passphrase);
      final name = await destination.write(bytes, scope.name, keep);
      final result = BackupResult(
        name,
        snapshot,
        destination.needsDownloadConfirmation,
      );
      if (!result.needsConfirmation) await confirmSaved(result);
      // A manual backup never edits nextDue, even when it is already overdue.
      return result;
    } finally {
      await destination.release();
    }
  }

  Future<void> confirmSaved(BackupResult result) async {
    final p = await _prefs();
    await p.setString(
      'backup.last.${result.snapshot.scope.name}',
      DateTime.now().toUtc().toIso8601String(),
    );
    if (result.snapshot.scope == BackupScope.all) {
      await p.setString(
        'backup.baseline',
        jsonEncode(result.snapshot.fingerprints),
      );
      await p.remove('backup.error');
    }
  }

  Future<void> restore(BackupSnapshot snapshot) async {
    if (!await destination.acquire()) {
      throw StateError('Another backup or restore is running.');
    }
    try {
      if (await readRestoreJournal() != null) {
        throw StateError(
          'Restart Ripot to finish interrupted restore recovery first.',
        );
      }
      // Validate before changing settings. Pause before applying data: a crash
      // or secure-storage failure must never leave restored data scheduled for
      // automatic rotation before the user has checked it.
      BackupSnapshot.parse(snapshot.toJson());
      final s = await schedule();
      await _storeSchedule(
        BackupSchedule(
          hour: s.hour,
          minute: s.minute,
          weekday: s.weekday,
          keep: s.keep,
        ),
      );
      _webPassphrase = null;
      if (backgroundAndroid) await Workmanager().cancelByUniqueName(_job);
      if (!kIsWeb) await _secure.delete(key: _secretKey);
      final p = await _prefs();
      await p.remove('backup.baseline');
      await p.remove('backup.last.all');
      await p.remove('backup.error');
      await p.remove('backup.retryAfter');
      try {
        await snapshots.restore(snapshot);
      } catch (_) {
        // Recreate providers even after successful rollback: their cached
        // objects may otherwise retain the partially restored dataset.
        backupAppRevision.value++;
        rethrow;
      }
    } finally {
      await destination.release();
    }
  }

  Future<void> runIfDue() async {
    if (_checking) return;
    _checking = true;
    var locked = false;
    try {
      var s = await schedule();
      final now = DateTime.now();
      if (!s.due(now) || !destination.supported) return;
      final p = await _prefs(),
          retry = DateTime.tryParse(
            (await _prefs()).getString('backup.retryAfter') ?? '',
          );
      if (retry != null && retry.isAfter(now)) return;
      locked = await destination.acquire();
      if (!locked) return;
      s = await schedule();
      if (!s.due(DateTime.now())) return;
      if (await readRestoreJournal() != null) {
        throw StateError('Open Ripot to finish restore recovery.');
      }
      final pass = kIsWeb
          ? _webPassphrase
          : await _secure.read(key: _secretKey);
      if (pass == null) {
        throw StateError('Open Backup & restore and enter your backup password.');
      }
      final snapshot = await snapshots.capture(BackupScope.all);
      // Compare all captured logical values, including saved native PDFs.
      final baseline = p.getString('backup.baseline');
      if (baseline == null ||
          !mapEquals(
            Map<String, String>.from(jsonDecode(baseline) as Map),
            snapshot.fingerprints,
          )) {
        final bytes = await BackupCipher.encrypt(snapshot.toJson(), pass);
        final name = await destination.write(bytes, 'all', s.keep);
        await confirmSaved(BackupResult(name, snapshot, false));
      }
      await _storeSchedule(s.advance(DateTime.now()));
      await p.remove('backup.error');
      await p.remove('backup.retryAfter');
    } catch (_) {
      // Never log passphrases, paths, report content or plugin error payloads.
      try {
        final p = await _prefs();
        await p.setString(
          'backup.error',
          'Automatic backup did not complete. Open Backup & restore, check the folder permission and available space, and enter your backup password if asked. Previous copies were kept.',
        );
        await p.setString(
          'backup.retryAfter',
          DateTime.now()
              .add(const Duration(minutes: 15))
              .toUtc()
              .toIso8601String(),
        );
      } catch (_) {
        /* Leave nextDue unchanged for the next attempt. */
      }
    } finally {
      try {
        if (locked) await destination.release();
      } finally {
        _checking = false;
      }
    }
  }
}
