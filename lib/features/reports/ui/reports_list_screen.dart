import 'dart:io';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../data/reports_repository.dart';
import '../providers/report_editor_provider.dart';
import '../providers/reports_list_provider.dart';
import 'report_editor_screen.dart';
import 'template_list_screen.dart';

class ReportsListScreen extends StatelessWidget {
  const ReportsListScreen({super.key});

  Future<_SavedReportAction?> _askOpenChoice(BuildContext context, String title) {
    return showModalBottomSheet<_SavedReportAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(title),
              subtitle: const Text('Choose how to open this saved report.'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Open PDF'),
              subtitle: const Text('Recommended'),
              onTap: () => Navigator.pop(ctx, _SavedReportAction.openPdf),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note_outlined),
              title: const Text('Continue editing'),
              subtitle: const Text('Open the editable draft'),
              onTap: () => Navigator.pop(ctx, _SavedReportAction.continueEditing),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listVm = context.watch<ReportsListProvider>();
    final repo = context.read<ReportsRepository>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => listVm.refresh(),
          ),
          IconButton(
            icon: const Icon(Icons.view_list_outlined),
            tooltip: 'Templates',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TemplatesListScreen()),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          context.read<ReportEditorProvider>().newReport();
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportEditorScreen()));
        },
        icon: const Icon(Icons.add),
        label: const Text('New Report'),
      ),
      body: Builder(
        builder: (_) {
          if (listVm.loading) return const Center(child: CircularProgressIndicator());
          if (listVm.reports.isEmpty) {
            return const Center(child: Text('No saved reports yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: listVm.reports.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final r = listVm.reports[i];
              return Card(
                child: ListTile(
                  title: Text(r.title),
                  subtitle: Text('Updated: ${r.updatedAt}'),
                  onTap: () async {
                    final action = await _askOpenChoice(context, r.title);
                    if (action == null || !context.mounted) return;

                    if (action == _SavedReportAction.openPdf) {
                      final pdfFile = await repo.pdfFileForReport(r.reportId);
                      if (!context.mounted) return;

                      if (!await pdfFile.exists()) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('PDF not found yet. Open the report and save from Preview first.')),
                        );
                        return;
                      }

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _SavedPdfViewScreen(file: pdfFile, title: r.title),
                        ),
                      );
                      return;
                    }

                    await context.read<ReportEditorProvider>().loadById(r.reportId);
                    if (!context.mounted) return;
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportEditorScreen()));
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => listVm.delete(r.reportId),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

enum _SavedReportAction { openPdf, continueEditing }

class _SavedPdfViewScreen extends StatelessWidget {
  final File file;
  final String title;

  const _SavedPdfViewScreen({required this.file, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PdfPreview(
        build: (_) => file.readAsBytes(),
        allowPrinting: true,
        allowSharing: true,
      ),
    );
  }
}
