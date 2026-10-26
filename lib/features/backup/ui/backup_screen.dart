import 'dart:convert';
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
  BackupScope.records: 'Records',
  BackupScope.templates: 'Templates',
};

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final service = BackupService();
  BackupScope scope = BackupScope.all;
  bool busy = true, enabled = false;
  int keep = 5, weekday = 0;
  TimeOfDay time = const TimeOfDay(hour: 20, minute: 0);
  String? folder, last, error, next;
  String changes = '';
  String? message;
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

  Future<void> _load() async {
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
        enabled = s.enabled;
        keep = s.keep;
        weekday = s.weekday;
        time = TimeOfDay(hour: s.hour, minute: s.minute);
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

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => message = e is FormatException
              ? e.message
              : e is StateError
              ? e.message.toString()
              : 'This operation did not complete. Check the passphrase, backup file, folder permission and storage space. Existing backups were kept.',
        );
      }
    } finally {
      if (mounted) await _load();
    }
  }

  Future<String?> _passphrase({required bool create}) async {
    final first = TextEditingController(), second = TextEditingController();
    String? validation;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(create ? 'Protect your backup' : 'Unlock backup'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  create
                      ? 'Use at least 12 characters. Keep this passphrase somewhere safe: Ripot cannot recover it. Older backups still need the passphrase used when they were made.'
                      : 'Enter the passphrase used when this backup was created.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: first,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(labelText: 'Passphrase'),
                ),
                if (create)
                  TextField(
                    controller: second,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Confirm passphrase',
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
                    () => validation = 'Check the passphrase and confirmation.',
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

  Future<void> _configure() async {
    final pass = enabled ? await _passphrase(create: true) : '';
    if (pass == null || !mounted) return;
    await _run(() async {
      await service.configure(
        BackupSchedule(
          enabled: enabled,
          hour: time.hour,
          minute: time.minute,
          weekday: weekday,
          keep: keep,
        ),
        pass,
      );
      if (mounted) {
        setState(
          () => message = enabled
              ? 'Automatic backup schedule saved. You can still back up now at any time.'
              : 'Automatic backup is off.',
        );
      }
    });
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
                      ? 'This replaces your local reports, PDFs, templates, letterheads, Records, Registry and Logbook with this backup. Make a current full backup first if you need to keep newer work.'
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
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Backup & restore')),
        body: AbsorbPointer(
          absorbing: busy,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (busy) const LinearProgressIndicator(),
              Text(
                'One folder. Dated copies.',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'A full backup includes editable reports, saved PDFs, images, signatures, templates, letterheads, Records, Registry and Logbook. Backups are encrypted. Sign-in, billing and device settings are excluded.',
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
                    folder ?? 'Choose once; full and section backups go here.',
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
                    labelText: 'Copies to keep per backup type',
                  ),
                  items: [
                    for (final n in [3, 5, 7, 10])
                      DropdownMenuItem(
                        value: n,
                        child: Text('$n dated copies'),
                      ),
                  ],
                  onChanged: (v) => _run(() async {
                    await service.setRetention(v!);
                  }),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Older copies are removed only after a new copy is saved and verified. Other files in the folder are left alone.',
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
                'Keep a copy away from this device too. A backup on the same phone cannot protect you if the phone is lost.',
              ),
              const Divider(height: 32),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Automatic full backups'),
                subtitle: const Text(
                  'Optional. Manual backup remains available at any time.',
                ),
                value: enabled,
                onChanged: service.destination.supported
                    ? (v) => setState(() => enabled = v)
                    : null,
              ),
              if (service.destination.supported) ...[
                Text(
                  service.backgroundAndroid
                      ? 'Android can run backups in the background. Battery restrictions may delay the chosen time; missed backups run when possible. Force-stopping Ripot pauses them until you reopen it.'
                      : kIsWeb
                      ? 'Runs only while this browser tab is open and unlocked for backups. You may need to choose the folder again after reopening the browser.'
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
                        ? 'The passphrase stays in memory for this tab only.'
                        : 'Enabling this saves the passphrase in this device’s secure storage so backups can run without prompting.',
                  ),
                  if (kIsWeb && !service.sessionUnlocked)
                    TextButton(
                      onPressed: () async {
                        final pass = await _passphrase(create: false);
                        if (pass != null && mounted) {
                          await _run(() async {
                            await service.unlockSession(pass);
                            if (!mounted) return;
                            setState(
                              () => message =
                                  'Backups unlocked for this browser session.',
                            );
                            await service.runIfDue();
                          });
                        }
                      },
                      child: const Text('Unlock for this session'),
                    ),
                ],
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _configure,
                  child: const Text('Save automatic settings'),
                ),
              ],
              const Divider(height: 32),
              OutlinedButton.icon(
                onPressed: _restore,
                icon: const Icon(Icons.restore),
                label: const Text('Restore from a backup file'),
              ),
              const Text(
                'Choose a dated .ripotbackup file from your backup folder or Downloads. Ripot checks it and shows its contents before changing anything. For older Registry or Logbook exports, use Restore in that section.',
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
