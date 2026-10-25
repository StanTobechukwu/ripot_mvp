import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:signature/signature.dart';
import '../../../core/ui/item_actions.dart';
import '../data/logbook_repository.dart';
import '../domain/logbook_models.dart';
import 'doctor_directory.dart';
import 'log_entry_editor.dart';

class LogDataView extends StatelessWidget {
  final LogData data;
  final Map<String, String> names;
  const LogDataView({super.key, required this.data, required this.names});
  @override
  Widget build(BuildContext context) {
    Widget field(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          SelectableText(value),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(data.procedure, style: Theme.of(context).textTheme.headlineSmall),
        field('Procedure date', readableDate(data.procedureDate)),
        for (final p in data.participants)
          field(
            p.role.label,
            '${names[p.doctorId] ?? 'Unknown doctor'}${p.supervised ? ' · Under supervision' : ''}',
          ),
        if (data.supervisorId.isNotEmpty)
          field(
            'Named supervisor',
            names[data.supervisorId] ?? 'Unknown doctor',
          ),
        if (data.facility.isNotEmpty) field('Facility', data.facility),
        if (data.reference.isNotEmpty) field('Case reference', data.reference),
        if (data.notes.isNotEmpty) field('Outcome / notes', data.notes),
        for (final f in data.fields) field(f.label, f.value),
        if (data.reportAuthor.isNotEmpty)
          field('Report author/signatory', data.reportAuthor),
      ],
    );
  }
}

class LogEntryDetail extends StatelessWidget {
  final String entryId;
  const LogEntryDetail({super.key, required this.entryId});
  @override
  Widget build(BuildContext context) {
    final repo = context.watch<LogbookRepository>();
    final entry = repo.data.entry(entryId);
    if (entry == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Log entry')),
        body: const Center(
          child: Text('This entry is no longer in this Logbook.'),
        ),
      );
    }
    final current = entry.currentSignature;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log entry'),
        actions: [
          IconButton(
            tooltip: 'Edit log',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => LogEntryEditor(entry: entry)),
            ),
          ),
          IconButton(
            tooltip: 'Delete log',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (!await confirmAction(
                    context,
                    'Delete log entry?',
                    'This permanently deletes this log and its signed versions from this device. The source report and Records are kept.',
                  ) ||
                  !context.mounted) {
                return;
              }
              try {
                await repo.deleteEntry(entryId);
                if (context.mounted) Navigator.pop(context);
              } catch (_) {
                if (context.mounted) {
                  showMessage(context, 'Could not delete this entry.');
                }
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            LogDataView(
              data: entry.data,
              names: current?.doctorNames ?? {for (final d in repo.data.doctors) d.id: d.name},
            ),
            const Divider(),
            Text(
              'Entry version ${entry.revision} · Recorded ${readableDate(entry.createdAt.toLocal())}',
            ),
            if (entry.linkedReportId.isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Copied from a report. This saved log remains available if the report is deleted.',
                ),
              ),
            if (current == null) ...[
              Text(
                entry.signatures.isEmpty
                    ? 'No signature recorded'
                    : 'This version has no signature. Earlier signed versions are kept below.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _SignLogScreen(entry: entry),
                  ),
                ),
                icon: const Icon(Icons.draw_outlined),
                label: const Text('Record in-person signature'),
              ),
            ] else
              _signatureCard(context, current),
            for (final s in entry.signatures.reversed.where(
              (s) => s.revision != entry.revision,
            ))
              Card(
                child: ListTile(
                  title: Text('Signed version ${s.revision}'),
                  subtitle: Text(
                    '${s.signerName} · ${readableDate(s.recordedAt.toLocal())}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          title: Text('Signed version ${s.revision}'),
                        ),
                        body: SafeArea(
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              LogDataView(
                                data: s.snapshot,
                                names: s.doctorNames,
                              ),
                              _signatureCard(context, s),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

Widget _signatureCard(BuildContext context, LogSignature s) => Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Signature recorded · Version ${s.revision}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text('${s.signerName} · ${s.recordedAt.toLocal()}'),
        Image.memory(
          base64Decode(s.pngBase64),
          height: 90,
          errorBuilder: (_, _, _) => const Text('Signature image unavailable'),
        ),
        const Text(
          'Recorded in person on this device. Identity has not been independently authenticated. This is not a competency assessment.',
        ),
      ],
    ),
  ),
);

class _SignLogScreen extends StatefulWidget {
  final LogEntry entry;
  const _SignLogScreen({required this.entry});
  @override
  State<_SignLogScreen> createState() => _SignLogScreenState();
}

class _SignLogScreenState extends State<_SignLogScreen> {
  final _signature = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  late final Map<String, String> _names;
  String _signer = '';
  bool _reviewed = false, _busy = false;
  @override
  void initState() {
    super.initState();
    _names = {
      for (final d in context.read<LogbookRepository>().data.doctors)
        d.id: d.name,
    };
    _signer = widget.entry.data.supervisorId;
  }

  @override
  void dispose() {
    _signature.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_reviewed || _signature.isEmpty || _signer.isEmpty) {
      showMessage(
        context,
        'Choose the reviewing doctor, review the entry and draw a fresh signature.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = context.read<LogbookRepository>();
      final png = await _signature.toPngBytes();
      if (png == null) throw StateError('No signature');
      await repo.sign(widget.entry.id, widget.entry.revision, _signer, png);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          'Could not record the signature. Reopen the entry if it has changed.',
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
        appBar: AppBar(title: const Text('Review and sign')),
        body: SafeArea(
          child: AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Review entry version ${widget.entry.revision}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                LogDataView(data: widget.entry.data, names: _names),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _signer.isEmpty
                        ? 'Choose reviewing doctor'
                        : repo.data.doctor(_signer)?.name ??
                              'Choose reviewing doctor',
                  ),
                  trailing: const Icon(Icons.person_search_outlined),
                  onTap: () async {
                    final d = await pickDoctor(
                      context,
                      title: 'Reviewing doctor',
                    );
                    if (d != null && mounted) {
                      setState(() {
                        _signer = d.id;
                        _reviewed = false;
                        _signature.clear();
                      });
                    }
                  },
                ),
                const Text(
                  'Pass the device to the reviewing doctor. Signing records review of the displayed entry; it does not certify competence or authenticate identity.',
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _reviewed,
                  onChanged: (v) => setState(() => _reviewed = v ?? false),
                  title: Text(
                    'I have reviewed the displayed entry, version ${widget.entry.revision}.',
                  ),
                ),
                ClipRect(
                  child: Signature(
                    controller: _signature,
                    height: 180,
                    backgroundColor: Colors.white,
                  ),
                ),
                TextButton(
                  onPressed: _signature.clear,
                  child: const Text('Clear signature'),
                ),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'Saving…' : 'Record signature'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
