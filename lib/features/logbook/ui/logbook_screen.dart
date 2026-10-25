import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import '../../../core/ui/item_actions.dart';
import '../data/logbook_repository.dart';
import '../domain/logbook_models.dart';
import '../domain/logbook_filter.dart';
import '../services/logbook_pdf.dart';
import 'doctor_directory.dart';
import 'log_entry_editor.dart';
import 'log_entry_detail.dart';
import 'logbook_backup_screen.dart';

class LogbookScreen extends StatefulWidget {
  const LogbookScreen({super.key});
  @override
  State<LogbookScreen> createState() => _LogbookScreenState();
}

class _LogbookScreenState extends State<LogbookScreen> {
  String _doctorId = '', _query = '';
  DateTimeRange? _range;
  bool _exporting = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LogbookRepository>().load();
    });
  }

  Future<void> _quick() async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const LogEntryEditor()),
    );
    if (id != null && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LogEntryDetail(entryId: id)),
      );
    }
  }

  void _backup() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const LogbookBackupScreen()),
  );
  Future<void> _export(List<LogEntry> entries, LogbookData book) async {
    var details = false;
    final action = await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, change) => AlertDialog(
          title: Text('Export ${entries.length} filtered entries'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _doctorId.isEmpty
                    ? 'All doctors in the current view'
                    : book.doctor(_doctorId)?.name ?? '',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: details,
                onChanged: (v) => change(() => details = v ?? false),
                title: const Text('Include entry details'),
                subtitle: const Text(
                  'Adds notes, copied fields and current signature images.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, 'share'),
              child: const Text('Share PDF'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, 'print'),
              child: const Text('Print / save PDF'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final bytes = await buildLogbookPdf(
        entries: entries,
        book: book,
        doctorId: _doctorId,
        dateRange: _range == null
            ? 'All dates'
            : '${readableDate(_range!.start)} to ${readableDate(_range!.end)}',
        includeDetails: details,
      );
      if (!mounted) return;
      if (action == 'share') {
        await Printing.sharePdf(bytes: bytes, filename: 'Ripot_Logbook.pdf');
      } else {
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          name: 'Ripot Logbook',
        );
      }
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          'Could not export the log. Try a smaller date range.',
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<LogbookRepository>();
    final book = repo.data;
    final doctors = [...book.doctors]..sort((a, b) => a.name.compareTo(b.name));
    // A restore may remove a doctor that was selected in this screen.
    final selected = doctors.any((d) => d.id == _doctorId) ? _doctorId : '';
    final entries = filterLogbook(
      book.entries,
      doctorId: selected,
      start: _range?.start,
      end: _range?.end,
      query: _query,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logbook'),
        actions: [
          IconButton(
            tooltip: 'Doctor directory',
            icon: const Icon(Icons.people_outline),
            onPressed: !repo.loaded
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DoctorDirectoryScreen(),
                    ),
                  ),
          ),
          IconButton(
            tooltip: 'Backup and restore',
            icon: const Icon(Icons.save_outlined),
            onPressed: _backup,
          ),
          IconButton(
            tooltip: 'Print or export filtered log',
            icon: const Icon(Icons.print_outlined),
            onPressed: _exporting || entries.isEmpty
                ? null
                : () => _export(entries, book),
          ),
        ],
      ),
      floatingActionButton: repo.loaded
          ? FloatingActionButton.extended(
              onPressed: _quick,
              icon: const Icon(Icons.add),
              label: const Text('Quick Log'),
            )
          : null,
      body: SafeArea(
        child: !repo.loaded
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: repo.error == null
                      ? const CircularProgressIndicator()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(repo.error!),
                            TextButton(
                              onPressed: repo.load,
                              child: const Text('Retry'),
                            ),
                            TextButton(
                              onPressed: _backup,
                              child: const Text('Restore backup'),
                            ),
                          ],
                        ),
                ),
              )
            : Column(
                children: [
                  if (_exporting) const LinearProgressIndicator(),
                  if (book.backupDue(DateTime.now()))
                    Card(
                      margin: const EdgeInsets.all(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Your Logbook has changes to back up.'),
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton(
                                  onPressed: _backup,
                                  child: const Text('Back up now'),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    try {
                                      await repo.snooze();
                                    } catch (_) {
                                      if (context.mounted) {
                                        showMessage(
                                          context,
                                          'Could not postpone the reminder.',
                                        );
                                      }
                                    }
                                  },
                                  child: const Text('Remind me tomorrow'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(selected),
                      initialValue: selected,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Doctor',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('All doctors'),
                        ),
                        for (final d in doctors)
                          DropdownMenuItem(
                            value: d.id,
                            child: Text(
                              doctorLabel(d),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _doctorId = v ?? ''),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              hintText: 'Procedure, facility or case reference',
                              prefixIcon: Icon(Icons.search),
                            ),
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Filter dates',
                          icon: const Icon(Icons.date_range_outlined),
                          onPressed: () async {
                            final range = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(1900),
                              lastDate: DateTime.now().add(
                                const Duration(days: 1),
                              ),
                              initialDateRange: _range,
                            );
                            if (range != null && mounted) {
                              setState(() => _range = range);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${entries.length} entries${_range == null ? '' : ' · ${readableDate(_range!.start)} – ${readableDate(_range!.end)}'}',
                          ),
                        ),
                        if (_range != null)
                          IconButton(
                            tooltip: 'Clear date filter',
                            onPressed: () => setState(() => _range = null),
                            icon: const Icon(Icons.close),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: entries.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                book.entries.isEmpty
                                    ? 'Capture a procedure with Quick Log, or choose “Add to Logbook” from a report’s menu.'
                                    : 'No entries match these filters.',
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                            itemCount: entries.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 4),
                            itemBuilder: (_, i) {
                              final e = entries[i];
                              return Card(
                                child: ListTile(
                                  contentPadding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    12,
                                    8,
                                  ),
                                  title: Text(
                                    e.data.procedure,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${readableDate(e.data.procedureDate)}${e.data.reference.isEmpty ? '' : ' · ${e.data.reference}'}\n${e.currentSignature == null ? 'No current signature' : 'Signature recorded'}',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          LogEntryDetail(entryId: e.id),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
