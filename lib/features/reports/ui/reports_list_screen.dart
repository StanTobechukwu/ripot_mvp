import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/reports_repository.dart';
import '../providers/report_editor_provider.dart';
import '../providers/reports_list_provider.dart';
import '../../access/providers/access_provider.dart';
import '../../access/ui/upgrade_screen.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/ui/auth_screens.dart';
import 'report_editor_screen.dart';
import 'saved_pdf_viewer_screen.dart';
import 'template_list_screen.dart';
import '../../records/ui/records_screen.dart';

class ReportsListScreen extends StatelessWidget {
  const ReportsListScreen({super.key});

  Future<void> _openPdf(BuildContext context, ReportSummary report) async {
    final repo = context.read<ReportsRepository>();
    final pdfBytes = await repo.loadPdfBytesForReport(report.reportId);
    final pdfFileName = await repo.pdfFileNameForReport(report.reportId) ?? '${report.title}.pdf';
    if (!context.mounted) return;

    if (pdfBytes != null && pdfBytes.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SavedPdfViewerScreen(
            title: report.title,
            pdfFileName: pdfFileName,
            pdfBytesFuture: Future.value(pdfBytes),
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No saved PDF found yet.')),
    );
  }

  Future<void> _openEditor(BuildContext context, String reportId) async {
    await context.read<ReportEditorProvider>().loadById(reportId);
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportEditorScreen()));
  }

  Future<void> _handleOpen(BuildContext context, ReportSummary report) async {
    if (report.isSavedWork) {
      await _openEditor(context, report.reportId);
      return;
    }
    await _openPdf(context, report);
  }

  void _openTemplates(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TemplatesListScreen()),
    );
  }

  void _openRecords(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecordsScreen()),
    );
  }

  void _openPremium(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UpgradeScreen()),
    );
  }

  void _openAccount(BuildContext context) => openAccountSheet(context);

  @override
  Widget build(BuildContext context) {
    final listVm = context.watch<ReportsListProvider>();
    final access = context.watch<AccessProvider>().safeState;
    final width = MediaQuery.of(context).size.width;
    final compactTopBar = width < 760;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 56,
       // leadingWidth: 132,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {},
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/ripot_icon.png',
                  height: 24,
                  width: 24,
                  errorBuilder: (_, __, ___) => const Icon(Icons.description_outlined, size: 22),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Ripot',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
        leadingWidth: 132,
        title: const SizedBox.shrink(),
        actions: [
          IconButton(
            tooltip: 'Reload reports',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => listVm.refresh(),
          ),
          IconButton(
            icon: const Icon(Icons.library_books_outlined),
            tooltip: 'Templates',
            onPressed: () => _openTemplates(context),
          ),
          if (width >= 980)
            IconButton(
              icon: const Icon(Icons.table_rows_rounded),
              tooltip: 'Records',
              onPressed: () => _openRecords(context),
            ),
          if (width >= 1100)
            IconButton(
              icon: const Icon(Icons.workspace_premium_outlined),
              tooltip: 'Ripot Premium',
              onPressed: () => _openPremium(context),
            ),
          Consumer<AuthProvider>(
            builder: (context, auth, _) => IconButton(
              icon: Icon(auth.isSignedIn ? Icons.account_circle : Icons.account_circle_outlined),
              tooltip: auth.isSignedIn ? 'Account' : 'Sign in or create account',
              onPressed: () => _openAccount(context),
            ),
          ),
          if (width < 1100)
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (value) {
                switch (value) {
                  case 'records':
                    _openRecords(context);
                    break;
                  case 'premium':
                    _openPremium(context);
                    break;
                }
              },
              itemBuilder: (_) => [
                if (width < 980) const PopupMenuItem(value: 'records', child: Text('Records')),
                if (width < 1100) const PopupMenuItem(value: 'premium', child: Text('Ripot Premium')),
              ],
            ),
          const SizedBox(width: 8),
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
      body: Column(
        children: [
          const SizedBox(height: 8),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'My Reports',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  access.badgeLabel,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Builder(
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
                    final badgeText = r.hasPdf
                        ? (r.isFinalized ? 'Final PDF' : 'Report')
                        : 'Saved work';
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
          ),
        ],
      ),
    );
  }
}

