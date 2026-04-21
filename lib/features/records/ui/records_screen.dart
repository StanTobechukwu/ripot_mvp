import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/web/file_download.dart';
import '../../reports/data/reports_repository.dart';
import '../../reports/ui/saved_pdf_viewer_screen.dart';
import '../domain/record_models.dart';
import '../providers/records_provider.dart';
import 'record_view_screen.dart';

enum RecordsViewMode { list, table }

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  RecordsViewMode _mode = RecordsViewMode.list;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<RecordsProvider>().refresh();
    });
  }

  Future<void> _openRecordView(RecordSummary item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecordViewScreen(summary: item)),
    );
    if (!mounted) return;
    await context.read<RecordsProvider>().refresh();
  }

  Future<void> _openPdf(RecordSummary item) async {
    final repo = context.read<ReportsRepository>();
    final pdfBytes = await repo.loadPdfBytesForReport(item.linkedReportId);
    final pdfFileName = await repo.pdfFileNameForReport(item.linkedReportId) ?? '${item.procedure.isEmpty ? 'record' : item.procedure}.pdf';
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
          title: item.procedure.isEmpty ? 'Record PDF' : item.procedure,
          pdfFileName: pdfFileName,
          pdfBytesFuture: Future.value(pdfBytes),
        ),
      ),
    );
  }

  Future<void> _downloadPdfFromTable(RecordSummary item) async {
    final repo = context.read<ReportsRepository>();
    final pdfBytes = await repo.loadPdfBytesForReport(item.linkedReportId);
    final pdfFileName = await repo.pdfFileNameForReport(item.linkedReportId) ?? '${item.procedure.isEmpty ? 'record' : item.procedure}.pdf';
    if (!mounted) return;

    if (pdfBytes == null || pdfBytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No saved PDF found for this record.')),
      );
      return;
    }

    if (kIsWeb) {
      await downloadBytes(bytes: pdfBytes, fileName: pdfFileName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF downloaded.')),
      );
      return;
    }

    await _openPdf(item);
  }

  Future<void> _exportTable(List<RecordSummary> records, List<RecordFieldDef> fields) async {
    final keys = [
      ...RecordFieldCatalog.exportDefaultKeys,
      ...fields.where((f) => !RecordFieldCatalog.exportDefaultKeys.contains(f.key)).map((f) => f.key),
    ];
    final visibleFields = keys.map((key) => fields.firstWhere((f) => f.key == key, orElse: () => RecordFieldDef(key: key, label: key, hint: '', isSystem: false))).toList(growable: false);
    String esc(String v) => '"${v.replaceAll('"', '""')}"';
    final buffer = StringBuffer();
    buffer.writeln(visibleFields.map((f) => esc(f.label)).join(','));
    for (final row in records) {
      buffer.writeln(visibleFields.map((f) => esc(row.values[f.key] ?? '')).join(','));
    }
    final bytes = utf8.encode(buffer.toString());
    await downloadBytes(bytes: bytes, fileName: 'ripot_records.csv');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Records table exported as CSV.')));
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RecordsProvider>();
    final fields = vm.allFields;
    final rows = vm.filteredRecords;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Records'),
        actions: [
          SegmentedButton<RecordsViewMode>(
            segments: const [
              ButtonSegment(value: RecordsViewMode.list, icon: Icon(Icons.view_list_outlined), label: Text('List')),
              ButtonSegment(value: RecordsViewMode.table, icon: Icon(Icons.table_rows_outlined), label: Text('Table')),
            ],
            selected: {_mode},
            onSelectionChanged: (value) => setState(() => _mode = value.first),
          ),
          const SizedBox(width: 8),
          if (_mode == RecordsViewMode.table)
            IconButton(
              tooltip: 'Export table',
              onPressed: rows.isEmpty ? null : () => _exportTable(rows, fields),
              icon: const Icon(Icons.download_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search records',
                border: OutlineInputBorder(),
              ),
              onChanged: vm.setQuery,
            ),
          ),
          Expanded(
            child: vm.loading
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No records yet. Save a report to PDF first, then optionally add Record Details to include it here.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : _mode == RecordsViewMode.list
                        ? ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: rows.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = rows[index];
                              return Card(
                                child: ListTile(
                                  leading: const CircleAvatar(child: Icon(Icons.folder_outlined)),
                                  title: Text(
                                    item.procedure.isEmpty ? 'Untitled record' : item.procedure,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    [
                                      if (item.diagnosis.isNotEmpty) item.diagnosis,
                                      if (item.patientReference.isNotEmpty) 'Ref: ${item.patientReference}',
                                      if (item.reportDate.isNotEmpty) item.reportDate,
                                    ].join(' • '),
                                  ),
                                  onTap: () => _openRecordView(item),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (value) async {
                                      if (value == 'openPdf') {
                                        await _openPdf(item);
                                      } else if (value == 'delete') {
                                        await vm.deleteRecord(item.recordEntryId);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'openPdf', child: Text('Open PDF')),
                                      PopupMenuItem(value: 'delete', child: Text('Delete record')),
                                    ],
                                  ),
                                ),
                              );
                            },
                          )
                        : _RecordsTable(
                            rows: rows,
                            fields: fields,
                            onOpenRecord: _openRecordView,
                            onDownloadPdf: _downloadPdfFromTable,
                          ),
          ),
        ],
      ),
    );
  }
}

