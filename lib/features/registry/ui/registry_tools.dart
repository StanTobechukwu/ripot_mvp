import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../../../core/web/file_download.dart';
import '../../records/data/records_repository.dart';
import '../../records/domain/record_models.dart';
import '../domain/registry_table.dart';
import '../services/registry_backup.dart';
import '../services/registry_backup_cipher.dart';

Future<void> _deliver(
  BuildContext context,
  Uint8List bytes,
  String name,
  String mime,
) async {
  if (kIsWeb) {
    await downloadBytes(bytes: bytes, fileName: name);
  } else {
    final box = context.findRenderObject() as RenderBox?;
    await Share.shareXFiles(
      [XFile.fromData(bytes, name: name, mimeType: mime)],
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    );
  }
}

void _notice(BuildContext c, String s) {
  if (c.mounted)
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(s)));
}

Future<void> registryExport(
  BuildContext context,
  RegistryTableData table,
) async {
  try {
    await _deliver(
      context,
      Uint8List.fromList(utf8.encode(table.toCsv())),
      'ripot-registry-${DateTime.now().millisecondsSinceEpoch}.csv',
      'text/csv',
    );
    _notice(
      context,
      'CSV export opened. Save the file in your chosen location.',
    );
  } catch (e) {
    _notice(context, 'Export failed: $e');
  }
}

Future<bool> registryConfirm(
  BuildContext context,
  String title,
  String message,
  String action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    ) ==
    true;

class _PasswordDialog extends StatefulWidget {
  final bool creating;
  const _PasswordDialog(this.creating);
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final password = TextEditingController(), repeated = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    password.dispose();
    repeated.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
    title: Text(
      widget.creating ? 'Protect Registry backup' : 'Unlock Registry backup',
    ),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.creating
              ? 'This encrypted file is restored inside Ripot. To view data in Excel, use Export CSV. Keep the passphrase safe; Ripot cannot recover it.'
              : 'Enter the passphrase you used when creating this Registry backup.'),
            TextFormField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Passphrase'),
              validator: (v) =>
                  v == null ||
                      v.length < (widget.creating ? 12 : 1) ||
                      v.length > 1024
                  ? 'Enter a valid passphrase${widget.creating ? ' (at least 12 characters)' : ''}'
                  : null,
            ),
            if (widget.creating)
              TextFormField(
                controller: repeated,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Repeat passphrase',
                ),
                validator: (v) =>
                    v != password.text ? 'Passphrases do not match' : null,
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(c),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) Navigator.pop(c, password.text);
        },
        child: const Text('Continue'),
      ),
    ],
  );
}

Future<void> registryBackup(
  BuildContext context,
  RecordRegistry registry,
) async {
  final password = await showDialog<String>(
    context: context,
    builder: (_) => const _PasswordDialog(true),
  );
  if (password == null || !context.mounted) return;
  _notice(context, 'Preparing encrypted backup…');
  try {
    final snapshot = await RegistrySnapshot.capture(registry);
    final bytes = await RegistryBackupCipher.encrypt(
      snapshot.toJson(),
      password,
    );
    if (!context.mounted) return;
    await _deliver(
      context,
      bytes,
      'ripot-registry-${DateTime.now().millisecondsSinceEpoch}.ripotregistry',
      'application/octet-stream',
    );
    if (!context.mounted) return;
    await showDialog<void>(context: context, builder: (c) => AlertDialog(
      title: const Text('How to open your backup'),
      content: const SingleChildScrollView(child: Text(
        'Confirm the .ripotregistry file is saved in your chosen location. It is encrypted and will not open in a PDF viewer or spreadsheet.\n\n'
        'In Ripot, open Registry → Restore, or a registry’s ⋮ menu → Restore backup. Select the file and enter your passphrase. Restoration creates a separate copy.\n\n'
        'For a spreadsheet, choose Export CSV instead. Backups include Registry data, but not source PDFs.')),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
    ));
  } catch (e) {
    _notice(context, 'Backup failed: $e');
  }
}

