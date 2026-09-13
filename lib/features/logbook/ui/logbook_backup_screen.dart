import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/ui/item_actions.dart';
import '../data/logbook_repository.dart';
import '../services/backup_folder.dart';
import '../services/logbook_backup.dart';

class LogbookBackupScreen extends StatefulWidget {
  const LogbookBackupScreen({super.key});
  @override
  State<LogbookBackupScreen> createState() => _LogbookBackupScreenState();
}

class _LogbookBackupScreenState extends State<LogbookBackupScreen> {
  final _folder = BackupFolder();
  String? _location, _status;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _readLocation();
  }

  Future<void> _readLocation() async {
    try {
      final path = await _folder.location();
      if (mounted) setState(() => _location = path);
    } catch (_) {
      if (mounted) setState(() => _status = 'Choose your backup folder again.');
    }
  }

  Future<String?> _password({required bool creating}) async {
    final form = GlobalKey<FormState>();
    String password = '', confirmation = '';
    bool visible = false;
    return showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, change) => AlertDialog(
          title: Text(creating ? 'Protect this backup' : 'Unlock backup'),
          content: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    creating
                        ? 'Use a memorable passphrase of at least 12 characters. Keep it somewhere safe: Ripot cannot recover it. You will need the passphrase used for each backup.'
                        : 'Enter the passphrase used when this backup was created.',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    obscureText: !visible,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLength: 1024,
                    decoration: InputDecoration(
                      labelText: 'Passphrase',
                      counterText: '',
                      suffixIcon: IconButton(
                        tooltip: visible
                            ? 'Hide passphrase'
                            : 'Show passphrase',
                        onPressed: () => change(() => visible = !visible),
                        icon: Icon(
                          visible ? Icons.visibility_off : Icons.visibility,
                        ),
                      ),
                    ),
                    onChanged: (v) => password = v,
                    validator: (v) =>
                        v == null || v.isEmpty || (creating && v.length < 12)
                        ? 'Enter ${creating ? 'at least 12 characters' : 'your passphrase'}'
                        : null,
                  ),
                  if (creating)
                    TextFormField(
                      obscureText: !visible,
                      autocorrect: false,
                      enableSuggestions: false,
                      maxLength: 1024,
                      decoration: const InputDecoration(
                        labelText: 'Confirm passphrase',
                        counterText: '',
                      ),
                      onChanged: (v) => confirmation = v,
                      validator: (_) => confirmation != password
                          ? 'Passphrases do not match'
                          : null,
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(dialog, password);
                }
              },
              child: Text(creating ? 'Create backup' : 'Unlock'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _backup() async {
    if (_busy) return;
    final repo = context.read<LogbookRepository>();
    if (!repo.loaded) {
      showMessage(context, 'Load or restore the Logbook first.');
      return;
    }
    if (_folder.supportsRotation && _location == null) {
      final path = await _folder.choose();
      if (path == null || !mounted) return;
      setState(() => _location = path);
    }
    if (!mounted) return;
    final password = await _password(creating: true);
    if (password == null || !mounted) return;
    setState(() {
      _busy = true;
      _status = 'Encrypting Logbook…';
    });
    final snapshot = repo.data;
    try {
      final bytes = await LogbookBackup.encrypt(snapshot, password);
      if (mounted) setState(() => _status = 'Saving and checking backup…');
      final warning = await _folder.write(bytes);
      if (kIsWeb) {
        if (!mounted) return;
        final saved = await confirmAction(
          context,
          'Was the backup saved?',
          'Check Downloads for the new .ripotbackup file before confirming.',
          action: 'File is saved',
          destructive: false,
        );
        if (!saved) {
          if (mounted) {
            setState(
              () => _status =
                  'Backup not confirmed. Your backup reminder is still active.',
            );
          }
          return;
        }
      }
      await repo.backupSucceeded(snapshot);
      if (mounted) {
        setState(
          () => _status =
              warning ??
              'Backup saved and checked. Ripot keeps the latest two backups in this folder.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status =
              'Backup was not confirmed. Check storage space and folder access, then try again. Existing backups are kept.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    final repo = context.read<LogbookRepository>();
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (picked == null || !mounted) return;
    final file = picked.files.single;
    if (file.size > LogbookBackup.maxBytes || file.bytes == null) {
      showMessage(
        context,
        'Choose a Ripot encrypted backup smaller than 40 MB.',
      );
      return;
    }
    final password = await _password(creating: false);
    if (password == null || !mounted) return;
    setState(() {
      _busy = true;
      _status = 'Unlocking and checking backup…';
    });
    try {
      final snapshot = await LogbookBackup.decrypt(file.bytes!, password);
      if (!mounted) return;
      final currentEncoded = jsonEncode(repo.data.toJson());
      final proceed = await confirmAction(
        context,
        'Restore Logbook backup?',
        'This backup contains ${snapshot.entries.length} log entries and ${snapshot.doctors.length} doctors. It will REPLACE the ${repo.data.entries.length} log entries currently on this device. Back up current entries first if needed. Reports, templates, Records and your account will be kept.',
        action: 'Replace Logbook',
      );
      if (!proceed || !mounted) {
        if (mounted) {
          setState(
            () => _status = 'Restore cancelled. Current entries were kept.',
          );
        }
        return;
      }
      if (jsonEncode(repo.data.toJson()) != currentEncoded) {
        throw StateError('Logbook changed during confirmation');
      }
      await repo.restore(snapshot);
      if (mounted) {
        setState(
          () => _status =
              'Restored ${snapshot.entries.length} entries. No duplicate entries were added.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status =
              'Restore failed: the passphrase may be wrong, or the file may be damaged or unsupported. Current entries were kept.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<LogbookRepository>();
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Logbook backup')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Keep a recoverable copy',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Backups include log entries, doctors and signed versions. Source reports, PDFs, images and Records are not included.',
              ),
              const SizedBox(height: 12),
              Text(
                _folder.supportsRotation
                    ? 'Choose a folder you can open in Files. Ripot saves a new encrypted backup, checks it, then removes its oldest backup so the latest two remain.'
                    : 'This platform saves individual encrypted files. Automatic two-file rotation is unavailable; keep the newest and previous backup yourself.',
              ),
              const SizedBox(height: 12),
              const Text(
                'A backup on the same phone will not protect against losing the phone. Copy one encrypted backup to a computer, external drive or a storage service you choose. Your chosen storage provider may sync the folder.',
              ),
              const SizedBox(height: 20),
              Text(
                repo.data.backedAt == null
                    ? 'No successful backup recorded'
                    : 'Last backup: ${readableDate(repo.data.backedAt!.toLocal())}',
              ),
              if (repo.data.dirty)
                const Text('There are changes since the last backup.'),
              if (_folder.supportsRotation)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(
                    _location == null
                        ? 'Choose backup folder'
                        : 'Backup folder selected',
                  ),
                  subtitle: _location == null
                      ? null
                      : Text(
                          Uri.decodeFull(_location!),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                  onTap: _busy
                      ? null
                      : () async {
                          try {
                            final path = await _folder.choose();
                            if (path != null && mounted) {
                              setState(() => _location = path);
                            }
                          } catch (_) {
                            if (context.mounted) {
                              showMessage(
                                context,
                                'Could not select the folder.',
                              );
                            }
                          }
                        },
                ),
              if (_busy) const LinearProgressIndicator(),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(_status!, semanticsLabel: _status),
                ),
              FilledButton.icon(
                onPressed: _busy || !repo.loaded ? null : _backup,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Back up now'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.restore),
                label: const Text('Restore from file'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Ripot reminds you after 20 new entries or a week with unbacked changes. “Remind me tomorrow” postpones the reminder without marking anything backed up.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
