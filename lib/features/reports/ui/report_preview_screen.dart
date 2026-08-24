import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../../core/web/file_download.dart';
import '../../access/providers/access_provider.dart';
import '../../access/ui/upgrade_screen.dart';
import '../../records/providers/records_provider.dart';
import '../../records/ui/record_details_screen.dart';
import '../data/letterhead_repository.dart';
import '../data/reports_repository.dart';
import '../domain/models/letterhead_template.dart';
import '../domain/models/report_doc.dart';
import '../domain/pdf/pdf_layout_metrics.dart';
import '../domain/pdf/pdf_plan_builder.dart';
import '../providers/report_editor_provider.dart';
import '../services/pdf_actions_service.dart';
import '../services/pdf_renderer_service.dart';
import '../ui/letterhead_editor_screen.dart';
import '../ui/manage_letterhead.screen.dart';

class ReportPreviewScreen extends StatefulWidget {
  const ReportPreviewScreen({super.key});

  @override
  State<ReportPreviewScreen> createState() => _ReportPreviewScreenState();
}

class _ReportPreviewScreenState extends State<ReportPreviewScreen> {
  final _renderer = PdfRendererService();
  final _planBuilder = const PdfPlanBuilder();

  bool _saving = false;

  // The selected letterhead ID does not change when the same letterhead
  // is edited. Incrementing this value forces PdfPreview to rebuild
  // using the latest saved letterhead contents.
  int _letterheadPreviewRevision = 0;

  void _refreshLetterheadPreview() {
    if (!mounted) return;

    setState(() {
      _letterheadPreviewRevision++;
    });
  }

  Future<Uint8List> _buildBytes() async {
    final vm = context.read<ReportEditorProvider>();
    final repo = context.read<LetterheadsRepository>();
    final access = context.read<AccessProvider>().safeState;

    LetterheadTemplate? letterhead;

    if (access.canUseLetterhead &&
        vm.doc.letterheadMode == LetterheadMode.digital &&
        vm.doc.letterheadId != null) {
      letterhead = await repo.loadLetterhead(
        vm.doc.letterheadId!,
      );
    }

    final isPrePrinted =
        access.canUseLetterhead &&
        vm.doc.letterheadMode == LetterheadMode.prePrinted;

    final metrics = PdfLayoutMetrics(
      headerReserve:
          isPrePrinted
              ? vm.doc.prePrintedTopSpacing.points
              : _digitalLetterheadHeaderReserve(letterhead),
      footerReserve:
          isPrePrinted && vm.doc.reservePrePrintedFooter
              ? 50.0
              : _digitalLetterheadFooterReserve(letterhead),
    );

    final plan = _planBuilder.build(
      vm.doc,
      metrics: metrics,
    );

    return _renderer.generatePdfBytes(
      doc: vm.doc,
      plan: plan,
      layoutMetrics: metrics,
      letterhead: letterhead,
      showRipotBranding: !access.canRemoveBranding,
    );
  }

  double _digitalLetterheadHeaderReserve(
    LetterheadTemplate? letterhead,
  ) {
    if (letterhead == null) return 0.0;

    final hasLogo =
        (letterhead.logoFilePath ?? '').trim().isNotEmpty;

    if (!hasLogo) return 36.0;

    if (letterhead.logoPlacement ==
        LetterheadLogoPlacement.side) {
      return 56.0;
    }

    return 78.0;
  }

  double _digitalLetterheadFooterReserve(
    LetterheadTemplate? letterhead,
  ) {
    if (letterhead == null) return 0.0;

    final hasFooter =
        letterhead.footerLeft.trim().isNotEmpty ||
        letterhead.footerRight.trim().isNotEmpty;

    return hasFooter ? 28.0 : 0.0;
  }

  Future<String> _savePdfToLocal(
    Uint8List bytes,
    ReportDoc doc,
  ) async {
    final repo = context.read<ReportsRepository>();

    await repo.savePdfBytesForReport(
      doc.reportId,
      bytes,
      doc: doc,
    );

    return repo.pdfFileNameForDoc(doc);
  }

