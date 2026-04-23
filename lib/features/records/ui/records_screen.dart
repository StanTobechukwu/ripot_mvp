import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/web/file_download.dart';
import '../../reports/data/reports_repository.dart';
import '../../reports/ui/saved_pdf_viewer_screen.dart';
import '../domain/record_models.dart';
import '../providers/records_provider.dart';
import '../../reports/services/pdf_actions_service.dart';
import 'record_view_screen.dart';

enum RecordsViewMode { list, table }

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

enum _RecordsSort { newestFirst, oldestFirst, procedureAZ }

class _RecordsScreenState extends State<RecordsScreen> {
  RecordsViewMode _mode = RecordsViewMode.list;
  _RecordsSort _sort = _RecordsSort.newestFirst;
  String _procedureFilter = 'All procedures';

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

    if (ripotIsNativeDesktop) {
      try {
        final file = await ripotDownloadPdf(bytes: pdfBytes, fileName: pdfFileName);
        if (!mounted) return;
        if (file == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Download cancelled')),
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF saved to: ${file.path}')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
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
    final procedures = <String>{};
    for (final row in vm.records) {
      final value = row.procedure.trim();
      if (value.isNotEmpty) procedures.add(value);
    }
    final procedureOptions = ['All procedures', ...procedures.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()))];

    var rows = vm.filteredRecords.where((row) {
      if (_procedureFilter == 'All procedures') return true;
      return row.procedure.trim().toLowerCase() == _procedureFilter.trim().toLowerCase();
    }).toList(growable: false);

    rows = [...rows]..sort((a, b) {
      switch (_sort) {
        case _RecordsSort.oldestFirst:
          return a.updatedAt.compareTo(b.updatedAt);
        case _RecordsSort.procedureAZ:
          final byProcedure = a.procedure.toLowerCase().compareTo(b.procedure.toLowerCase());
          return byProcedure != 0 ? byProcedure : b.updatedAt.compareTo(a.updatedAt);
        case _RecordsSort.newestFirst:
          return b.updatedAt.compareTo(a.updatedAt);
      }
    });

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
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search records',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: vm.setQuery,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        value: procedureOptions.contains(_procedureFilter) ? _procedureFilter : 'All procedures',
                        decoration: const InputDecoration(
                          labelText: 'Procedure',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: procedureOptions
                            .map((value) => DropdownMenuItem<String>(value: value, child: Text(value, overflow: TextOverflow.ellipsis)))
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _procedureFilter = value);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<_RecordsSort>(
                        value: _sort,
                        decoration: const InputDecoration(
                          labelText: 'Sort',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: _RecordsSort.newestFirst, child: Text('Newest first')),
                          DropdownMenuItem(value: _RecordsSort.oldestFirst, child: Text('Oldest first')),
                          DropdownMenuItem(value: _RecordsSort.procedureAZ, child: Text('Procedure A–Z')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _sort = value);
                        },
                      ),
                    ),
                  ],
                ),
              ],
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
                          SizedBox(
                            width: 190,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 84,
                                    height: 36,
                                    child: OutlinedButton(
                                      onPressed: () => widget.onOpenRecord(row),
                                      child: const Text('View'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: IconButton(
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      tooltip: 'Download PDF',
                                      onPressed: () => widget.onDownloadPdf(row),
                                      icon: const Icon(Icons.download_outlined, size: 20),
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
