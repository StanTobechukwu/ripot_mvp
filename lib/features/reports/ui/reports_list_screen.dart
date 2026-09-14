import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../../core/ui/item_actions.dart';
import '../../logbook/data/logbook_repository.dart';
import '../../logbook/services/report_log_draft.dart';
import '../../logbook/ui/logbook_screen.dart';
import '../../logbook/ui/log_entry_editor.dart';
import '../../logbook/ui/log_entry_detail.dart';
import '../../records/ui/record_details_screen.dart';
import '../../records/ui/records_field_picker.dart';
import '../../registry/ui/registry_screen.dart';
import 'package:provider/provider.dart';

import '../data/reports_repository.dart';
import '../providers/report_editor_provider.dart';
import '../providers/reports_list_provider.dart';
import '../providers/template_list_provider.dart';
import '../../access/providers/access_provider.dart';
import '../../access/ui/upgrade_screen.dart';
import '../../access/ui/premium_prompt.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/ui/auth_screens.dart';
import 'report_editor_screen.dart';
import 'saved_pdf_viewer_screen.dart';
import 'template_list_screen.dart';
import '../../records/ui/records_screen.dart';
import '../../records/providers/records_provider.dart';
import '../../../core/navigation/app_route_observer.dart';
import '../../../core/platform/incoming_file_service.dart';
import '../data/templates_repository.dart';
import '../../records/data/records_repository.dart';

class ReportsListScreen extends StatefulWidget {
  const ReportsListScreen({super.key});

  @override
  State<ReportsListScreen> createState() => _ReportsListScreenState();
}

class _ReportsListScreenState extends State<ReportsListScreen> with RouteAware {
  bool _routeObserverSubscribed = false;
  int _section = 0;

  Future<void> _selectSection(int index) async {
    if (index == 2 && !context.read<AccessProvider>().safeState.canUseRecords) {
      await showPremiumFeatureSheet(context, PremiumFeature.records);
      return;
    }
    if (!mounted) return;
    setState(() => _section = index);
    if (index == 0) await _refreshReports();
  }

