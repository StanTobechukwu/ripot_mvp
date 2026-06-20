import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/web/file_download.dart';
import '../../access/providers/access_provider.dart';
import '../../access/ui/upgrade_screen.dart';
import '../../reports/data/reports_repository.dart';
import '../../reports/ui/saved_pdf_viewer_screen.dart';
import '../domain/record_models.dart';
import '../providers/records_provider.dart';
import '../../reports/services/pdf_actions_service.dart';
import '../data/records_repository.dart';
import 'record_view_screen.dart';
import 'record_details_screen.dart';


class _CsvPreviewScreen extends StatelessWidget {
  final String csvText;
  final String fileName;

  const _CsvPreviewScreen({required this.csvText, required this.fileName});

  @override
  Widget build(BuildContext context) {
    final bytes = Uint8List.fromList(utf8.encode(csvText));
    return Scaffold(
      appBar: AppBar(
        title: Text(fileName),
        actions: [
          IconButton(
            tooltip: 'Share CSV',
            icon: const Icon(Icons.share_outlined),
            onPressed: () async {
              if (kIsWeb) {
                final datePart = fileName
                    .replaceFirst('Ripot_Records_', '')
                    .replaceFirst('.csv', '');
                await Share.shareXFiles(
                  [XFile.fromData(bytes, name: fileName, mimeType: 'text/csv')],
                  subject: 'Ripot records export - $datePart',
                  text: 'Attached is the Ripot records CSV export.',
                );
                return;
              }
              await ripotShareCsv(bytes: bytes, fileName: fileName);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: SelectableText(
              csvText,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}

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
  String _procedureFilter = 'All report types';
  String _facilityFilter = 'All facilities';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<RecordsProvider>().refresh();
    });
  }

  String _compactFilterLabel(String value, {int maxChars = 22}) {
    final trimmed = value.trim();
    if (trimmed.length <= maxChars) return trimmed;
    return '${trimmed.substring(0, maxChars).trimRight()}…';
  }


  bool _isSubjectRecordKey(String key) {
    return key == RecordFieldCatalog.subjectName.key ||
        key == RecordFieldCatalog.patientReference.key ||
        key == RecordFieldCatalog.age.key ||
        key == RecordFieldCatalog.gender.key ||
        key.startsWith('subject_');
  }

  List<RecordFieldDef> _fieldsForTable(List<RecordFieldDef> baseFields, List<RecordSummary> rows) {
    final baseByKey = <String, RecordFieldDef>{
      for (final field in baseFields) field.key: field,
      for (final field in RecordFieldCatalog.coreFields) field.key: field,
    };

    final byKey = <String, RecordFieldDef>{};

    void addField(String key, {String? label}) {
      final trimmedKey = key.trim();
      if (trimmedKey.isEmpty || byKey.containsKey(trimmedKey)) return;
      final base = baseByKey[trimmedKey];
      byKey[trimmedKey] = RecordFieldDef(
        key: trimmedKey,
        label: label?.trim().isNotEmpty == true ? label!.trim() : (base?.label ?? trimmedKey),
        hint: base?.hint ?? 'Record value',
        builtInSuggestions: base?.builtInSuggestions ?? const <String>[],
        isSystem: base?.isSystem ?? _isSubjectRecordKey(trimmedKey),
        procedureScope: base?.procedureScope ?? '',
        registryId: base?.registryId ?? '',
      );
    }

    // Always keep a few real system columns. Avoid adding every possible core
    // field because that creates empty ghost columns such as Intervention or
    // Recommendations when the user/template never created them.
    for (final key in RecordFieldCatalog.exportDefaultKeys) {
      addField(key);
    }

    for (final row in rows) {
      final accountedKeys = <String>{
        ...row.fieldLabels.keys,
        ...row.fieldSources.keys,
      };

      for (final entry in row.values.entries) {
        final key = entry.key.trim();
        if (key.isEmpty || byKey.containsKey(key)) continue;

        final hasValue = entry.value.trim().isNotEmpty;
        final base = baseByKey[key];
        final isUserCreated = base != null && !base.isSystem;
        final isRegistryField = base?.isRegistryField == true;
        final isTemplateOrExplicit = accountedKeys.contains(key);

        // Empty fields are allowed inside Record Details if they are accounted for,
        // but the Records table should not grow blank columns unless the field has
        // data or was explicitly created as a manageable record/registry field.
        if (!hasValue && !isUserCreated && !isRegistryField && !isTemplateOrExplicit) {
          continue;
        }
        if (!hasValue && isTemplateOrExplicit) {
          // Keep empty accounted template fields out of the table until at least
          // one record has a value. They remain editable in Record Details.
          continue;
        }

        final label = row.fieldLabels[key]?.trim();
        addField(key, label: label);
      }
    }

    return byKey.values.toList(growable: false);
  }

  Future<void> _openRecordView(RecordSummary item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecordViewScreen(summary: item)),
    );
    if (!mounted) return;
    await context.read<RecordsProvider>().refresh();
  }


  Future<void> _editRecordDetails(RecordSummary item) async {
    final provider = context.read<RecordsProvider>();
    final entry = await provider.repo.loadByRecordId(item.recordEntryId);
    if (!mounted) return;
    if (entry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Record details could not be loaded.')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecordDetailsScreen(initialEntry: entry)),
    );
    if (!mounted) return;
    await provider.refresh();
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

  String _todayCsvFileName() {
    final now = DateTime.now();
    final date = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return 'Ripot_Records_$date.csv';
  }

  String _todayPackageFileName() {
    final now = DateTime.now();
    final date = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return 'Ripot_Records_Backup_$date.zip';
  }

  Future<void> _shareCsv({required Uint8List bytes, required String fileName}) async {
    final datePart = fileName.replaceFirst('Ripot_Records_', '').replaceFirst('.csv', '');
    if (kIsWeb) {
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: fileName, mimeType: 'text/csv')],
        subject: 'Ripot records export - $datePart',
        text: 'Attached is the Ripot records CSV export.',
      );
      return;
    }
    await ripotShareCsv(bytes: bytes, fileName: fileName);
  }

  Future<void> _sharePackage({required Uint8List bytes, required String fileName}) async {
    if (kIsWeb) {
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: fileName, mimeType: 'application/zip')],
        subject: fileName,
        text: 'Attached is a Ripot records package. Import it from Records > Import / Merge in Ripot.',
      );
      return;
    }
    await ripotShareRecordsPackage(bytes: bytes, fileName: fileName);
  }

  Future<void> _openCsvPreview({required String csvText, required String fileName}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _CsvPreviewScreen(csvText: csvText, fileName: fileName)),
    );
  }

  Future<String?> _showExportChoice() {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Export records', style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('Export the currently filtered records. Use CSV for metadata-only merging, or Records Package to include saved PDFs.'),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.table_chart_outlined),
                title: const Text('Export as CSV'),
                subtitle: const Text('Record list only. Best for analysis and metadata merge.'),
                onTap: () => Navigator.pop(sheetContext, 'csv'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Export as Records Package'),
                subtitle: const Text('Record list plus available PDF reports.'),
                onTap: () => Navigator.pop(sheetContext, 'package'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showExportDoneSheet({
    required String title,
    required String fileName,
    required String helper,
    required VoidCallback onOpen,
    required Future<void> Function() onShare,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(fileName),
              const SizedBox(height: 6),
              Text(helper, style: Theme.of(sheetContext).textTheme.bodySmall),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(sheetContext, 'open'),
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Open'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => Navigator.pop(sheetContext, 'share'),
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'open') {
      onOpen();
    } else if (action == 'share') {
      try {
        await onShare();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Share failed: $e')));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported: $fileName')));
    }
  }

  Future<void> _exportRecords(List<RecordSummary> records, List<RecordFieldDef> fields) async {
    final choice = await _showExportChoice();
    if (!mounted || choice == null) return;
    if (choice == 'csv') {
      await _exportCsv(records, fields);
    } else if (choice == 'package') {
      await _exportRecordsPackage(records, fields);
    }
  }

  Future<void> _exportCsv(List<RecordSummary> records, List<RecordFieldDef> fields) async {
    final csvText = context.read<RecordsProvider>().repo.buildRipotCsv(records: records, fields: fields);
    final bytes = Uint8List.fromList(utf8.encode(csvText));
    final fileName = _todayCsvFileName();
    if (kIsWeb) {
      await downloadBytes(bytes: bytes, fileName: fileName);
    } else {
      await ripotDownloadCsv(bytes: bytes, fileName: fileName);
    }
    if (!mounted) return;
    await _showExportDoneSheet(
      title: 'CSV exported',
      fileName: fileName,
      helper: 'Open with Excel, Google Sheets, Numbers, or another spreadsheet app to view columns properly.',
      onOpen: () => _openCsvPreview(csvText: csvText, fileName: fileName),
      onShare: () => _shareCsv(bytes: bytes, fileName: fileName),
    );
  }

  Future<Uint8List> _buildRecordsPackage(List<RecordSummary> records, List<RecordFieldDef> fields) async {
    final csvText = context.read<RecordsProvider>().repo.buildRipotCsv(records: records, fields: fields);
    final reportsRepo = context.read<ReportsRepository>();
    final now = DateTime.now().toIso8601String();
    final archive = Archive();
    final manifest = jsonEncode({
      'app': 'Ripot',
      'exportType': 'recordsPackage',
      'exportVersion': 1,
      'exportedAtIso': now,
      'recordCount': records.length,
    });
    archive.addFile(ArchiveFile.string('manifest.json', manifest));
    archive.addFile(ArchiveFile.string('records.csv', csvText));
    for (final row in records) {
      final pdfBytes = await reportsRepo.loadPdfBytesForReport(row.linkedReportId);
      if (pdfBytes == null || pdfBytes.isEmpty) continue;
      final pdfName = await reportsRepo.pdfFileNameForReport(row.linkedReportId) ?? '${row.recordEntryId}.pdf';
      final safeName = pdfName.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
      archive.addFile(ArchiveFile('pdfs/${row.recordEntryId}__$safeName', pdfBytes.length, pdfBytes));
    }
    final zipped = ZipEncoder().encode(archive);
    if (zipped == null) throw Exception('Could not create records package.');
    return Uint8List.fromList(zipped);
  }

  Future<void> _exportRecordsPackage(List<RecordSummary> records, List<RecordFieldDef> fields) async {
    final bytes = await _buildRecordsPackage(records, fields);
    final fileName = _todayPackageFileName();
    if (kIsWeb) {
      await downloadBytes(bytes: bytes, fileName: fileName);
    } else {
      await ripotDownloadRecordsPackage(bytes: bytes, fileName: fileName);
    }
    if (!mounted) return;
    await _showExportDoneSheet(
      title: 'Records package exported',
      fileName: fileName,
      helper: 'This package contains the record list and available PDF reports. Keep it as backup or share it with another Ripot user.',
      onOpen: () {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Package saved. Use a file manager to view the ZIP.')));
      },
      onShare: () => _sharePackage(bytes: bytes, fileName: fileName),
    );
  }

  Future<void> _importOrMerge() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Import / Merge records', style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('Merge only files exported from Ripot. CSV imports record details only. Records Package imports record details and available PDFs.'),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.table_chart_outlined),
                title: const Text('Merge Ripot Records CSV'),
                subtitle: const Text('Record details only.'),
                onTap: () => Navigator.pop(sheetContext, 'csv'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Merge Records Package'),
                subtitle: const Text('Record details and PDFs.'),
                onTap: () => Navigator.pop(sheetContext, 'package'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'csv') {
      await _mergeCsvFile();
    } else if (choice == 'package') {
      await _mergePackageFile();
    }
  }

  Future<PlatformFile?> _pickFile(List<String> extensions) async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: extensions, withData: true);
    if (picked == null || picked.files.isEmpty) return null;
    return picked.files.first;
  }

  Future<void> _mergeCsvFile() async {
    try {
      final file = await _pickFile(['csv']);
      if (!mounted || file == null) return;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) throw Exception('The selected file could not be read.');
      final csvText = utf8.decode(bytes);
      final result = await context.read<RecordsProvider>().repo.mergeRipotCsv(csvText);
      if (!mounted) return;
      await context.read<RecordsProvider>().refresh();
      _showMergeResult(result, includePdfs: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Merge failed: $e')));
    }
  }

  Future<void> _mergePackageFile() async {
    try {
      final file = await _pickFile(['zip']);
      if (!mounted || file == null) return;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) throw Exception('The selected package could not be read.');
      final archive = ZipDecoder().decodeBytes(bytes);
      final manifestFile = archive.findFile('manifest.json');
      final csvFile = archive.findFile('records.csv');
      if (manifestFile == null || csvFile == null) {
        throw const FormatException('This package does not look like a Ripot records package.');
      }
      final manifest = jsonDecode(utf8.decode(List<int>.from(manifestFile.content as List))) as Map<String, dynamic>;
      if (manifest['app'] != 'Ripot' || manifest['exportType'] != 'recordsPackage') {
        throw const FormatException('This package does not look like a Ripot records package.');
      }
      final csvText = utf8.decode(List<int>.from(csvFile.content as List));
      final recordsRepo = context.read<RecordsProvider>().repo;
      final reportsRepo = context.read<ReportsRepository>();
      final result = await recordsRepo.mergeRipotCsv(csvText);
      var importedPdfs = 0;
      for (final item in archive.files) {
        if (!item.isFile || !item.name.startsWith('pdfs/') || !item.name.toLowerCase().endsWith('.pdf')) continue;
        final name = item.name.split('/').last;
        final separator = name.indexOf('__');
        if (separator <= 0) continue;
        final recordId = name.substring(0, separator);
        final entry = await recordsRepo.loadByRecordId(recordId);
        if (entry == null) continue;
        final content = Uint8List.fromList(List<int>.from(item.content as List));
        final pdfName = name.substring(separator + 2);
        await reportsRepo.importPdfBytesForReport(entry.linkedReportId, content, fileName: pdfName);
        importedPdfs += 1;
      }
      if (!mounted) return;
      await context.read<RecordsProvider>().refresh();
      _showMergeResult(result, includePdfs: true, importedPdfs: importedPdfs);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Package merge failed: $e')));
    }
  }

  void _showMergeResult(RecordsMergeResult result, {required bool includePdfs, int importedPdfs = 0}) {
    final pdfLine = includePdfs ? '\nPDF reports imported: $importedPdfs' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Merge complete. Imported: ${result.imported}, Updated: ${result.updated}, Duplicates skipped: ${result.duplicatesSkipped}$pdfLine'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<AccessProvider>().safeState;
    if (!access.canUseRecords) {
      return Scaffold(
        appBar: AppBar(title: const Text('Records')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Records is a Premium feature',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Upgrade to organize finalized reports in searchable list and table views, filter by report type, and export record tables.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const UpgradeScreen()),
                        ),
                        icon: const Icon(Icons.workspace_premium_outlined),
                        label: const Text('View Premium'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final vm = context.watch<RecordsProvider>();
    final baseFields = vm.allFields;
    final procedures = <String>{};
    final facilities = <String>{};
    for (final row in vm.records) {
      final procedure = row.procedure.trim();
      if (procedure.isNotEmpty) procedures.add(procedure);
      final facility = (row.values[RecordFieldCatalog.facility.key] ?? '').trim();
      if (facility.isNotEmpty) facilities.add(facility);
    }
    final procedureOptions = ['All report types', ...procedures.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()))];
    final facilityOptions = ['All facilities', ...facilities.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()))];

    var rows = vm.filteredRecords.where((row) {
      final procedureMatches = _procedureFilter == 'All report types' || row.procedure.trim().toLowerCase() == _procedureFilter.trim().toLowerCase();
      final facility = (row.values[RecordFieldCatalog.facility.key] ?? '').trim();
      final facilityMatches = _facilityFilter == 'All facilities' || facility.toLowerCase() == _facilityFilter.trim().toLowerCase();
      return procedureMatches && facilityMatches;
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

    final tableFields = _fieldsForTable(baseFields, rows);

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
          IconButton(
            tooltip: 'Import / Merge',
            onPressed: _importOrMerge,
            icon: const Icon(Icons.file_upload_outlined),
          ),
          IconButton(
            tooltip: 'Export records',
            onPressed: rows.isEmpty ? null : () => _exportRecords(rows, tableFields),
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
                        isExpanded: true,
                        value: procedureOptions.contains(_procedureFilter) ? _procedureFilter : 'All report types',
                        decoration: const InputDecoration(
                          labelText: 'Procedure / Report Type',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: procedureOptions
                            .map((value) => DropdownMenuItem<String>(
                                  value: value,
                                  child: Tooltip(
                                    message: value,
                                    child: Text(_compactFilterLabel(value), overflow: TextOverflow.ellipsis),
                                  ),
                                ))
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _procedureFilter = value);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: facilityOptions.contains(_facilityFilter) ? _facilityFilter : 'All facilities',
                        decoration: const InputDecoration(
                          labelText: 'Facility',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: facilityOptions
                            .map((value) => DropdownMenuItem<String>(value: value, child: Text(value, overflow: TextOverflow.ellipsis)))
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _facilityFilter = value);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<_RecordsSort>(
                        isExpanded: true,
                        value: _sort,
                        decoration: const InputDecoration(
                          labelText: 'Sort',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: _RecordsSort.newestFirst, child: Text('Newest first', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: _RecordsSort.oldestFirst, child: Text('Oldest first', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: _RecordsSort.procedureAZ, child: Text('Report type A–Z', overflow: TextOverflow.ellipsis)),
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
                                      if (item.patientReference.isNotEmpty) 'Subject ID: ${item.patientReference}',
                                      if (item.reportDate.isNotEmpty) item.reportDate,
                                    ].join(' • '),
                                  ),
                                  onTap: () => _openRecordView(item),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (value) async {
                                      if (value == 'openPdf') {
                                        await _openPdf(item);
                                      } else if (value == 'edit') {
                                        await _editRecordDetails(item);
                                      } else if (value == 'delete') {
                                        await vm.deleteRecord(item.recordEntryId);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'openPdf', child: Text('Open PDF')),
                                      PopupMenuItem(value: 'edit', child: Text('Edit details')),
                                      PopupMenuItem(value: 'delete', child: Text('Delete record')),
                                    ],
                                  ),
                                ),
                              );
                            },
                          )
                        : _RecordsTable(
                            rows: rows,
                            fields: tableFields,
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
