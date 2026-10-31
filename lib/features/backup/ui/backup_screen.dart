import 'dart:convert';
import 'package:provider/provider.dart';
import '../../access/providers/access_provider.dart';
import '../../access/ui/premium_prompt.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/backup_cipher.dart';
import '../data/backup_schedule.dart';
import '../data/backup_service.dart';
import '../data/backup_snapshot.dart';

const backupScopeNames = {
  BackupScope.all: 'Everything',
  BackupScope.reports: 'Reports',
  BackupScope.registry: 'Registry',
  BackupScope.logbook: 'Logbook',
  BackupScope.records: 'Report data',
  BackupScope.templates: 'Templates',
};

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, this.service});
  final BackupService? service;
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  late final service = widget.service ?? BackupService();
  BackupScope scope = BackupScope.all;
  bool busy = true, enabled = false;
  int keep = 5, weekday = 0;
  TimeOfDay time = const TimeOfDay(hour: 20, minute: 0);
  String? folder, last, error, next;
  String changes = '';
  String? message;
  BackupSchedule? _savedSchedule;
  bool _confirmingLeave = false;

  bool get _hasUnsavedSettings {
    final saved = _savedSchedule;
    return saved != null &&
        (enabled != saved.enabled ||
            weekday != saved.weekday ||
            time.hour != saved.hour ||
            time.minute != saved.minute);
  }

  Future<void> _confirmLeave() async {
    if (busy || _confirmingLeave) return;
    _confirmingLeave = true;
    try {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Save backup settings?'),
          content: const Text(
            'Your automatic backup changes have not been saved. '
            'Discarding them keeps your previous schedule. '
            'Your chosen folder, saved copies setting and backup files are kept.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('Discard changes'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Save settings'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (choice == 'save' && !await _configure()) return;
      if (mounted && (choice == 'save' || choice == 'discard')) {
        Navigator.of(context).pop();
      }
    } finally {
      _confirmingLeave = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _date(String? value) {
    final d = DateTime.tryParse(value ?? '')?.toLocal();
    if (d == null) return 'Not yet';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _load({bool discardDraft = false}) async {
    final preserveDraft = _hasUnsavedSettings && !discardDraft;
    try {
      final s = await service.schedule(),
          p = await SharedPreferences.getInstance();
      await p.reload();
      final selected = await service.destination.location();
      var changed = '';
      final baseline = p.getString('backup.baseline');
      if (baseline != null) {
        final old = Map<String, String>.from(jsonDecode(baseline) as Map),
            current = await service.snapshots.inventory();
        final added = current.keys
            .where((k) => k.startsWith('reports.doc.') && !old.containsKey(k))
            .length;
        final updated = current.keys
            .where(
              (k) =>
                  k.startsWith('reports.doc.') &&
                  old.containsKey(k) &&
                  current[k] != old[k],
            )
            .length;
        final removed = old.keys
            .where(
              (k) => k.startsWith('reports.doc.') && !current.containsKey(k),
            )
            .length;
        changed =
            '$added reports added, $updated edited, $removed removed since the last full backup.';
      }
      if (!mounted) return;
      setState(() {
        _savedSchedule = s;
        if (!preserveDraft) {
          enabled = s.enabled;
          weekday = s.weekday;
          time = TimeOfDay(hour: s.hour, minute: s.minute);
        }
        keep = s.keep;
        folder = selected;
        last = p.getString('backup.last.all');
        error = p.getString('backup.error');
        next = s.nextDue?.toIso8601String();
        changes = changed;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Backup settings could not be read. Please reopen this screen.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> _run(
    Future<void> Function() action, {
    bool reloadSettings = false,
    String? failureTitle,
  }) async {
    var succeeded = false;
    String? failureMessage;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
      succeeded = true;
    } catch (e) {
      if (mounted) {
        setState(
          () => message = e is FormatException
              ? e.message
              : e is StateError
              ? e.message.toString()
              : 'This operation did not complete. Check the backup password, backup file, folder permission and storage space. Existing backups were kept.',
        );
        failureMessage = message;
      }
    } finally {
      if (mounted) {
        await _load(discardDraft: reloadSettings && succeeded);
      }
    }
    if (mounted && failureTitle != null && failureMessage != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(failureTitle),
          content: Text(failureMessage!),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Keep editing'),
            ),
          ],
        ),
      );
    }
    return succeeded;
  }

  Future<String?> _passphrase({
    required bool create,
    bool automatic = false,
  }) async {
    final first = TextEditingController(), second = TextEditingController();
    String? validation;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(
            create ? 'Choose a backup password' : 'Enter backup password',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  create
                      ? 'Choose a password of at least 12 characters to protect your backup files. This is separate from your Ripot login password. Keep it safe: Ripot cannot recover it. Older backups still need the password used when they were made.'
                      : automatic
                      ? 'Enter the backup password you chose when setting up automatic backups. This is separate from your Ripot login password.'
                      : 'Enter the backup password used when this file was created. This is separate from your Ripot login password.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: first,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Backup password',
                  ),
                ),
                if (create)
                  TextField(
                    controller: second,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Confirm backup password',
                    ),
                  ),
                if (validation != null)
                  Text(
                    validation!,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (first.text.isEmpty ||
                    first.text.length > 1024 ||
                    (create &&
                        (first.text.length < 12 ||
                            first.text != second.text))) {
                  update(
                    () => validation = create
                        ? 'Use at least 12 characters and enter the same password in both fields.'
                        : 'Enter your backup password.',
                  );
                  return;
                }
                Navigator.pop(ctx, first.text);
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    // Controllers are disposed after the dialog's closing animation.
    Future.delayed(const Duration(seconds: 1), () {
      first.dispose();
      second.dispose();
    });
    return result;
  }

  Future<void> _backup() async {
    if (!await _ensureFolder() || !mounted) return;
    final pass = await _passphrase(create: true);
    if (pass == null || !mounted) return;
    await _run(() async {
      final result = await service.backUp(scope, pass, keep);
      if (!mounted) return;
      if (result.needsConfirmation) {
        final saved = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Was the download saved?'),
            content: const Text(
              'Check your Downloads or Files app. Ripot cannot verify a browser download or rotate downloaded copies. Move the file into your Ripot Backups folder.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not saved'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Yes, saved'),
              ),
            ],
          ),
        );
        if (saved != true) {
          setState(
            () => message =
                'Download not confirmed. Backup status was not updated.',
          );
          return;
        }
        await service.confirmSaved(result);
      }
      if (mounted) setState(() => message = 'Backup saved: ${result.name}');
    });
  }

  Future<bool> _ensureFolder() async {
    if (!service.destination.supported || folder != null) return true;
    var choosing = false;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
              title: const Text('Choose a backup folder'),
              content: const Text(
                'Select where Ripot should save your full and section backups. '
                'No backup will be saved until you choose a folder.',
              ),
              actions: [
                TextButton(
                  onPressed: choosing ? null : () => Navigator.pop(ctx, false),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: choosing
                      ? null
                      : () async {
                          update(() => choosing = true);
                          // Open the browser picker directly from this button's gesture.
                          final saved = await _run(
                            () => service.chooseFolder(),
                          );
                          if (ctx.mounted)
                            Navigator.pop(ctx, saved && folder != null);
                        },
                  child: Text(choosing ? 'Choosing folder…' : 'Choose folder'),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Future<bool> _configure() async {
    if (!_hasUnsavedSettings) return true;
    if (enabled && (!await _ensureFolder() || !mounted)) return false;
    String? pass;
    final existing = _savedSchedule?.enabled == true;
    final resume = enabled && existing && service.needsSessionPassword;
    if (enabled && (!existing || resume)) {
      pass = await _passphrase(create: !existing, automatic: true);
      if (pass == null || !mounted) return false;
    }
    final input = BackupSchedule(
      enabled: enabled,
      hour: time.hour,
      minute: time.minute,
      weekday: weekday,
      keep: keep,
    );
    return _run(
      () async {
        if (resume) await service.unlockSession(pass!);
        await service.configure(input, existing ? null : pass);
        if (mounted) {
          setState(() {
            // A later status/inventory refresh must not mark a completed save dirty.
            _savedSchedule = input;
            message = enabled
                ? 'Automatic backup schedule saved. You can still back up now at any time.'
                : 'Automatic backup is off.';
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message!)));
        }
      },
      reloadSettings: true,
      failureTitle: 'Backup settings were not saved',
    );
  }

  Future<void> _restore() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (picked == null || !mounted) return;
    final file = picked.files.single;
    if (file.size > BackupCipher.maxBytes) {
      setState(() => message = 'This file exceeds the 180 MB backup limit.');
      return;
    }
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => message = 'The backup file could not be read.');
      return;
    }
    final pass = await _passphrase(create: false);
    if (pass == null || !mounted) return;
    await _run(() async {
      final snapshot = BackupSnapshot.parse(
        await BackupCipher.decrypt(bytes, pass),
      );
      if (!mounted) return;
      final full = snapshot.scope == BackupScope.all;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            full
                ? 'Replace local Ripot data?'
                : 'Add missing ${backupScopeNames[snapshot.scope]!.toLowerCase()}?',
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${backupScopeNames[snapshot.scope]} backup • ${_date(snapshot.createdAt.toIso8601String())}',
                ),
                const SizedBox(height: 12),
                Text(
                  '${snapshot.reports} reports · ${snapshot.templates} templates · ${snapshot.records} records',
                ),
                if (snapshot.logbook != null)
                  Text(
                    '${(jsonDecode(snapshot.logbook!)['entries'] as List).length} logbook entries',
                  ),
                if (snapshot.values.containsKey('registry.longitudinal.v1'))
                  Text(
                    '${(jsonDecode(snapshot.values['registry.longitudinal.v1'] as String)['patients'] as List).length} registry patients',
                  ),
                const SizedBox(height: 16),
                Text(
                  full
                      ? 'This replaces your local reports, PDFs, templates, letterheads, Report data, Registry and Logbook with this backup. Make a current full backup first if you need to keep newer work.'
                      : 'This adds missing items. Existing items with the same identity keep their current version. Related letterheads or registry definitions are added when missing. Links to items outside this section require those items to be on this device.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your sign-in and subscription are unchanged. Automatic backups will pause after restore so you can check the result before re-enabling them.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(full ? 'Replace local data' : 'Add missing items'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await service.restore(snapshot);
      backupAppRevision.value++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final premium =
        context.watch<AccessProvider?>()?.safeState.isPremiumLike ?? false;
    return PopScope(
      canPop: !busy && !_hasUnsavedSettings,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !busy && _hasUnsavedSettings) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Backup & restore')),
        body: AbsorbPointer(
          absorbing: busy,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (busy) const LinearProgressIndicator(),
              Text(
                'Keep a copy of your work',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Encrypted backups you can restore in Ripot. Manual backup and restore are free.',
              ),
              const SizedBox(height: 16),
              Text('Last full backup: ${_date(last)}'),
              if (changes.isNotEmpty) Text(changes),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: SelectableText(message!),
                ),
              const Divider(height: 32),
              if (service.destination.supported) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Backup folder'),
                  subtitle: Text(
                    folder ??
                        'Required: choose where full and section backups will be saved.',
                  ),
                  trailing: const Icon(Icons.folder_open),
                  onTap: () => _run(() async {
                    await service.chooseFolder();
                  }),
                ),
                DropdownButtonFormField<int>(
                  key: ValueKey('keep-$keep'),
                  initialValue: keep,
                  decoration: const InputDecoration(
                    labelText: 'Recent backups to keep',
                  ),
                  items: [
                    for (final n in [3, 5, 7, 10])
                      DropdownMenuItem(value: n, child: Text('$n backups')),
                  ],
                  onChanged: (v) => _run(() async {
                    await service.setRetention(v!);
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  'Keeps $keep copies per backup type. Older copies are removed only after a new one is saved and checked.',
                ),
              ] else
                const Text(
                  'This device uses normal downloads. Choose where to save each file; Ripot cannot automatically verify or remove downloaded copies.',
                ),
              const SizedBox(height: 20),
              DropdownButtonFormField<BackupScope>(
                initialValue: scope,
                decoration: const InputDecoration(labelText: 'What to back up'),
                items: [
                  for (final s in BackupScope.values)
                    DropdownMenuItem(
                      value: s,
                      child: Text(backupScopeNames[s]!),
                    ),
                ],
                onChanged: (v) => setState(() => scope = v!),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _backup,
                icon: const Icon(Icons.save_alt),
                label: const Text('Back up now'),
              ),
              const Text(
                'Keep a copy somewhere other than this device in case it is lost or damaged.',
              ),
              const Divider(height: 32),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Automatic backups · Premium'),
                subtitle: Text(
                  premium
                      ? 'Back up everything on a schedule.'
                      : 'Manual backup and restore stay free.',
                ),
                value: enabled,
                onChanged: service.destination.supported
                    ? (v) async {
                        if (v && !premium) {
                          final unlocked = await showPremiumFeatureSheet(
                            context,
                            PremiumFeature.automaticBackup,
                          );
                          if (!mounted || !unlocked) return;
                        }
                        setState(() => enabled = v);
                      }
                    : null,
              ),
              if (enabled && !premium)
                const Text(
                  'Automatic backups are paused until Premium access is active.',
                ),
              if (service.destination.supported && premium) ...[
                Text(
                  service.backgroundAndroid
                      ? 'Runs in the background on Android. Battery restrictions may delay backups.'
                      : kIsWeb
                      ? 'Runs while this Ripot Web tab is open.'
                      : 'Runs while Ripot is open. A missed backup runs when you next open the app.',
                ),
                if (enabled) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    key: ValueKey('weekday-$weekday'),
                    initialValue: weekday,
                    decoration: const InputDecoration(labelText: 'Frequency'),
                    items: [
                      const DropdownMenuItem(value: 0, child: Text('Daily')),
                      for (var day = 1; day <= 7; day++)
                        DropdownMenuItem(
                          value: day,
                          child: Text(
                            'Weekly · ${['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][day - 1]}',
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => weekday = v!),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Preferred local time'),
                    trailing: Text(time.format(context)),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: time,
                      );
                      if (t != null && mounted) setState(() => time = t);
                    },
                  ),
                  Text(
                    'Next scheduled check: ${_date(next)}. Unchanged data does not create another copy.',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    kIsWeb
                        ? 'Web backups run only while Ripot Web is open in this browser tab. You may need to enter your backup password again after reopening it.'
                        : 'Your backup password is saved securely on this device so automatic backups can run without asking each time.',
                  ),
                  if (_savedSchedule?.enabled == true &&
                      service.needsSessionPassword) ...[
                    const SizedBox(height: 8),
                    const Text('Automatic backups are paused.'),
                    const Text(
                      'Enter your backup password to restart them. Web backups run only while Ripot Web is open in this browser tab.',
                    ),
                    TextButton(
                      onPressed: () async {
                        final pass = await _passphrase(
                          create: false,
                          automatic: true,
                        );
                        if (pass != null && mounted) {
                          await _run(() async {
                            await service.unlockSession(pass);
                            if (!mounted) return;
                            setState(
                              () => message =
                                  'Your backup password was accepted. Automatic backups can now run while Ripot Web is open in this tab.',
                            );
                            await service.runIfDue();
                          }, failureTitle: 'Automatic backups could not restart');
                        }
                      },
                      child: const Text('Enter backup password'),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                if (_hasUnsavedSettings)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('You have changes to save.'),
                  ),
                OutlinedButton(
                  onPressed: _hasUnsavedSettings ? _configure : null,
                  child: Text(
                    _hasUnsavedSettings ? 'Save settings' : 'Settings saved',
                  ),
                ),
              ],
              if (!premium && _hasUnsavedSettings && !enabled)
                OutlinedButton(
                  onPressed: _configure,
                  child: const Text('Save settings'),
                ),
              const Divider(height: 32),
              OutlinedButton.icon(
                onPressed: _restore,
                icon: const Icon(Icons.restore),
                label: const Text('Restore from a backup file'),
              ),
              const Text(
                'Choose a .ripotbackup file. You can review its contents before restoring.',
              ),
              const ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Backup details'),
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Full backups include reports, saved PDFs, images, signatures, templates, letterheads, Report data, Registry and Logbook. Sign-in, billing and device settings are excluded. Other files in your folder are kept.\n\nOn Android, force-stopping Ripot pauses automatic backups until you reopen it. For older Registry or Logbook exports, restore within that section.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