Future<RecordRegistry?> registryRestore(BuildContext context) async {
  try {
    final file = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (file == null || !context.mounted) return null;
    final picked = file.files.single;
    if (picked.size > RegistryBackupCipher.maxBytes || picked.bytes == null)
      throw const FormatException('Choose a Registry backup under 40 MB.');
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _PasswordDialog(false),
    );
    if (password == null || !context.mounted) return null;
    _notice(context, 'Unlocking backup…');
    final snapshot = RegistrySnapshot.parse(
      await RegistryBackupCipher.decrypt(picked.bytes!, password),
    );
    if (!context.mounted) return null;
    if (!await registryConfirm(
          context,
          'Restore ${snapshot.registry.title}?',
          'Create a separate restored registry with ${snapshot.data.patients.length} patients and ${snapshot.data.updates.length} dated updates? Existing registries are kept. Restoring again creates another copy. Source PDFs are not included.',
          'Restore copy',
        ) ||
        !context.mounted)
      return null;
    final r = await snapshot.restoreCopy(context.read<RecordsRepository>());
    _notice(context, 'Registry restored as a separate copy.');
    return r;
  } catch (e) {
    _notice(
      context,
      'Could not restore backup. Check the file and passphrase. $e',
    );
    return null;
  }
}

class RegistryTableView extends StatefulWidget {
  final RegistryTableData data;
  final ValueChanged<String>? onPatient;
  const RegistryTableView({super.key, required this.data, this.onPatient});
  @override
  State<RegistryTableView> createState() => _RegistryTableViewState();
}

class _RegistryTableViewState extends State<RegistryTableView> {
  final Set<String> _hidden = {};

  Future<void> _columns() async {
    final hidden = {..._hidden};
    final accepted = await showDialog<bool>(context: context, builder: (c) =>
      StatefulBuilder(builder: (c, update) => AlertDialog(
        title: const Text('Visible columns'),
        content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final h in widget.data.headers.skip(1))
            CheckboxListTile(title: Text(h), value: !hidden.contains(h),
              onChanged: (v) => update(() { if (v == true) { hidden.remove(h); } else { hidden.add(h); } })),
          ],
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Apply')),
        ],
      )));
    if (accepted == true && mounted) setState(() { _hidden.clear(); _hidden.addAll(hidden); });
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final columns = [for (var i = 1; i < data.headers.length; i++)
      if (!_hidden.contains(data.headers[i])) i];
    final height = 100.0 * MediaQuery.textScalerOf(context).scale(14) / 14;
    Widget cell(String value, {bool heading = false, bool identity = false, String? patientId}) =>
      InkWell(onTap: patientId == null || widget.onPatient == null ? null : () => widget.onPatient!(patientId),
        child: Container(width: identity ? 132 : 170, height: height,
          padding: const EdgeInsets.all(10), alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: heading ? Theme.of(context).colorScheme.surfaceContainerHighest : null,
            border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor))),
          child: Tooltip(message: value, child: Text(value.isEmpty ? '—' : value,
            maxLines: 4, overflow: TextOverflow.ellipsis,
            style: heading ? Theme.of(context).textTheme.labelLarge : null)),
        ));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextButton.icon(onPressed: _columns, icon: const Icon(Icons.view_column_outlined), label: const Text('Columns')),
      const Text('Swipe sideways for more fields. Dates beneath measurements show when they were recorded.'),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [cell(data.headers.first, heading: true, identity: true),
          for (var i = 0; i < data.rows.length; i++)
            cell('${data.rows[i][0]}\n${data.rows[i][1]}', identity: true, patientId: data.patientIds[i]),
        ]),
        Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: Column(children: [
            Row(children: [for (final i in columns) cell(data.headers[i], heading: true)]),
            for (var r = 0; r < data.rows.length; r++)
              Row(children: [for (final i in columns) cell(data.rows[r][i], patientId: data.patientIds[r])]),
          ]))),
      ]),
      if (data.rows.isEmpty) const Text('No saved observations to display.'),
    ]);
  }
}
