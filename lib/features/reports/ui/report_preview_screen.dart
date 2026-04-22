import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../access/providers/access_provider.dart';
import '../../access/ui/upgrade_screen.dart';
import '../domain/pdf/pdf_layout_metrics.dart';
import '../domain/pdf/pdf_plan_builder.dart';
import '../domain/models/letterhead_template.dart';
import '../domain/models/report_doc.dart';
import '../providers/report_editor_provider.dart';
import '../services/pdf_renderer_service.dart';
import '../services/pdf_actions_service.dart';
import '../../../core/web/file_download.dart';
import '../data/letterhead_repository.dart';
import '../data/reports_repository.dart';
import '../ui/letterhead_editor_screen.dart';
import '../ui/manage_letterhead.screen.dart';
import '../../records/providers/records_provider.dart';
import '../../records/ui/record_details_screen.dart';

class ReportPreviewScreen extends StatefulWidget {
  const ReportPreviewScreen({super.key});

  @override
  State<ReportPreviewScreen> createState() => _ReportPreviewScreenState();
}

class _ReportPreviewScreenState extends State<ReportPreviewScreen> {
  final _renderer = PdfRendererService();
  final _planBuilder = const PdfPlanBuilder();
  bool _saving = false;

  Future<Uint8List> _buildBytes() async {
    final vm = context.read<ReportEditorProvider>();
    final repo = context.read<LetterheadsRepository>();
    final access = context.read<AccessProvider>().safeState;

    LetterheadTemplate? letterhead;

    if (access.canUseLetterhead && vm.doc.applyLetterhead && vm.doc.letterheadId != null) {
      letterhead = await repo.loadLetterhead(vm.doc.letterheadId!);
    }

    final metrics = PdfLayoutMetrics(
      headerReserve: letterhead != null ? 90.0 : 0.0,
      footerReserve: letterhead != null ? 45.0 : 0.0,
    );
    final plan = _planBuilder.build(vm.doc, metrics: metrics);

    return _renderer.generatePdfBytes(
      doc: vm.doc,
      plan: plan,
      letterhead: letterhead,
      showRipotBranding: !access.canRemoveBranding,
    );
  }


  Future<String> _savePdfToLocal(Uint8List bytes, ReportDoc doc) async {
    final repo = context.read<ReportsRepository>();
    await repo.savePdfBytesForReport(doc.reportId, bytes, doc: doc);
    return repo.pdfFileNameForDoc(doc);
  }

