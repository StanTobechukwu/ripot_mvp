import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/web/file_download.dart';
import '../../reports/data/reports_repository.dart';
import '../../reports/providers/report_editor_provider.dart';
import '../../reports/ui/report_editor_screen.dart';
import '../../reports/ui/saved_pdf_viewer_screen.dart';
import '../domain/record_models.dart';
import '../providers/records_provider.dart';
import 'record_details_screen.dart';

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

  Future<void> _editRecord(String reportId) async {
    final editor = context.read<ReportEditorProvider>();
    await editor.loadById(reportId);
    if (!mounted) return;
    final provider = context.read<RecordsProvider>();
    final draft = await provider.draftForReport(editor.doc);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecordDetailsScreen(initialEntry: draft)),
    );
    if (!mounted) return;
    await provider.refresh();
  }

  Future<void> _openEditableDraft(String reportId) async {
    final editor = context.read<ReportEditorProvider>();
    await editor.loadById(reportId);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReportEditorScreen()),
    );
  }

  Future<void> _openRecordPrimary(RecordSummary item) async {
    final repo = context.read<ReportsRepository>();
    final pdfBytes = await repo.loadPdfBytesForReport(item.linkedReportId);
    final pdfFileName = await repo.pdfFileNameForReport(item.linkedReportId) ?? '${item.procedure.isEmpty ? 'record' : item.procedure}.pdf';
    if (!mounted) return;

    if (pdfBytes != null && pdfBytes.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SavedPdfViewerScreen(
            title: item.procedure.isEmpty ? 'Record PDF' : item.procedure,
            pdfFileName: pdfFileName,
            pdfBytesFuture: Future.value(pdfBytes),
          ),
        ),
      );
      return;
    }

    await _openEditableDraft(item.linkedReportId);
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
                                  leading: const CircleAvatar(child: Icon(Icons.table_rows_outlined)),
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
                                  onTap: () => _openRecordPrimary(item),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (value) async {
                                      if (value == 'edit') {
                                        await _editRecord(item.linkedReportId);
                                      } else if (value == 'openPdf') {
                                        await _openRecordPrimary(item);
                                      } else if (value == 'draft') {
                                        await _openEditableDraft(item.linkedReportId);
                                      } else if (value == 'delete') {
                                        await vm.deleteRecord(item.recordEntryId);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'openPdf', child: Text('Open PDF')), 
                                      PopupMenuItem(value: 'draft', child: Text('Open editable draft')),
                                      PopupMenuItem(value: 'edit', child: Text('Edit record details')),
                                      PopupMenuItem(value: 'delete', child: Text('Delete record')),
                                    ],
                                  ),
                                ),
                              );
                            },
                          )
                        : _RecordsTable(rows: rows, fields: fields, onOpen: _openRecordPrimary),
          ),
        ],
      ),
    );
  }
}

class _RecordsTable extends StatefulWidget {
  final List<RecordSummary> rows;
  final List<RecordFieldDef> fields;
  final ValueChanged<RecordSummary> onOpen;

  const _RecordsTable({required this.rows, required this.fields, required this.onOpen});

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
          constraints: const BoxConstraints(minWidth: 960),
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
                      cells: [
                        ...visibleFields.map((f) {
                          final rawValue = row.values[f.key] ?? '';
                          final displayValue = f.key == RecordFieldCatalog.reportId.key ? formatReportIdForDisplay(rawValue) : rawValue;
                          return DataCell(Text(displayValue));
                        }),
                        DataCell(
                          TextButton(
                            onPressed: () => widget.onOpen(row),
                            child: const Text('Open PDF'),
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