class _RecordsTable extends StatefulWidget {
  final List<RecordSummary> rows;
  final List<RecordFieldDef> fields;
  final ValueChanged<RecordSummary> onOpenRecord;
  final ValueChanged<RecordSummary> onDownloadPdf;

  const _RecordsTable({required this.rows, required this.fields, required this.onOpenRecord, required this.onDownloadPdf});

  @override
  State<_RecordsTable> createState() => _RecordsTableState();
}

class _RecordsTableState extends State<_RecordsTable> {
  late final ScrollController _horizontalController;
  late final ScrollController _verticalController;

  @override
  void initState() {
    super.initState();
    _horizontalController = ScrollController();
    _verticalController = ScrollController();
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orderedKeys = [
      ...RecordFieldCatalog.exportDefaultKeys,
      ...widget.fields.where((f) => !RecordFieldCatalog.exportDefaultKeys.contains(f.key)).map((f) => f.key),
    ];
    final visibleFields = orderedKeys
        .map((key) => widget.fields.firstWhere((f) => f.key == key, orElse: () => RecordFieldDef(key: key, label: key, hint: '', isSystem: false)))
        .toList(growable: false);

    return Scrollbar(
      controller: _horizontalController,
      thumbVisibility: true,
      trackVisibility: true,
      notificationPredicate: (notification) => notification.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _horizontalController,
        padding: const EdgeInsets.all(12),
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 980),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Scrollbar(
              controller: _verticalController,
              thumbVisibility: true,
              trackVisibility: true,
              notificationPredicate: (notification) => notification.metrics.axis == Axis.vertical,
              child: SingleChildScrollView(
                controller: _verticalController,
                child: DataTable(
                  columns: [
                    ...visibleFields.map((f) => DataColumn(label: Text(f.label))),
                    const DataColumn(label: Text('Actions')),
                  ],
                  rows: widget.rows.map((row) {
                    return DataRow(
                      onSelectChanged: (_) => widget.onOpenRecord(row),
                      cells: [
                        ...visibleFields.map((f) {
                          final rawValue = row.values[f.key] ?? '';
                          final displayValue = f.key == RecordFieldCatalog.reportId.key ? formatReportIdForDisplay(rawValue) : rawValue;
                          return DataCell(Text(displayValue));
                        }),
                        DataCell(
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: () => widget.onOpenRecord(row),
                                child: const Text('View'),
                              ),
                              TextButton.icon(
                                onPressed: () => widget.onDownloadPdf(row),
                                icon: const Icon(Icons.download_outlined),
                                label: const Text('PDF'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(growable: false),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