  Widget _navigation() => NavigationBar(
    selectedIndex: _section,
    onDestinationSelected: _selectSection,
    destinations: const [
      NavigationDestination(icon: Icon(Icons.description_outlined), label: 'Reports'),
      NavigationDestination(icon: Icon(Icons.library_books_outlined), label: 'Templates'),
      NavigationDestination(icon: Icon(Icons.table_rows_outlined), label: 'Records'),
      NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: 'Logbook'),
    ],
  );
  IncomingFileService? _incomingFileService;

  Future<void> _refreshReports() async {
    if (!mounted) return;
    await context.read<ReportsListProvider>().refresh();
  }

  Future<void> _refreshAfterIncomingFile(IncomingFileResult result) async {
    if (!mounted) return;
    if (result.changed) {
      await context.read<TemplateListProvider>().load();
      await context.read<RecordsProvider>().refresh();
      await context.read<ReportsListProvider>().refresh();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _incomingFileService = IncomingFileService(
        templatesRepository: context.read<TemplatesRepository>(),
        recordsRepository: context.read<RecordsRepository>(),
        reportsRepository: context.read<ReportsRepository>(),
      );
      _incomingFileService?.listen((result) {
        _refreshAfterIncomingFile(result);
      });
      final initial = await _incomingFileService?.handleInitialFile();
      if (initial != null) {
        await _refreshAfterIncomingFile(initial);
      }
      await _refreshReports();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeObserverSubscribed) return;
    final route = ModalRoute.of(context);
    if (route is ModalRoute<dynamic>) {
      appRouteObserver.subscribe(this, route);
      _routeObserverSubscribed = true;
    }
  }

  @override
  void didPopNext() {
    // Called when a screen above My Reports is popped.
    // This catches nested flows such as:
    // My Reports → Templates → Template editor/report → Save → back to My Reports.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshReports();
    });
  }

  @override
  void dispose() {
    if (_routeObserverSubscribed) {
      appRouteObserver.unsubscribe(this);
    }
    super.dispose();
  }

  Future<void> _openPdf(BuildContext context, ReportSummary report) async {
    final repo = context.read<ReportsRepository>();
    final pdfBytes = await repo.loadPdfBytesForReport(report.reportId);
    final pdfFileName =
        await repo.pdfFileNameForReport(report.reportId) ??
        '${report.title}.pdf';
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

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('No saved PDF found yet.')));
  }

  Future<void> _openEditor(BuildContext context, String reportId) async {
    await context.read<ReportEditorProvider>().loadById(reportId);
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReportEditorScreen()),
    );
    if (!context.mounted) return;
    await _refreshReports();
  }

  Future<void> _handleOpen(BuildContext context, ReportSummary report) async {
    if (report.isSavedWork) {
      await _openEditor(context, report.reportId);
      return;
    }
    await _openPdf(context, report);
  }

  Future<void> _confirmAndDeleteReport(
    BuildContext context,
    ReportSummary report,
  ) async {
    const title = 'Delete report?';
    const message =
        'This permanently deletes the saved report and any saved PDF for it from this device. Existing Records and Logbook entries are kept. This cannot be undone.';
    const actionLabel = 'Delete report';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await context.read<ReportsListProvider>().delete(report.reportId);
  }

  Future<void> _reportActions(
    BuildContext context,
    ReportSummary report,
  ) async {
    final book = context.read<LogbookRepository>();
    final action = await showItemActions(context, report.title, [
      if (report.canContinueEditing)
        const ItemAction('edit', 'Continue editing', Icons.edit_outlined),
      if (report.hasPdf)
        const ItemAction('pdf', 'View PDF', Icons.picture_as_pdf_outlined),
      if (report.hasPdf)
        const ItemAction('share', 'Share PDF', Icons.ios_share),
      ItemAction(
        'records',
        report.hasPdf ? 'Add to Records' : 'Records · Generate report first',
        Icons.table_rows_outlined,
      ),
      ItemAction(
        'log',
        book.forReport(report.reportId) == null
            ? 'Add to Logbook'
            : 'View log entry',
        Icons.menu_book_outlined,
      ),
      if (report.hasPdf)
        const ItemAction('registry', 'Add to Registry', Icons.people_outline),
      const ItemAction(
        'delete',
        'Delete report',
        Icons.delete_outline,
        destructive: true,
      ),
    ]);
    if (action == null || !context.mounted) return;
    try {
      final repo = context.read<ReportsRepository>();
      switch (action) {
        case 'registry':
          final doc = await repo.loadReport(report.reportId);
          if (!context.mounted) return;
          final draft = context
              .read<RecordsRepository>()
              .registrySourceForReport(doc);
          if (context.mounted) await openRegistry(context, source: draft);
          break;
        case 'edit':
          await _openEditor(context, report.reportId);
          break;
        case 'pdf':
          await _openPdf(context, report);
          break;
        case 'share':
          final bytes = await repo.loadPdfBytesForReport(report.reportId);
          if (bytes == null) throw StateError('PDF unavailable');
          await Printing.sharePdf(
            bytes: bytes,
            filename:
                await repo.pdfFileNameForReport(report.reportId) ??
                'Ripot_Report.pdf',
          );
          break;
        case 'records':
          if (!report.hasPdf) {
            final openEditor = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Generate the report first'),
                content: const Text(
                  'Records are created from the finished PDF report. Continue editing, then generate the report to add it to Records.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Not now'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Continue editing'),
                  ),
                ],
              ),
            );
            if (openEditor == true && context.mounted) {
              await _openEditor(context, report.reportId);
            }
            return;
          }
          if (!context.read<AccessProvider>().safeState.canUseRecords) {
            await showPremiumFeatureSheet(context, PremiumFeature.records);
            return;
          }
          final records = context.read<RecordsRepository>();
          final doc = await repo.loadReport(report.reportId);
          if (!context.mounted) return;
          final selected = await prepareReportRecords(context, doc);
          if (selected == null) return;
          final draft = await records.buildDraftForReport(selected);
          if (!context.mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RecordDetailsScreen(initialEntry: draft),
            ),
          );
          break;
        case 'log':
          await book.load();
          if (!book.loaded) throw StateError('Logbook unavailable');
          final existing = book.forReport(report.reportId);
          if (!context.mounted) return;
          if (existing != null) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LogEntryDetail(entryId: existing.id),
              ),
            );
          } else {
            final doc = await repo.loadReport(report.reportId);
            if (!context.mounted) return;
            final id = await Navigator.push<String>(
              context,
              MaterialPageRoute(
                builder: (_) => LogEntryEditor(
                  prefill: logDataFromReport(doc, meId: book.data.meId),
                  linkedReportId: report.reportId,
                ),
              ),
            );
            if (id != null && context.mounted)
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => LogEntryDetail(entryId: id)),
              );
          }
          break;
        case 'delete':
          await _confirmAndDeleteReport(context, report);
          break;
      }
    } catch (_) {
      if (context.mounted)
        showMessage(
          context,
          'Could not complete that action. Please try again.',
        );
    }
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
    if (_section != 0) {
      return Scaffold(
        body: KeyedSubtree(
          key: ValueKey(_section),
          child: switch (_section) {
            1 => const TemplatesListScreen(),
            2 => const RecordsScreen(),
            _ => const LogbookScreen(),
          },
        ),
        bottomNavigationBar: _navigation(),
      );
    }

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
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.description_outlined, size: 22),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Ripot',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        leadingWidth: 132,
        title: const SizedBox.shrink(),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.people_outline),
            label: const Text('Registry'),
            onPressed: () => openRegistry(context),
          ),
          Consumer<AuthProvider>(
            builder: (context, auth, _) => IconButton(
              icon: Icon(
                auth.isSignedIn
                    ? Icons.account_circle
                    : Icons.account_circle_outlined,
              ),
              tooltip: auth.isSignedIn
                  ? 'Account'
                  : 'Sign in or create account',
              onPressed: () => _openAccount(context),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (value) {
              switch (value) {
                case 'registry':
                  openRegistry(context);
                  break;
                case 'premium':
                  _openPremium(context);
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'premium',
                  child: Text('Ripot Premium'),
                ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: _navigation(),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 6,
        onPressed: () async {
          context.read<ReportEditorProvider>().newReport();
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ReportEditorScreen()),
          );
          if (!context.mounted) return;
          await _refreshReports();
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
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                  ),
                  onPressed: () => _openPremium(context),
                  icon: Icon(
                    access.isPremiumLike
                        ? Icons.workspace_premium
                        : Icons.workspace_premium_outlined,
                    size: 16,
                  ),
                  label: Text(
                    access.isTrialActive
                        ? 'Premium trial • ${access.daysRemaining} days remaining'
                        : access.badgeLabel == 'Premium'
                        ? 'Premium'
                        : 'Free plan • See Premium',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Builder(
              builder: (_) {
                if (listVm.loading)
                  return const Center(child: CircularProgressIndicator());
                if (listVm.reports.isEmpty) {
                  return const Center(child: Text('No saved reports yet.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 100),
                  itemCount: listVm.reports.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final r = listVm.reports[i];
                    final accent = r.hasPdf
                        ? Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withOpacity(0.34)
                        : Theme.of(context).colorScheme.surfaceContainerHighest
                              .withOpacity(0.55);
                    final icon = r.hasPdf
                        ? Icons.description_outlined
                        : Icons.edit_note_outlined;
                    final badgeText = r.hasPdf
                        ? (r.isFinalized ? 'PDF Report' : 'Report')
                        : 'Saved work';
                    return Card(
                      color: accent,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surface,
                          child: Icon(icon),
                        ),
                        contentPadding: const EdgeInsets.fromLTRB(
                          16,
                          10,
                          8,
                          10,
                        ),
                        title: Text(
                          r.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                badgeText,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(r.subtitle),
                            ],
                          ),
                        ),
                        onTap: () => _handleOpen(context, r),
                        onLongPress: () => _reportActions(context, r),
                        trailing: IconButton(
                          tooltip: 'Options for ${r.title}',
                          icon: const Icon(Icons.more_vert),
                          onPressed: () => _reportActions(context, r),
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