  Future<void> _onSavePressed() async {
    if (_saving) return;

    final vm = context.read<ReportEditorProvider>();
    final reportsRepo = context.read<ReportsRepository>();
    final access = context.read<AccessProvider>().safeState;
    final currentReports = await reportsRepo.listReports();
    final isExisting = currentReports.any((r) => r.reportId == vm.doc.reportId);
    if (!isExisting && currentReports.length >= access.maxSavedReports) {
      if (!mounted) return;
      final open = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Report limit reached'),
          content: Text('Free plan allows up to ${access.maxSavedReports} saved reports. Start a premium trial to save more.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Later')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('See Premium')),
          ],
        ),
      );
      if (open == true && mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const UpgradeScreen()));
      }
      return;
    }

    setState(() => _saving = true);

    try {
      await vm.save();

      final bytes = await _buildBytes();

      final fileName = await _savePdfToLocal(bytes, vm.doc);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF saved: $fileName')),
      );
      await _offerAddToRecords();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  Future<void> _offerAddToRecords() async {
    final vm = context.read<ReportEditorProvider>();
    final provider = context.read<RecordsProvider>();
    final existing = await provider.repo.loadByReportId(vm.doc.reportId);
    if (existing != null || !mounted) return;
    final shouldOpen = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add this report to Records?',
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Records are optional, but they make this report easier to find later in list or table form.',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext, false),
                        child: const Text('Not now'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        icon: const Icon(Icons.library_add_outlined),
                        label: const Text('Add to Records'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (shouldOpen != true || !mounted) return;
    final draft = await provider.draftForReport(vm.doc);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecordDetailsScreen(initialEntry: draft)),
    );
  }

  Future<void> _openLetterheadSheet() async {
    final access = context.read<AccessProvider>().safeState;
    if (!access.canUseLetterhead) {
      if (!mounted) return;
      final open = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Premium feature'),
          content: const Text('Custom letterhead is available in Premium Trial and Premium.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Later')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('See Premium')),
          ],
        ),
      );
      if (open == true && mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const UpgradeScreen()));
      }
      return;
    }

    final vm = context.read<ReportEditorProvider>();
    final repo = context.read<LetterheadsRepository>();

    final templates = await repo.loadAll();

    if (!mounted) return;

    const addToken = '__add__';
    const manageToken = '__manage__';
    const noneToken = '__none__';
    String tempSelected = vm.doc.letterheadId ?? noneToken;

    debugPrint(
  'letterhead open -> id=${vm.doc.letterheadId}, apply=${vm.doc.applyLetterhead}',
);




    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        

        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  const SizedBox(height: 12),
                  const Center(
                    child: Text(
                      'Select Letterhead',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Divider(),
                  RadioListTile<String>(
                    value: noneToken,
                    groupValue: tempSelected,
                    title: const Text('None'),
                    onChanged: (value) {
                      if (value == null) return;
                      setModalState(() => tempSelected = value);
                      vm.setLetterhead(null);
                    },
                  ),
                  ...templates.map(
                    (t) => RadioListTile<String>(
                      value: t.letterheadId,
                      groupValue: tempSelected,
                      title: Text(t.name),
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() => tempSelected = value);
                        vm.setLetterhead(value);
                      },
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Add new letterhead'),
                    onTap: () => Navigator.pop(sheetContext, addToken),
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('Manage letterheads'),
                    onTap: () => Navigator.pop(sheetContext, manageToken),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted) return;

    if (result == addToken) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const LetterheadEditorScreen(letterheadId: null),
        ),
      );
      return;
    }

    if (result == manageToken) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const ManageLetterheadsScreen(),
        ),
      );
      return;
    }
  }

  void _openLayoutSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Consumer<ReportEditorProvider>(
            builder: (context, vm, _) {
              final layout = vm.doc.reportLayout;
              final indentContent = vm.doc.indentContent;
              final indentHierarchy = vm.doc.indentHierarchy;
              final applyIndentation = indentContent || indentHierarchy;
              final showColonAfterTitlesWithContent = vm.doc.showColonAfterTitlesWithContent;
              final scale = vm.doc.fontScale;

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  const Text(
                    'Report layout',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 8),

                  RadioListTile<ReportLayout>(
                    value: ReportLayout.block,
                    groupValue: layout,
                    onChanged: (v) {
                      if (v != null) vm.setReportLayout(v);
                    },
                    title: const Text(
                      'Block (section title on its own line)',
                    ),
                    dense: true,
                  ),

                  RadioListTile<ReportLayout>(
                    value: ReportLayout.aligned,
                    groupValue: layout,
                    onChanged: (v) {
                      if (v != null) vm.setReportLayout(v);
                    },
                    title: const Text('Aligned (two-column style)'),
                    dense: true,
                  ),

                  if (layout == ReportLayout.block || layout == ReportLayout.aligned) ...[
                    const Divider(height: 24),
                    SwitchListTile(
                      value: applyIndentation,
                      onChanged: (enabled) {
                        if (enabled) {
                          vm.setIndentHierarchy(true);
                          if (layout == ReportLayout.block) {
                            vm.setIndentContent(true);
                          }
                        } else {
                          vm.setIndentHierarchy(false);
                          vm.setIndentContent(false);
                        }
                      },
                      title: const Text('Apply indentation'),
                      dense: true,
                    ),
                    if (applyIndentation) ...[
                      if (layout == ReportLayout.block)
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: CheckboxListTile(
                            value: indentContent,
                            onChanged: (v) => vm.setIndentContent(v ?? false),
                            title: const Text('Content'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: CheckboxListTile(
                          value: indentHierarchy,
                          onChanged: (v) => vm.setIndentHierarchy(v ?? false),
                          title: const Text('Hierarchy / subsections'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ),
                    ],
                    const Divider(height: 24),
                    SwitchListTile(
                      value: showColonAfterTitlesWithContent,
                      onChanged: vm.setShowColonAfterTitlesWithContent,
                      title: const Text('Show colons'),
                      dense: true,
                    ),
                    const Divider(height: 24),
                  ],

                  const Text(
                    'Global font size',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Slider(
                    value: scale,
                    min: 0.85,
                    max: 1.35,
                    divisions: 10,
                    label: scale.toStringAsFixed(2),
                    onChanged: vm.setFontScale,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      layout == ReportLayout.aligned
                          ? 'Applies to aligned layout too'
                          : 'Applies to the current layout',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                ],
              ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        toolbarHeight: 56,
        titleSpacing: 0,
        actions: [
          IconButton(
            tooltip: 'Letterhead',
            icon: const Icon(Icons.view_headline_outlined),
            onPressed: _openLetterheadSheet,
          ),
          IconButton(
            tooltip: 'Layout',
            icon: const Icon(Icons.tune),
            onPressed: _openLayoutSheet,
          ),
          if (kIsWeb)
            IconButton(
              tooltip: 'Download PDF',
              icon: const Icon(Icons.download_outlined),
              onPressed: () async {
                final bytes = await _buildBytes();
                if (!mounted) return;
                final reportsRepo = context.read<ReportsRepository>();
                final pdfFileName = reportsRepo.pdfFileNameForDoc(context.read<ReportEditorProvider>().doc);
                await downloadBytes(bytes: bytes, fileName: pdfFileName);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('PDF downloaded: $pdfFileName')),
                );
                await _offerAddToRecords();
              },
            ),
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            onPressed: _saving ? null : _onSavePressed,
          ),
        ],
      ),
      body: Consumer<ReportEditorProvider>(
        builder: (context, vm, _) {
          final reportsRepo = context.read<ReportsRepository>();
          final pdfFileName = reportsRepo.pdfFileNameForDoc(vm.doc);
          return LayoutBuilder(
            builder: (context, constraints) {
              final isDesktopWeb = kIsWeb && constraints.maxWidth >= 900;
              final isNativeDesktop = ripotIsNativeDesktop;
              final preview = ConstrainedBox(
                constraints: BoxConstraints.tightFor(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                ),
                child: PdfPreview(
                  key: ValueKey(
                    "preview-${vm.doc.reportLayout}-${vm.doc.indentContent}-${vm.doc.indentHierarchy}-${vm.doc.showColonAfterTitlesWithContent}-${vm.doc.fontScale}-${vm.doc.applyLetterhead}-${vm.doc.letterheadId}-${vm.doc.updatedAtIso}",
                  ),
                  build: (_) => _buildBytes(),
                  pdfFileName: pdfFileName,
                  allowPrinting: !isNativeDesktop,
                  allowSharing: !isDesktopWeb && !isNativeDesktop,
                ),
              );

              final header = Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Preview',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isDesktopWeb
                            ? 'On desktop web, use the download button in the preview toolbar, then share the PDF from your downloads.'
                            : 'On desktop, use the Ripot buttons below for Download, Print, and Share.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              );

              if (!isDesktopWeb && !isNativeDesktop) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Center(
                        child: Text(
                          'Preview',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                    ),
                    Expanded(child: preview),
                  ],
                );
              }

              return Column(
                children: [
                  header,
                  if (isNativeDesktop)
                    FutureBuilder<Uint8List>(
                      future: _buildBytes(),
                      builder: (context, snapshot) {
                        final bytes = snapshot.data;
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: bytes == null
                                      ? null
                                      : () async {
                                          try {
                                            final file = await ripotDownloadPdf(
                                              bytes: bytes,
                                              fileName: pdfFileName,
                                            );
                                            if (!context.mounted) return;

                                            if (file != null) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('PDF saved to: ${file.path}')),
                                              );
                                            } else {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Download cancelled')),
                                              );
                                            }
                                          } catch (e) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Download failed: $e')),
                                            );
                                          }
                                        },
                                  icon: const Icon(Icons.download_outlined),
                                  label: const Text('Download PDF'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: bytes == null
                                      ? null
                                      : () async {
                                          try {
                                            await ripotPrintPdf(bytes: bytes, fileName: pdfFileName);
                                          } catch (e) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Print failed: $e')),
                                            );
                                          }
                                        },
                                  icon: const Icon(Icons.print_outlined),
                                  label: const Text('Print PDF'),
                                ),
                                FilledButton.icon(
                                  onPressed: bytes == null
                                      ? null
                                      : () async {
                                          try {
                                            await ripotSharePdf(bytes: bytes, fileName: pdfFileName);
                                          } catch (e) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Share failed: $e')),
                                            );
                                          }
                                        },
                                  icon: const Icon(Icons.share_outlined),
                                  label: const Text('Share PDF'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  Expanded(child: preview),
                ],
              );
            },
          );
        },
      ),
    );
  }
}