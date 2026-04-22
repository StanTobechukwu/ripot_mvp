import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../reports/data/reports_repository.dart';
import '../../reports/providers/report_editor_provider.dart';
import '../../reports/ui/report_editor_screen.dart';
import '../../reports/ui/saved_pdf_viewer_screen.dart';
import '../domain/record_models.dart';
import '../providers/records_provider.dart';

class RecordViewScreen extends StatefulWidget {
  final RecordSummary summary;

  const RecordViewScreen({super.key, required this.summary});

  @override
  State<RecordViewScreen> createState() => _RecordViewScreenState();
}

class _RecordViewScreenState extends State<RecordViewScreen> {
  bool _loading = true;
  RecordEntry? _entry;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<RecordsProvider>().repo;
    final entry = await repo.loadByRecordId(widget.summary.recordEntryId);
    if (!mounted) return;
    setState(() {
      _entry = entry;
      _loading = false;
    });
  }

  Future<void> _openPdf() async {
    final reportsRepo = context.read<ReportsRepository>();
    final pdfBytes = await reportsRepo.loadPdfBytesForReport(widget.summary.linkedReportId);
    final pdfFileName = await reportsRepo.pdfFileNameForReport(widget.summary.linkedReportId) ??
        '${widget.summary.procedure.isEmpty ? 'record' : widget.summary.procedure}.pdf';
    if (!mounted) return;

    if (pdfBytes == null || pdfBytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No saved PDF found for this record.')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SavedPdfViewerScreen(
          title: widget.summary.procedure.isEmpty ? 'Record PDF' : widget.summary.procedure,
          pdfFileName: pdfFileName,
          pdfBytesFuture: Future.value(pdfBytes),
        ),
      ),
    );
  }

  Future<void> _duplicateAsNewReport() async {
    final editor = context.read<ReportEditorProvider>();
    await editor.duplicateFromExisting(widget.summary.linkedReportId);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReportEditorScreen()),
    );
  }

  Future<void> _deleteRecord() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete record?'),
        content: const Text('This removes the saved record entry from Ripot. The action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<RecordsProvider>().deleteRecord(widget.summary.recordEntryId);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = _entry;
    final valueMap = entry?.values ?? widget.summary.values;
    final procedureName = (valueMap[RecordFieldCatalog.procedure.key] ?? '').trim();
    final fieldDefs = context.watch<RecordsProvider>().allFields;
    final visibleFields = fieldDefs
        .where((field) => field.appliesToProcedure(procedureName) && (valueMap[field.key] ?? '').trim().isNotEmpty)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Record'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primaryContainer.withOpacity(0.9),
                        theme.colorScheme.secondaryContainer.withOpacity(0.65),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.shadow.withOpacity(0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 52,
                            width: 52,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface.withOpacity(0.72),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(Icons.description_outlined, color: theme.colorScheme.primary),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.summary.procedure.isEmpty ? 'Saved Record' : widget.summary.procedure,
                                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  widget.summary.diagnosis.isEmpty ? 'Final clinical record stored in Ripot.' : widget.summary.diagnosis,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _InfoChip(icon: Icons.badge_outlined, label: 'ID', value: formatReportIdForDisplay(valueMap[RecordFieldCatalog.reportId.key] ?? '')),
                          _InfoChip(icon: Icons.calendar_today_outlined, label: 'Date', value: widget.summary.reportDate),
                          _InfoChip(icon: Icons.person_outline, label: 'Reference', value: widget.summary.patientReference),
                        ].where((chip) => chip.value.trim().isNotEmpty).toList(growable: false),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'This record is read-only. Open the PDF for printing or sharing. Use Duplicate to create a new report from this record.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lock_outline, color: theme.colorScheme.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Record actions',
                                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _openPdf,
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Open PDF'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _duplicateAsNewReport,
                          icon: const Icon(Icons.copy_all_outlined),
                          label: const Text('Duplicate as New Report'),
                        ),
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: _deleteRecord,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete Record'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Record details',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Saved details are shown below for review only.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        if (visibleFields.isEmpty)
                          const Text('No saved record details.')
                        else
                          ...visibleFields.map(
                            (field) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _DetailRow(
                                label: field.label,
                                value: field.key == RecordFieldCatalog.reportId.key
                                    ? formatReportIdForDisplay(valueMap[field.key] ?? '')
                                    : (valueMap[field.key] ?? ''),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoChip({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.72),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: theme.textTheme.labelSmall),
              Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.28),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
