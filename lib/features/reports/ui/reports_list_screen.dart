import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/reports_repository.dart';
import '../providers/report_editor_provider.dart';
import '../providers/reports_list_provider.dart';
import 'report_editor_screen.dart';
import 'saved_pdf_viewer_screen.dart';
import 'template_list_screen.dart';

class ReportsListScreen extends StatelessWidget {
  const ReportsListScreen({super.key});

  Future<_SavedReportOpenChoice?> _askOpenChoice(
    BuildContext context,
    ReportSummary report,
  ) {
    return showModalBottomSheet<_SavedReportOpenChoice>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Text(
                  report.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Text('Choose how to open this saved report.'),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Open PDF'),
                onTap: () => Navigator.pop(ctx, _SavedReportOpenChoice.openPdf),
              ),
              ListTile(
                leading: const Icon(Icons.edit_note_outlined),
                title: const Text('Continue editing'),
                subtitle: const Text('Open the editable draft'),
                onTap: () => Navigator.pop(ctx, _SavedReportOpenChoice.continueEditing),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleOpen(BuildContext context, ReportSummary report) async {
    if (!report.hasPdf) {
      await context.read<ReportEditorProvider>().loadById(report.reportId);
      if (!context.mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportEditorScreen()));
      return;
    }

    final choice = await _askOpenChoice(context, report);
    if (choice == null || !context.mounted) return;

    if (choice == _SavedReportOpenChoice.openPdf) {
      final repo = context.read<ReportsRepository>();
      final pdfBytes = await repo.loadPdfBytesForReport(report.reportId);
      if (!context.mounted) return;

      if (pdfBytes != null && pdfBytes.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SavedPdfViewerScreen(
              title: report.title,
              pdfBytesFuture: Future.value(pdfBytes),
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No saved PDF found yet. Open the draft and save from Preview first.')),
      );
      return;
    }

    await context.read<ReportEditorProvider>().loadById(report.reportId);
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportEditorScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final listVm = context.watch<ReportsListProvider>();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('My Reports'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Reload reports',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => listVm.refresh(),
                ),
                const SizedBox(width: 12),
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
              final accent = r.hasPdf
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest;
              final icon = r.hasPdf ? Icons.description_outlined : Icons.edit_note_outlined;
              final badgeText = r.hasPdf ? 'Report' : 'Saved work';
              return Card(
                color: accent.withOpacity(r.hasPdf ? 0.55 : 0.45),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    child: Icon(icon),
                  ),
                  title: Row(
                    children: [
                      Expanded(child: Text(r.title, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badgeText,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(r.subtitle),
                  ),
                  onTap: () => _handleOpen(context, r),
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

enum _SavedReportOpenChoice { openPdf, continueEditing }