  Future<bool> _confirmFinalizePdf() async {
    final result = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Save final PDF?'),
            content: const Text(
              'This will finalize the report as a PDF. '
              'The saved version will open as a PDF, not an editable draft.',
            ),
            actions: [
              TextButton(
                onPressed:
                    () => Navigator.pop(
                      dialogContext,
                      false,
                    ),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    () => Navigator.pop(
                      dialogContext,
                      true,
                    ),
                child: const Text('Save PDF'),
              ),
            ],
          ),
    );

    return result == true;
  }

  Future<void> _onSavePressed() async {
    if (_saving) return;

    final vm = context.read<ReportEditorProvider>();
    final reportsRepo =
        context.read<ReportsRepository>();
    final access =
        context.read<AccessProvider>().safeState;

    final currentReports =
        await reportsRepo.listReports();

    final isExisting = currentReports.any(
      (r) => r.reportId == vm.doc.reportId,
    );

    if (!isExisting &&
        currentReports.length >=
            access.maxSavedReports) {
      if (!mounted) return;

      final open = await showDialog<bool>(
        context: context,
        builder:
            (_) => AlertDialog(
              title:
                  const Text(
                    'Report limit reached',
                  ),
              content: Text(
                'Free plan allows up to '
                '${access.maxSavedReports} saved reports. '
                'Start a premium trial to save more.',
              ),
              actions: [
                TextButton(
                  onPressed:
                      () => Navigator.pop(
                        context,
                        false,
                      ),
                  child:
                      const Text('Later'),
                ),
                FilledButton(
                  onPressed:
                      () => Navigator.pop(
                        context,
                        true,
                      ),
                  child:
                      const Text(
                        'See Premium',
                      ),
                ),
              ],
            ),
      );

      if (open == true && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) =>
                    const UpgradeScreen(),
          ),
        );
      }

      return;
    }

    final shouldContinue =
        await _confirmFinalizePdf();

    if (!shouldContinue || !mounted) {
      return;
    }

    setState(() => _saving = true);

    try {
      await vm.save();

      final bytes =
          await _buildBytes();

      final fileName =
          await _savePdfToLocal(
            bytes,
            vm.doc,
          );

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content:
              Text(
                'PDF saved: $fileName',
              ),
        ),
      );

      await _offerAddToRecords();
    } finally {
      if (mounted) {
        setState(
          () => _saving = false,
        );
      }
    }
  }

  Future<void> _offerAddToRecords() async {
    final access =
        context.read<AccessProvider>().safeState;

    if (!access.canUseRecords) {
      if (!mounted) return;

      final shouldUpgrade =
          await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder:
            (sheetContext) => SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(
                      20,
                      8,
                      20,
                      20,
                    ),
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Records is a Premium feature',
                      style:
                          Theme.of(
                            sheetContext,
                          ).textTheme.titleLarge?.copyWith(
                            fontWeight:
                                FontWeight.w700,
                          ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    const Text(
                      'Your PDF has been saved. Upgrade to add finalized reports '
                      'to searchable Records tables and procedure filters.',
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child:
                              OutlinedButton(
                                onPressed:
                                    () =>
                                        Navigator.pop(
                                          sheetContext,
                                          false,
                                        ),
                                child:
                                    const Text(
                                      'Not now',
                                    ),
                              ),
                        ),
                        const SizedBox(
                          width: 12,
                        ),
                        Expanded(
                          child:
                              FilledButton.icon(
                                onPressed:
                                    () =>
                                        Navigator.pop(
                                          sheetContext,
                                          true,
                                        ),
                                icon:
                                    const Icon(
                                      Icons
                                          .workspace_premium_outlined,
                                    ),
                                label:
                                    const Text(
                                      'View Premium',
                                    ),
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      );

      if (shouldUpgrade == true &&
          mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) =>
                    const UpgradeScreen(),
          ),
        );
      }

      return;
    }

    final vm =
        context.read<ReportEditorProvider>();

    final provider =
        context.read<RecordsProvider>();

    final existing =
        await provider.repo.loadByReportId(
      vm.doc.reportId,
    );

    if (existing != null || !mounted) {
      return;
    }

    final shouldOpen =
        await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  20,
                ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'Add this report to Records?',
                  style:
                      Theme.of(
                        sheetContext,
                      ).textTheme.titleLarge?.copyWith(
                        fontWeight:
                            FontWeight.w700,
                      ),
                ),
                const SizedBox(
                  height: 8,
                ),
                const Text(
                  'The PDF has been saved. Records are optional, '
                  'but they make this final report easier to find later '
                  'in list or table form.',
                ),
                const SizedBox(
                  height: 16,
                ),
                Row(
                  children: [
                    Expanded(
                      child:
                          OutlinedButton(
                            onPressed:
                                () =>
                                    Navigator.pop(
                                      sheetContext,
                                      false,
                                    ),
                            child:
                                const Text(
                                  'Not now',
                                ),
                          ),
                    ),
                    const SizedBox(
                      width: 12,
                    ),
                    Expanded(
                      child:
                          FilledButton.icon(
                            onPressed:
                                () =>
                                    Navigator.pop(
                                      sheetContext,
                                      true,
                                    ),
                            icon:
                                const Icon(
                                  Icons
                                      .library_add_outlined,
                                ),
                            label:
                                const Text(
                                  'Add to Records',
                                ),
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

    if (shouldOpen != true ||
        !mounted) {
      return;
    }

    final draft =
        await provider.draftForReport(
      vm.doc,
    );

    if (!mounted) return;

    final saved =
        await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder:
            (_) => RecordDetailsScreen(
              initialEntry: draft,
            ),
      ),
    );

    if (!mounted) return;

    if (saved == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content:
              Text(
                'Report added to Records.',
              ),
        ),
      );
    }
  }

  Future<void> _openLetterheadSheet() async {
    final access =
        context.read<AccessProvider>().safeState;

    if (!access.canUseLetterhead) {
      if (!mounted) return;

      final open =
          await showDialog<bool>(
        context: context,
        builder:
            (_) => AlertDialog(
              title:
                  const Text(
                    'Premium feature',
                  ),
              content:
                  const Text(
                    'Letterhead options are available in Premium Trial and Premium.',
                  ),
              actions: [
                TextButton(
                  onPressed:
                      () =>
                          Navigator.pop(
                            context,
                            false,
                          ),
                  child:
                      const Text(
                        'Later',
                      ),
                ),
                FilledButton(
                  onPressed:
                      () =>
                          Navigator.pop(
                            context,
                            true,
                          ),
                  child:
                      const Text(
                        'See Premium',
                      ),
                ),
              ],
            ),
      );

      if (open == true && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) =>
                    const UpgradeScreen(),
          ),
        );
      }

      return;
    }

    final vm =
        context.read<ReportEditorProvider>();

    final repo =
        context.read<LetterheadsRepository>();

    final templates =
        await repo.loadAll();

    if (!mounted) return;

    const addToken = '__add__';
    const manageToken = '__manage__';

    LetterheadMode? expandedMode =
        vm.doc.letterheadMode ==
                LetterheadMode.none
            ? null
            : vm.doc.letterheadMode;

    final result =
        await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder:
              (
                context,
                setModalState,
              ) {
            final doc =
                context
                    .watch<
                      ReportEditorProvider
                    >()
                    .doc;

            const childIndent =
                64.0;

            const childRightPadding =
                16.0;

            const childContentPadding =
                EdgeInsets.only(
              left: childIndent,
              right:
                  childRightPadding,
            );

            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding:
                    const EdgeInsets.fromLTRB(
                      12,
                      8,
                      12,
                      16,
                    ),
                children: [
                  const Center(
                    child: Text(
                      'Letterhead',
                      style:
                          TextStyle(
                            fontWeight:
                                FontWeight
                                    .bold,
                          ),
                    ),
                  ),

                  const SizedBox(
                    height: 8,
                  ),

                  RadioListTile<
                    LetterheadMode
                  >(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(
                          horizontal:
                              4,
                        ),
                    value:
                        LetterheadMode
                            .none,
                    groupValue:
                        doc
                            .letterheadMode,
                    title:
                        const Text(
                          'None',
                        ),
                    onChanged:
                        (value) {
                      if (value ==
                          null) {
                        return;
                      }

                      vm.setLetterheadMode(
                        value,
                      );

                      setModalState(
                        () =>
                            expandedMode =
                                null,
                      );
                    },
                  ),

                  RadioListTile<
                    LetterheadMode
                  >(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(
                          horizontal:
                              4,
                        ),
                    value:
                        LetterheadMode
                            .digital,
                    groupValue:
                        doc
                            .letterheadMode,
                    title:
                        const Text(
                          'Digital letterhead',
                        ),
                    onChanged:
                        (value) {
                      if (value ==
                          null) {
                        return;
                      }

                      vm.setLetterheadMode(
                        value,
                      );

                      setModalState(
                        () =>
                            expandedMode =
                                value,
                      );
                    },
                  ),

                  if (doc.letterheadMode ==
                          LetterheadMode
                              .digital &&
                      expandedMode ==
                          LetterheadMode
                              .digital) ...[
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(
                            childIndent,
                            4,
                            childRightPadding,
                            4,
                          ),
                      child: Text(
                        'Saved digital letterheads',
                        style:
                            Theme.of(
                              context,
                            ).textTheme.labelMedium?.copyWith(
                              fontWeight:
                                  FontWeight
                                      .w700,
                            ),
                      ),
                    ),

                    if (templates
                        .isEmpty)
                      const ListTile(
                        dense: true,
                        contentPadding:
                            childContentPadding,
                        title:
                            Text(
                              'No saved digital letterheads yet',
                            ),
                      ),

                    ...templates.map(
                      (template) =>
                          RadioListTile<
                            String
                          >(
                            dense: true,
                            contentPadding:
                                childContentPadding,
                            value:
                                template
                                    .letterheadId,
                            groupValue:
                                doc
                                    .letterheadId,
                            title:
                                Text(
                                  template
                                      .name,
                                ),
                            onChanged:
                                (value) {
                              if (value ==
                                  null) {
                                return;
                              }

                              vm.setLetterhead(
                                value,
                              );
                            },
                          ),
                    ),

                    const Divider(
                      indent:
                          childIndent,
                      endIndent:
                          childRightPadding,
                    ),

                    ListTile(
                      dense: true,
                      contentPadding:
                          childContentPadding,
                      leading:
                          const Icon(
                            Icons.add,
                          ),
                      title:
                          const Text(
                            'Add new letterhead',
                          ),
                      onTap:
                          () =>
                              Navigator.pop(
                                sheetContext,
                                addToken,
                              ),
                    ),

                    ListTile(
                      dense: true,
                      contentPadding:
                          childContentPadding,
                      leading:
                          const Icon(
                            Icons
                                .settings_outlined,
                          ),
                      title:
                          const Text(
                            'Manage letterheads',
                          ),
                      onTap:
                          () =>
                              Navigator.pop(
                                sheetContext,
                                manageToken,
                              ),
                    ),
                  ],

                  RadioListTile<
                    LetterheadMode
                  >(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(
                          horizontal:
                              4,
                        ),
                    value:
                        LetterheadMode
                            .prePrinted,
                    groupValue:
                        doc
                            .letterheadMode,
                    title:
                        const Text(
                          'Pre-printed letter paper',
                          maxLines: 2,
                          overflow:
                              TextOverflow
                                  .ellipsis,
                        ),
                    onChanged:
                        (value) {
                      if (value ==
                          null) {
                        return;
                      }

                      vm.setLetterheadMode(
                        value,
                      );

                      setModalState(
                        () =>
                            expandedMode =
                                value,
                      );
                    },
                  ),

                  if (doc.letterheadMode ==
                          LetterheadMode
                              .prePrinted &&
                      expandedMode ==
                          LetterheadMode
                              .prePrinted) ...[
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(
                            childIndent,
                            0,
                            childRightPadding,
                            8,
                          ),
                      child: Text(
                        'Uses pre-printed paper. No digital header/footer will be drawn.',
                        style:
                            Theme.of(
                              context,
                            ).textTheme.bodySmall,
                      ),
                    ),

                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(
                            childIndent,
                            6,
                            childRightPadding,
                            0,
                          ),
                      child: Text(
                        'Top safe space',
                        style:
                            Theme.of(
                              context,
                            ).textTheme.labelMedium?.copyWith(
                              fontWeight:
                                  FontWeight
                                      .w700,
                            ),
                      ),
                    ),

                    ...PrePrintedTopSpacing
                        .values
                        .map(
                          (spacing) =>
                              RadioListTile<
                                PrePrintedTopSpacing
                              >(
                                dense:
                                    true,
                                contentPadding:
                                    childContentPadding,
                                value:
                                    spacing,
                                groupValue:
                                    doc
                                        .prePrintedTopSpacing,
                                title:
                                    Text(
                                      '${spacing.label} '
                                      '(${spacing.points.toStringAsFixed(0)} pt)',
                                    ),
                                onChanged:
                                    (value) {
                                  if (value ==
                                      null) {
                                    return;
                                  }

                                  vm.setPrePrintedTopSpacing(
                                    value,
                                  );
                                },
                              ),
                        ),

                    CheckboxListTile(
                      dense: true,
                      contentPadding:
                          childContentPadding,
                      value:
                          doc
                              .reservePrePrintedFooter,
                      onChanged:
                          (value) =>
                              vm.setReservePrePrintedFooter(
                                value ??
                                    false,
                              ),
                      title:
                          const Text(
                            'Reserve bottom/footer safe space',
                            maxLines:
                                2,
                            overflow:
                                TextOverflow
                                    .ellipsis,
                          ),
                      subtitle:
                          Text(
                            'Adds 50 pt on every page.',
                            style:
                                Theme.of(
                                  context,
                                ).textTheme.bodySmall,
                          ),
                      controlAffinity:
                          ListTileControlAffinity
                              .leading,
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted) return;

    if (result == addToken) {
      final createdLetterheadId =
          await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder:
              (_) =>
                  const LetterheadEditorScreen(
                    letterheadId:
                        null,
                  ),
        ),
      );

      if (!mounted) return;

      if (createdLetterheadId != null &&
          createdLetterheadId !=
              '__deleted__') {
        _refreshLetterheadPreview();
      }

      return;
    }

    if (result == manageToken) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) =>
                  const ManageLetterheadsScreen(),
        ),
      );

      if (!mounted) return;

      // Editing a letterhead does not change its ID.
      // Force the preview to reload its saved contents.
      _refreshLetterheadPreview();

      return;
    }
  }

  void _openLayoutSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder:
          (_) => SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    16,
                  ),
              child:
                  Consumer<
                    ReportEditorProvider
                  >(
                    builder:
                        (
                          context,
                          vm,
                          _,
                        ) {
                      final layout =
                          vm
                              .doc
                              .reportLayout;

                      final indentContent =
                          vm
                              .doc
                              .indentContent;

                      final indentHierarchy =
                          vm
                              .doc
                              .indentHierarchy;

                      final showColonAfterTitlesWithContent =
                          vm
                              .doc
                              .showColonAfterTitlesWithContent;

                      final scale =
                          vm
                              .doc
                              .fontScale;

                      return SingleChildScrollView(
                        child: Column(
                          mainAxisSize:
                              MainAxisSize
                                  .min,
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .stretch,
                          children: [
                            const Text(
                              'Report layout',
                              style:
                                  TextStyle(
                                    fontSize:
                                        16,
                                    fontWeight:
                                        FontWeight
                                            .w600,
                                  ),
                            ),

                            const SizedBox(
                              height: 8,
                            ),

                            RadioListTile<
                              ReportLayout
                            >(
                              value:
                                  ReportLayout
                                      .block,
                              groupValue:
                                  layout,
                              onChanged:
                                  (v) {
                                if (v !=
                                    null) {
                                  vm.setReportLayout(
                                    v,
                                  );
                                }
                              },
                              title:
                                  const Text(
                                    'Block',
                                  ),
                              dense:
                                  true,
                              contentPadding:
                                  EdgeInsets
                                      .zero,
                            ),

                            RadioListTile<
                              ReportLayout
                            >(
                              value:
                                  ReportLayout
                                      .inline,
                              groupValue:
                                  layout,
                              onChanged:
                                  (v) {
                                if (v !=
                                    null) {
                                  vm.setReportLayout(
                                    v,
                                  );
                                }
                              },
                              title:
                                  const Text(
                                    'Inline',
                                  ),
                              dense:
                                  true,
                              contentPadding:
                                  EdgeInsets
                                      .zero,
                            ),

                            RadioListTile<
                              ReportLayout
                            >(
                              value:
                                  ReportLayout
                                      .aligned,
                              groupValue:
                                  layout,
                              onChanged:
                                  (v) {
                                if (v !=
                                    null) {
                                  vm.setReportLayout(
                                    v,
                                  );
                                }
                              },
                              title:
                                  const Text(
                                    'Aligned',
                                  ),
                              dense:
                                  true,
                              contentPadding:
                                  EdgeInsets
                                      .zero,
                            ),

                            const Divider(
                              height: 24,
                            ),

                            const Text(
                              'Text style',
                              style:
                                  TextStyle(
                                    fontWeight:
                                        FontWeight
                                            .w600,
                                  ),
                            ),

                            const SizedBox(
                              height: 6,
                            ),

                            CheckboxListTile(
                              value:
                                  showColonAfterTitlesWithContent,
                              onChanged:
                                  (v) =>
                                      vm.setShowColonAfterTitlesWithContent(
                                        v ??
                                            false,
                                      ),
                              title:
                                  const Text(
                                    'Show colons',
                                  ),
                              contentPadding:
                                  EdgeInsets
                                      .zero,
                              dense:
                                  true,
                              controlAffinity:
                                  ListTileControlAffinity
                                      .leading,
                            ),

                            CheckboxListTile(
                              value:
                                  indentHierarchy,
                              onChanged:
                                  (v) =>
                                      vm.setIndentHierarchy(
                                        v ??
                                            false,
                                      ),
                              title:
                                  const Text(
                                    'Indent hierarchy',
                                  ),
                              contentPadding:
                                  EdgeInsets
                                      .zero,
                              dense:
                                  true,
                              controlAffinity:
                                  ListTileControlAffinity
                                      .leading,
                            ),

                            CheckboxListTile(
                              value:
                                  indentContent,
                              onChanged:
                                  (v) =>
                                      vm.setIndentContent(
                                        v ??
                                            false,
                                      ),
                              title:
                                  const Text(
                                    'Indent content',
                                  ),
                              contentPadding:
                                  EdgeInsets
                                      .zero,
                              dense:
                                  true,
                              controlAffinity:
                                  ListTileControlAffinity
                                      .leading,
                            ),

                            const Divider(
                              height: 24,
                            ),

                            const Text(
                              'Global font size',
                              style:
                                  TextStyle(
                                    fontWeight:
                                        FontWeight
                                            .w600,
                                  ),
                            ),

                            const SizedBox(
                              height: 6,
                            ),

                            Slider(
                              value:
                                  scale,
                              min:
                                  0.85,
                              max:
                                  1.35,
                              divisions:
                                  10,
                              label:
                                  scale
                                      .toStringAsFixed(
                                        2,
                                      ),
                              onChanged:
                                  vm
                                      .setFontScale,
                            ),

                            const Padding(
                              padding:
                                  EdgeInsets.only(
                                    left:
                                        4,
                                  ),
                              child: Text(
                                'Applies to the current layout',
                                style:
                                    TextStyle(
                                      fontSize:
                                          12,
                                      color:
                                          Colors
                                              .black54,
                                    ),
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
        automaticallyImplyLeading:
            false,
        leading: IconButton(
          tooltip: 'Back',
          icon:
              const Icon(
                Icons.arrow_back,
              ),
          onPressed: () {
            if (Navigator.of(
              context,
            ).canPop()) {
              Navigator.of(
                context,
              ).pop();
            }
          },
        ),
        toolbarHeight: 56,
        titleSpacing: 0,
        actions: [
          IconButton(
            tooltip: 'Letterhead',
            icon:
                const Icon(
                  Icons
                      .view_headline_outlined,
                ),
            onPressed:
                _openLetterheadSheet,
          ),

          IconButton(
            tooltip: 'Layout',
            icon:
                const Icon(
                  Icons.tune,
                ),
            onPressed:
                _openLayoutSheet,
          ),

          if (kIsWeb)
            IconButton(
              tooltip:
                  'Download PDF',
              icon:
                  const Icon(
                    Icons
                        .download_outlined,
                  ),
              onPressed: () async {
                final bytes =
                    await _buildBytes();

                if (!mounted) {
                  return;
                }

                final reportsRepo =
                    context.read<
                      ReportsRepository
                    >();

                final pdfFileName =
                    reportsRepo.pdfFileNameForDoc(
                  context
                      .read<
                        ReportEditorProvider
                      >()
                      .doc,
                );

                await downloadBytes(
                  bytes:
                      bytes,
                  fileName:
                      pdfFileName,
                );

                if (!mounted) {
                  return;
                }

                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(
                  SnackBar(
                    content:
                        Text(
                          'PDF downloaded: $pdfFileName',
                        ),
                  ),
                );

                await _offerAddToRecords();
              },
            ),

          Padding(
            padding:
                const EdgeInsets.only(
                  right: 8,
                ),
            child: Tooltip(
              message:
                  'Save final PDF',
              child: Material(
                color:
                    _saving
                        ? Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(
                          0.45,
                        )
                        : Theme.of(
                          context,
                        ).colorScheme.primary,
                shape:
                    const CircleBorder(),
                clipBehavior:
                    Clip.antiAlias,
                child: InkWell(
                  customBorder:
                      const CircleBorder(),
                  onTap:
                      _saving
                          ? null
                          : _onSavePressed,
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: Center(
                      child:
                          _saving
                              ? SizedBox(
                                width:
                                    18,
                                height:
                                    18,
                                child:
                                    CircularProgressIndicator(
                                      strokeWidth:
                                          2,
                                      valueColor:
                                          AlwaysStoppedAnimation<
                                            Color
                                          >(
                                            Theme.of(
                                              context,
                                            ).colorScheme.onPrimary,
                                          ),
                                    ),
                              )
                              : Icon(
                                Icons
                                    .save_outlined,
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onPrimary,
                                size:
                                    23,
                              ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),

      body:
          Consumer<
            ReportEditorProvider
          >(
            builder:
                (
                  context,
                  vm,
                  _,
                ) {
              final reportsRepo =
                  context.read<
                    ReportsRepository
                  >();

              final pdfFileName =
                  reportsRepo.pdfFileNameForDoc(
                vm.doc,
              );

              return LayoutBuilder(
                builder:
                    (
                      context,
                      constraints,
                    ) {
                  final isDesktopWeb =
                      kIsWeb &&
                      constraints
                              .maxWidth >=
                          900;

                  final isNativeDesktop =
                      ripotIsNativeDesktop;

                  final preview =
                      ConstrainedBox(
                    constraints:
                        BoxConstraints.tightFor(
                      width:
                          constraints
                              .maxWidth,
                      height:
                          constraints
                              .maxHeight,
                    ),
                    child: PdfPreview(
                      key: ValueKey(
                        'preview-'
                        '${vm.doc.reportLayout}-'
                        '${vm.doc.indentContent}-'
                        '${vm.doc.indentHierarchy}-'
                        '${vm.doc.showColonAfterTitlesWithContent}-'
                        '${vm.doc.fontScale}-'
                        '${vm.doc.letterheadMode}-'
                        '${vm.doc.applyLetterhead}-'
                        '${vm.doc.letterheadId}-'
                        '${vm.doc.prePrintedTopSpacing}-'
                        '${vm.doc.reservePrePrintedFooter}-'
                        '${vm.doc.updatedAtIso}-'
                        '$_letterheadPreviewRevision',
                      ),
                      build:
                          (_) =>
                              _buildBytes(),
                      pdfFileName:
                          pdfFileName,
                      allowPrinting:
                          !isNativeDesktop,
                      allowSharing:
                          !isDesktopWeb &&
                          !isNativeDesktop,
                    ),
                  );

                  final header =
                      Padding(
                    padding:
                        const EdgeInsets.fromLTRB(
                          16,
                          8,
                          16,
                          12,
                        ),
                    child: Center(
                      child: Column(
                        mainAxisSize:
                            MainAxisSize
                                .min,
                        children: [
                          Text(
                            'Preview',
                            textAlign:
                                TextAlign
                                    .center,
                            style:
                                Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                          ),
                          const SizedBox(
                            height:
                                4,
                          ),
                          Text(
                            isDesktopWeb
                                ? 'On desktop web, use the download button in the preview toolbar, then share the PDF from your downloads.'
                                : 'On desktop, use the Ripot buttons below for Download and Share. Use the toolbar icons above for Letterhead and Layout.',
                            textAlign:
                                TextAlign
                                    .center,
                            style:
                                const TextStyle(
                                  fontSize:
                                      12.5,
                                  color:
                                      Colors
                                          .black54,
                                ),
                          ),
                        ],
                      ),
                    ),
                  );

                  if (!isDesktopWeb &&
                      !isNativeDesktop) {
                    return Column(
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(
                                16,
                                8,
                                16,
                                12,
                              ),
                          child: Center(
                            child:
                                Text(
                                  'Preview',
                                  textAlign:
                                      TextAlign
                                          .center,
                                  style:
                                      Theme.of(
                                        context,
                                      ).textTheme.headlineMedium,
                                ),
                          ),
                        ),
                        Expanded(
                          child:
                              preview,
                        ),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      header,

                      if (isNativeDesktop)
                        FutureBuilder<
                          Uint8List
                        >(
                          future:
                              _buildBytes(),
                          builder:
                              (
                                context,
                                snapshot,
                              ) {
                            final bytes =
                                snapshot
                                    .data;

                            return Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    12,
                                  ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .end,
                                children: [
                                  Text(
                                    'Toolbar: Letterhead • Layout',
                                    style:
                                        Theme.of(
                                          context,
                                        ).textTheme.labelMedium?.copyWith(
                                          color:
                                              Colors
                                                  .black54,
                                        ),
                                  ),
                                  const SizedBox(
                                    height:
                                        8,
                                  ),
                                  Wrap(
                                    alignment:
                                        WrapAlignment
                                            .end,
                                    spacing:
                                        8,
                                    runSpacing:
                                        8,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed:
                                            bytes ==
                                                    null
                                                ? null
                                                : () async {
                                                  try {
                                                    final file =
                                                        await ripotDownloadPdf(
                                                          bytes:
                                                              bytes,
                                                          fileName:
                                                              pdfFileName,
                                                        );

                                                    if (!context.mounted) {
                                                      return;
                                                    }

                                                    if (file != null) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content:
                                                              Text(
                                                                'PDF saved to: ${file.path}',
                                                              ),
                                                        ),
                                                      );

                                                      await _offerAddToRecords();
                                                    } else {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content:
                                                              Text(
                                                                'Download cancelled',
                                                              ),
                                                        ),
                                                      );
                                                    }
                                                  } catch (e) {
                                                    if (!context.mounted) {
                                                      return;
                                                    }

                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content:
                                                            Text(
                                                              'Download failed: $e',
                                                            ),
                                                      ),
                                                    );
                                                  }
                                                },
                                        icon:
                                            const Icon(
                                              Icons
                                                  .download_outlined,
                                            ),
                                        label:
                                            const Text(
                                              'Download PDF',
                                            ),
                                      ),

                                      FilledButton.tonalIcon(
                                        onPressed:
                                            bytes ==
                                                    null
                                                ? null
                                                : () async {
                                                  try {
                                                    await ripotSharePdf(
                                                      bytes:
                                                          bytes,
                                                      fileName:
                                                          pdfFileName,
                                                    );
                                                  } catch (e) {
                                                    if (!context.mounted) {
                                                      return;
                                                    }

                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content:
                                                            Text(
                                                              'Share failed: $e',
                                                            ),
                                                      ),
                                                    );
                                                  }
                                                },
                                        icon:
                                            const Icon(
                                              Icons
                                                  .share_outlined,
                                            ),
                                        label:
                                            const Text(
                                              'Share PDF',
                                            ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                      Expanded(
                        child: preview,
                      ),
                    ],
                  );
                },
              );
            },
          ),
    );
  }
}