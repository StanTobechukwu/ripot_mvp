import 'dart:math';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/models/letterhead_template.dart';
import '../domain/models/nodes.dart';
import '../domain/models/report_doc.dart';
import '../domain/models/subject_info_def.dart';
import '../domain/pdf/pdf_estimates.dart';
import '../domain/pdf/pdf_layout_metrics.dart';
import '../domain/pdf/pdf_plan.dart';
import 'platforms/file_loader.dart';

class PdfRendererService {
  static const double _alignedTitleWidth = 160.0;
  static const double _fitSlack = 24.0;
  static const String _emptyDots = '..........';

  String _displayValue(String text, {bool suppressPlaceholder = false}) =>
      text.trim().isEmpty
      ? (suppressPlaceholder ? '' : _emptyDots)
      : text.trim();

  pw.TextStyle _placeholderStyle(double fontSize) =>
      pw.TextStyle(fontSize: fontSize, color: PdfColors.grey600);

  SectionNode? _findSectionById(List<SectionNode> roots, String id) {
    for (final section in roots) {
      if (section.id == id) return section;
      final found = _findSectionById(
        section.children.whereType<SectionNode>().toList(growable: false),
        id,
      );
      if (found != null) return found;
    }
    return null;
  }

  String _sectionFirstContentValue(SectionNode section) {
    for (final child in section.children) {
      if (child is ContentNode) {
        final text = child.text.trim();
        if (text.isNotEmpty) return text;
      } else if (child is SectionNode) {
        final nested = _sectionFirstContentValue(child);
        if (nested.isNotEmpty) return nested;
      }
    }
    return '';
  }

  bool _sectionConditionAllows(ReportDoc doc, SectionNode section) {
    if (!section.hasCondition) return true;
    final parent = _findSectionById(
      doc.roots,
      section.conditionalParentSectionId,
    );
    if (parent == null) return true;
    final parentValue = _sectionFirstContentValue(parent).trim().toLowerCase();
    final expected = section.conditionalEquals.trim().toLowerCase();
    if (expected.isEmpty) return true;
    if (parentValue == expected) return true;
    // Multi-select structured values are stored as semicolon-separated values.
    // Allow conditions to target one selected value without being affected by
    // commas that may appear inside report-ready phrases.
    return parentValue
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .contains(expected);
  }

  bool _sectionHasAnyPdfOutput(ReportDoc doc, SectionNode section) {
    if (!_sectionConditionAllows(doc, section)) return false;
    if (section.showInPdf || section.note.trim().isNotEmpty) return true;
    return section.children.whereType<SectionNode>().any(
      (child) => _sectionHasAnyPdfOutput(doc, child),
    );
  }

  Future<Uint8List> generatePdfBytes({
    required ReportDoc doc,
    required PdfPlan plan,
    PdfLayoutMetrics? layoutMetrics,
    LetterheadTemplate? letterhead,
    bool showRipotBranding = true,
  }) async {
    final double fontScale = doc.fontScale;
    final double contentFontSize = 11.5 * fontScale;
    final double reportTitleFontSize = contentFontSize;

    final theme = pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
    );

    final metrics =
        layoutMetrics ??
        PdfLayoutMetrics(
          headerReserve: _letterheadHeaderReserve(letterhead),
          footerReserve: _letterheadFooterReserve(letterhead),
        );

    final pageFormat = metrics.pageFormat;
    final pageMargin = metrics.pageMargin;
    final usesSafePageMargins = doc.letterheadMode == LetterheadMode.prePrinted;
    final pageMargins = usesSafePageMargins
        ? pw.EdgeInsets.fromLTRB(
            pageMargin,
            pageMargin + metrics.headerReserve,
            pageMargin,
            pageMargin + metrics.footerReserve,
          )
        : pw.EdgeInsets.all(pageMargin);
    final pageBodyHeight = usesSafePageMargins
        ? pageFormat.height -
              (pageMargin * 2) -
              metrics.headerReserve -
              metrics.footerReserve
        : pageFormat.height - (pageMargin * 2);

    final titleText = plan.title.trim();
    final bool showTitle = titleText.isNotEmpty;

    final inlinePageOneImgs = await _loadLabeledImages(
      plan.pageOne.inlineImages,
    );
    final spillInlineImgs = await _loadLabeledImages(
      plan.finalContent.spillInlineImages,
    );
    final plannedAttachmentImgs = await _loadLabeledImages(
      plan.attachmentPages.expand((p) => p.images).toList(),
    );

    final signatureImg = await _loadSingle(doc.signature.signatureFilePath);
    final pw.MemoryImage? logo = (letterhead == null)
        ? null
        : await _loadLogo(letterhead);

    final pdf = pw.Document(theme: theme);

    // Hybrid report-image renderer:
    // - report images remain report content throughout;
    // - first-page images use the fixed right-side vertical column when they fit;
    // - excess report images flow in fixed-size horizontal rows below report text;
    // - horizontal image rows may continue across report pages;
    // - the signature is always after all report images;
    // - only true attachments are rendered on attachment pages.
    final topWidgets = <pw.Widget>[];
    if (showTitle || doc.reportDateIso.trim().isNotEmpty) {
      topWidgets.add(
        _reportHeading(
          doc,
          titleText: titleText,
          fontSize: reportTitleFontSize,
          fontScale: fontScale,
        ),
      );
      topWidgets.add(pw.SizedBox(height: 12));
    }

    if (_hasFilledSubjectInfo(doc)) {
      topWidgets.add(_subjectInfoBlock(doc, fontScale: fontScale));
      topWidgets.add(pw.SizedBox(height: 12));
    }

    final allInlineCandidates = <_PdfLoadedImage>[
      ...inlinePageOneImgs,
      ...spillInlineImgs,
    ];

    final pageOneInlineCandidates = plan.inlineEnabled
        ? allInlineCandidates.take(metrics.maxPage1InlineSlots).toList()
        : <_PdfLoadedImage>[];

    final topStackHeight = _estimatePage1TopStackHeight(
      doc,
      fontScale: fontScale,
      showTitle: showTitle,
      titleFontSize: reportTitleFontSize,
    );
    final availableAfterTop = max(80.0, metrics.usableHeight - topStackHeight);

    final templates = _buildTemplates(
      doc,
      contentFontSize: contentFontSize,
      metrics: metrics,
    );

    final signatureHeight = _estimateSignatureBlockHeight(
      doc,
      hasSignatureImage: signatureImg != null,
      fontScale: fontScale,
    );

    final signatureFitRelief = _signatureFitRelief(
      hasLetterhead: letterhead != null,
      hasFooter: metrics.footerReserve > 0,
      hasInlineColumn: pageOneInlineCandidates.isNotEmpty,
      fontScale: fontScale,
    );

    // Stable default path for reports with no report images. True
    // attachments remain separate and are rendered only after the signature.
    if (pageOneInlineCandidates.isEmpty && spillInlineImgs.isEmpty) {
      final bodyWidgets = <pw.Widget>[
        ...topWidgets,
        ..._templatesToWidgets(templates),
        pw.SizedBox(height: 6),
        _signatureBlock(doc, signatureImg, fontScale: fontScale),
      ];

      pdf.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: pageFormat,
          margin: pageMargins,
          header: (_) => letterhead != null
              ? _letterheadHeader(letterhead, logo)
              : pw.SizedBox(),
          footer: (context) => _pageFooter(
            letterhead: letterhead,
            showBranding:
                plannedAttachmentImgs.isEmpty &&
                context.pageNumber == context.pagesCount &&
                showRipotBranding,
          ),
          build: (_) => bodyWidgets,
        ),
      );

      if (plannedAttachmentImgs.isNotEmpty) {
        final chunks = chunked(
          plannedAttachmentImgs,
          metrics.attachmentImagesPerPage,
        );
        for (int i = 0; i < chunks.length; i++) {
          final isLast = i == chunks.length - 1;
          pdf.addPage(
            pw.MultiPage(
              theme: theme,
              pageFormat: pageFormat,
              margin: pageMargins,
              header: (_) => letterhead != null
                  ? _letterheadHeader(letterhead, logo)
                  : pw.SizedBox(),
              footer: (_) => _pageFooter(
                letterhead: letterhead,
                showBranding: isLast && showRipotBranding,
              ),
              build: (_) => [
                pw.Text(
                  'Image Attachments',
                  style: pw.TextStyle(
                    fontSize: 18 * fontScale,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 12),
                _attachmentsGridFixed(chunks[i], metrics: metrics),
              ],
            ),
          );
        }
      }

      return pdf.save();
    }

    // Hybrid rendering strategy:
    // 1) Manually create only the special first-page side-by-side block:
    //    narrow report text on the left + fixed vertical images on the right.
    // 2) Everything after that block is ordinary MultiPage flow:
    //    remaining full-width text -> horizontal report-image rows -> signature.
    // The PDF engine decides natural pagination after the special first block.

    List<_PdfEntry> firstPageEntries = <_PdfEntry>[];
    List<_PdfTemplate> remainingTemplates = templates;
    List<_PdfLoadedImage> pageOneInlineImages = <_PdfLoadedImage>[];

    final wantsPageOneImageColumn = pageOneInlineCandidates.isNotEmpty;
    final leftColumnWidth = wantsPageOneImageColumn
        ? metrics.page1TextWidth
        : metrics.bodyWidth;

    // The only estimated pagination decision we keep: how much report text can
    // safely participate in the narrow first-page side-by-side block.
    final firstPageContent = _paginateTemplates(
      templates,
      availableHeight: availableAfterTop,
      bodyWidth: metrics.bodyWidth,
      pageTextWidth: leftColumnWidth,
    );

    firstPageEntries = firstPageContent.$1;
    remainingTemplates = firstPageContent.$2;

    if (wantsPageOneImageColumn) {
      pageOneInlineImages = _inlineImagesThatFitWithin(
        pageOneInlineCandidates,
        maxHeight: availableAfterTop,
        metrics: metrics,
        fontScale: fontScale,
      );
    }

    // Conservative fallback if the narrow side-by-side text block cannot be
    // safely formed.
    if (firstPageEntries.isEmpty && templates.isNotEmpty) {
      final fallback = _paginateTemplates(
        templates,
        availableHeight: availableAfterTop,
        bodyWidth: metrics.bodyWidth,
        pageTextWidth: metrics.bodyWidth,
      );
      firstPageEntries = fallback.$1;
      remainingTemplates = fallback.$2;
      pageOneInlineImages = <_PdfLoadedImage>[];
    }

    final hasPageOneImageColumn = pageOneInlineImages.isNotEmpty;
    final firstPageTextWidth = hasPageOneImageColumn
        ? metrics.page1TextWidth
        : metrics.bodyWidth;

    // Overflow from inline/report mode remains report content.
    final reportOverflowImages = <_PdfLoadedImage>[
      ...allInlineCandidates.skip(pageOneInlineImages.length),
    ];

    // Only genuine attachment-mode images belong to attachment pages.
    final attachmentImgs = <_PdfLoadedImage>[...plannedAttachmentImgs];

    final naturalFlowWidgets = <pw.Widget>[
      ...topWidgets,

      // Special float-like block: narrow text + right image column.
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: firstPageTextWidth,
            child: _entriesBlock(
              firstPageEntries,
              contentFontSize: contentFontSize,
            ),
          ),
          if (hasPageOneImageColumn) ...[
            pw.SizedBox(width: metrics.inlineToTextGap),
            pw.SizedBox(
              width: metrics.inlineColumnWidth,
              child: _inlineColumnFixed(
                pageOneInlineImages,
                fontScale: fontScale,
                metrics: metrics,
              ),
            ),
          ],
        ],
      ),

      // Once clear of the side column, remaining report text is full width.
      if (remainingTemplates.isNotEmpty) ...[
        pw.SizedBox(height: 6),
        ..._templatesToWidgets(remainingTemplates),
      ],

      // Fixed horizontal image rows now participate in ordinary MultiPage flow.
      if (reportOverflowImages.isNotEmpty) ...[
        pw.SizedBox(height: metrics.inlineSlotGap),
        ..._reportImageOverflowRows(reportOverflowImages, metrics: metrics),
      ],

      // Signature is simply next in document order. MultiPage decides whether
      // it stays on the current page or moves intact to the next one.
      pw.SizedBox(height: 6),
      _signatureBlock(doc, signatureImg, fontScale: fontScale),
    ];

    pdf.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: pageFormat,
        margin: pageMargins,
        header: (_) => letterhead != null
            ? _letterheadHeader(letterhead, logo)
            : pw.SizedBox(),
        footer: (context) => _pageFooter(
          letterhead: letterhead,
          showBranding:
              attachmentImgs.isEmpty &&
              context.pageNumber == context.pagesCount &&
              showRipotBranding,
        ),
        build: (_) => naturalFlowWidgets,
      ),
    );

    if (attachmentImgs.isNotEmpty) {
      final chunks = chunked(attachmentImgs, metrics.attachmentImagesPerPage);
      for (int i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        final isLastAttachmentPage = i == chunks.length - 1;
        pdf.addPage(
          pw.Page(
            theme: theme,
            pageFormat: pageFormat,
            margin: pageMargins,
            build: (_) {
              final footerChildren = <pw.Widget>[];
              if (letterhead != null) {
                footerChildren.add(_letterheadFooter(letterhead));
              }
              if (isLastAttachmentPage && showRipotBranding) {
                if (footerChildren.isNotEmpty)
                  footerChildren.add(pw.SizedBox(height: 4));
                footerChildren.add(_ripotBranding());
              }

              final mainContent = pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  if (letterhead != null)
                    pw.SizedBox(
                      height: metrics.headerReserve,
                      child: _letterheadHeader(letterhead, logo),
                    ),
                  pw.Text(
                    'Image Attachments',
                    style: pw.TextStyle(
                      fontSize: 18 * fontScale,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  _attachmentsGridFixed(chunk, metrics: metrics),
                ],
              );

              if (footerChildren.isEmpty) return mainContent;

              return pw.Stack(
                children: [
                  mainContent,
                  pw.Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: pw.SizedBox(
                      height:
                          metrics.footerReserve +
                          (isLastAttachmentPage && showRipotBranding
                              ? 18.0
                              : 0.0),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        mainAxisSize: pw.MainAxisSize.min,
                        children: footerChildren,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      }
    }

    return pdf.save();
  }

  List<pw.Widget> _templatesToWidgets(List<_PdfTemplate> templates) {
    return templates.map((t) => t.buildWidget(t.text)).toList(growable: false);
  }

  pw.Widget _pageFooter({
    required LetterheadTemplate? letterhead,
    required bool showBranding,
  }) {
    final parts = <pw.Widget>[];
    if (letterhead != null) {
      parts.add(_letterheadFooter(letterhead));
    }
    if (showBranding) {
      if (parts.isNotEmpty) parts.add(pw.SizedBox(height: 4));
      parts.add(_ripotBranding());
    }
    if (parts.isEmpty) return pw.SizedBox();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: parts,
    );
  }

  pw.Widget _reportHeading(
    ReportDoc doc, {
    required String titleText,
    required double fontSize,
    required double fontScale,
  }) {
    final dateText = 'Date: ${_formatSignedDate(doc.reportDateIso)}';
    final hasTitle = titleText.trim().isNotEmpty;

    if (!hasTitle) {
      return pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          dateText,
          style: pw.TextStyle(
            fontSize: 9.5 * fontScale,
            color: PdfColors.grey600,
          ),
        ),
      );
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Text(
            titleText,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: pw.FontWeight.bold,
              height: 1.35,
            ),
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Text(
          dateText,
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(
            fontSize: 9.5 * fontScale,
            color: PdfColors.grey600,
          ),
        ),
      ],
    );
  }

  double _estimatePage1TopStackHeight(
    ReportDoc doc, {
    required double fontScale,
    required bool showTitle,
    required double titleFontSize,
  }) {
    var h = 0.0;
    if (showTitle || doc.reportDateIso.trim().isNotEmpty) {
      h += (titleFontSize * 1.35) + 12;
    }
    if (_hasFilledSubjectInfo(doc)) {
      final def = doc.subjectInfoDef;
      final fieldCount = _filledSubjectInfoFields(doc).length;
      final rows = def.columns == 2
          ? (fieldCount / 2).ceil().clamp(1, 1000)
          : fieldCount.clamp(1, 1000);
      final headingH = _visibleSubjectInfoHeading(doc).isEmpty
          ? 0.0
          : (12.4 * fontScale) + 8;
      final rowH = 24.0 * fontScale;
      h += 20 + headingH + (rows * rowH) + 12;
    }
    return h;
  }

  List<pw.Widget> _buildBodyWidgets(
    ReportDoc doc, {
    required double contentFontSize,
  }) {
    final widgets = <pw.Widget>[];
    for (final root in doc.roots) {
      widgets.addAll(
        _sectionWidgets(root, doc: doc, contentFontSize: contentFontSize),
      );
    }
    if (widgets.isEmpty) {
      widgets.add(
        pw.Text(_emptyDots, style: _placeholderStyle(contentFontSize)),
      );
    }
    return widgets;
  }

  List<pw.Widget> _sectionWidgets(
    SectionNode s, {
    required ReportDoc doc,
    required double contentFontSize,
  }) {
    final out = <pw.Widget>[];
    if (!_sectionConditionAllows(doc, s)) return out;

    if (!s.showInPdf) {
      final note = s.note.trim();
      if (note.isNotEmpty) {
        final prefix = s.title.trim().isEmpty ? '' : '${s.title}: ';
        out.add(
          pw.Padding(
            padding: pw.EdgeInsets.only(
              left: doc.indentHierarchy ? 12.0 * s.indent : 0.0,
              bottom: 10,
            ),
            child: pw.RichText(
              text: pw.TextSpan(
                children: [
                  if (prefix.isNotEmpty)
                    pw.TextSpan(
                      text: prefix,
                      style: pw.TextStyle(
                        fontSize: contentFontSize,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  pw.TextSpan(
                    text: note,
                    style: pw.TextStyle(
                      fontSize: contentFontSize,
                      lineSpacing: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      for (final child in s.children.whereType<SectionNode>()) {
        out.addAll(
          _sectionWidgets(child, doc: doc, contentFontSize: contentFontSize),
        );
      }
      return out;
    }

    final sectionChildren = s.children
        .whereType<SectionNode>()
        .where((child) => _sectionHasAnyPdfOutput(doc, child))
        .toList(growable: false);
    final contentChildren = s.children.whereType<ContentNode>().toList(
      growable: false,
    );

    final useContentIndent = doc.reportLayout == ReportLayout.block;
    final indentPx = doc.indentHierarchy ? 12.0 * s.indent : 0.0;
    final contentIndentPx =
        indentPx + (useContentIndent && doc.indentContent ? 12.0 : 0.0);

    final double titleFontSize = switch (s.style.level) {
      HeadingLevel.h1 => contentFontSize * 1.45,
      HeadingLevel.h2 => contentFontSize * 1.25,
      HeadingLevel.h3 => contentFontSize * 1.10,
      HeadingLevel.h4 => contentFontSize,
    };

    final titleStyle = pw.TextStyle(
      fontSize: titleFontSize,
      fontWeight: (s.indent == 0 || s.style.bold)
          ? pw.FontWeight.bold
          : pw.FontWeight.normal,
    );

    final titleAlign = switch (s.style.align) {
      TitleAlign.left => pw.Alignment.centerLeft,
      TitleAlign.center => pw.Alignment.center,
      TitleAlign.right => pw.Alignment.centerRight,
    };

    final titleTextAlign = switch (s.style.align) {
      TitleAlign.left => pw.TextAlign.left,
      TitleAlign.center => pw.TextAlign.center,
      TitleAlign.right => pw.TextAlign.right,
    };

    pw.Widget titleWidget({String? overrideTitle}) {
      return pw.Padding(
        padding: pw.EdgeInsets.only(left: indentPx, bottom: 4),
        child: pw.Align(
          alignment: titleAlign,
          child: pw.Text(
            overrideTitle ?? s.title,
            textAlign: titleTextAlign,
            style: titleStyle,
          ),
        ),
      );
    }

    pw.Widget blockContentWidget(String text) {
      final trimmed = text.trim();
      return pw.Padding(
        padding: pw.EdgeInsets.only(left: contentIndentPx, bottom: 10),
        child: pw.Text(
          _displayValue(
            trimmed,
            suppressPlaceholder: doc.showColonAfterTitlesWithContent,
          ),
          style: trimmed.isEmpty
              ? _placeholderStyle(contentFontSize)
              : pw.TextStyle(fontSize: contentFontSize, lineSpacing: 1.6),
        ),
      );
    }

    pw.Widget noteWidget() {
      final note = s.note.trim();
      if (note.isEmpty) return pw.SizedBox();
      return pw.Padding(
        padding: pw.EdgeInsets.only(left: contentIndentPx, bottom: 10),
        child: pw.Text(
          note,
          style: pw.TextStyle(fontSize: contentFontSize, lineSpacing: 1.6),
        ),
      );
    }

    pw.Widget inlineWidget(
      String text, {
      required bool aligned,
      required bool showLabel,
    }) {
      final inlineTitleStyle = pw.TextStyle(
        fontSize: contentFontSize,
        fontWeight: (s.indent == 0 || s.style.bold)
            ? pw.FontWeight.bold
            : pw.FontWeight.normal,
      );
      final trimmed = text.trim();
      final colon = doc.showColonAfterTitlesWithContent;
      final label = aligned
          ? (colon ? '${s.title}:' : s.title)
          : '${s.title}${colon ? ':' : ''}';
      final value = _displayValue(
        trimmed,
        suppressPlaceholder: doc.showColonAfterTitlesWithContent,
      );
      final valueStyle = trimmed.isEmpty
          ? _placeholderStyle(contentFontSize)
          : pw.TextStyle(fontSize: contentFontSize, lineSpacing: 1.6);

      if (!aligned) {
        final inlinePrefix = showLabel
            ? (doc.showColonAfterTitlesWithContent
                  ? '${s.title}: '
                  : '${s.title} ')
            : '';
        return pw.Padding(
          padding: pw.EdgeInsets.only(left: indentPx, bottom: 10),
          child: pw.RichText(
            text: pw.TextSpan(
              children: [
                if (inlinePrefix.isNotEmpty)
                  pw.TextSpan(text: inlinePrefix, style: inlineTitleStyle),
                pw.TextSpan(text: value, style: valueStyle),
              ],
            ),
          ),
        );
      }

      final titleCell = showLabel
          ? pw.SizedBox(
              width: _alignedTitleWidth,
              child: pw.Align(
                alignment: titleAlign,
                child: pw.Text(
                  label,
                  textAlign: titleTextAlign,
                  style: inlineTitleStyle,
                ),
              ),
            )
          : pw.SizedBox(width: _alignedTitleWidth);

      final approxTitleCharsPerLine = max(
        8,
        (_alignedTitleWidth / (contentFontSize * 0.62)).floor(),
      );
      final titleLines = showLabel
          ? _estimateWrappedLines(label, charsPerLine: approxTitleCharsPerLine)
          : 1;
      final valueTopPad = showLabel && titleLines > 1
          ? (titleLines - 1) * contentFontSize * 1.15
          : 0.0;

      return pw.Padding(
        padding: pw.EdgeInsets.only(left: indentPx, bottom: 10),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            titleCell,
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Padding(
                padding: pw.EdgeInsets.only(top: valueTopPad),
                child: pw.Text(value, style: valueStyle),
              ),
            ),
          ],
        ),
      );
    }

    if (sectionChildren.isNotEmpty) {
      final introNode = contentChildren.isNotEmpty
          ? contentChildren.first
          : null;
      if (doc.reportLayout == ReportLayout.block || introNode == null) {
        final introHasText =
            introNode != null && introNode.text.trim().isNotEmpty;
        final colonTitle =
            doc.reportLayout == ReportLayout.block &&
                doc.showColonAfterTitlesWithContent
            ? '${s.title}:'
            : s.title;
        out.add(titleWidget(overrideTitle: colonTitle));
      }
      if (introNode != null && introNode.text.trim().isNotEmpty) {
        out.add(
          doc.reportLayout == ReportLayout.block
              ? blockContentWidget(introNode.text.trim())
              : inlineWidget(
                  introNode.text.trim(),
                  aligned: doc.reportLayout == ReportLayout.aligned,
                  showLabel: true,
                ),
        );
      }
      if (s.note.trim().isNotEmpty) {
        out.add(noteWidget());
      }
      for (final child in sectionChildren) {
        out.addAll(
          _sectionWidgets(child, doc: doc, contentFontSize: contentFontSize),
        );
      }
      return out;
    }

    final leafText = contentChildren.isNotEmpty
        ? contentChildren.first.text.trim()
        : '';
    if (doc.reportLayout == ReportLayout.block) {
      final colonTitle = doc.showColonAfterTitlesWithContent
          ? '${s.title}:'
          : s.title;
      out.add(titleWidget(overrideTitle: colonTitle));
      out.add(blockContentWidget(leafText));
      if (s.note.trim().isNotEmpty) {
        out.add(noteWidget());
      }
      return out;
    }

    out.add(
      inlineWidget(
        leafText,
        aligned: doc.reportLayout == ReportLayout.aligned,
        showLabel: true,
      ),
    );
    if (s.note.trim().isNotEmpty) {
      out.add(noteWidget());
    }
    return out;
  }

  pw.Widget _inlineImagesFlowBlock(
    List<_PdfLoadedImage> images, {
    required String heading,
    required double fontScale,
    required PdfLayoutMetrics metrics,
  }) {
    if (images.isEmpty) return pw.SizedBox();

    final rows = <pw.Widget>[
      pw.Text(
        heading,
        style: pw.TextStyle(
          fontSize: 12.0 * fontScale,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(height: 8),
    ];

    for (int i = 0; i < images.length; i += 2) {
      final left = images[i];
      final right = (i + 1 < images.length) ? images[i + 1] : null;
      rows.add(
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: _inlineImageCell(left, metrics: metrics)),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: right == null
                  ? pw.SizedBox()
                  : _inlineImageCell(right, metrics: metrics),
            ),
          ],
        ),
      );
      if (i + 2 < images.length) {
        rows.add(pw.SizedBox(height: 10));
      }
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  List<pw.Widget> _inlineImageFlowWidgets(
    List<_PdfLoadedImage> images, {
    required String heading,
    required double fontScale,
    required PdfLayoutMetrics metrics,
  }) {
    if (images.isEmpty) return const <pw.Widget>[];

    final widgets = <pw.Widget>[
      pw.Text(
        heading,
        style: pw.TextStyle(
          fontSize: 12.0 * fontScale,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(height: 8),
    ];

    for (int i = 0; i < images.length; i += 2) {
      final left = images[i];
      final right = (i + 1 < images.length) ? images[i + 1] : null;
      widgets.add(
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: _inlineImageCell(left, metrics: metrics)),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: right == null
                  ? pw.SizedBox(height: metrics.inlineSlotHeight)
                  : _inlineImageCell(right, metrics: metrics),
            ),
          ],
        ),
      );
      if (i + 2 < images.length) {
        widgets.add(pw.SizedBox(height: 10));
      }
    }

    return widgets;
  }

  List<pw.Widget> _reportImageOverflowRows(
    List<_PdfLoadedImage> images, {
    required PdfLayoutMetrics metrics,
  }) {
    if (images.isEmpty) return const <pw.Widget>[];

    const imagesPerRow = 3;
    final widgets = <pw.Widget>[];

    for (int i = 0; i < images.length; i += imagesPerRow) {
      final rowImages = images
          .skip(i)
          .take(imagesPerRow)
          .toList(growable: false);

      // Preserve three fixed positions across the full body width.
      // Slot 1 is flush left and slot 3 is flush right, matching the
      // vertical image column's right edge.
      final slots = <pw.Widget>[];
      for (int slot = 0; slot < imagesPerRow; slot++) {
        if (slot < rowImages.length) {
          slots.add(
            pw.SizedBox(
              width: metrics.inlineColumnWidth,
              height: metrics.inlineSlotHeight,
              child: _inlineImageCell(rowImages[slot], metrics: metrics),
            ),
          );
        } else {
          slots.add(
            pw.SizedBox(
              width: metrics.inlineColumnWidth,
              height: metrics.inlineSlotHeight,
            ),
          );
        }
      }

      widgets.add(
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: slots,
        ),
      );

      if (i + imagesPerRow < images.length) {
        widgets.add(pw.SizedBox(height: metrics.inlineSlotGap));
      }
    }

    return widgets;
  }

  pw.Widget _inlineImageCell(
    _PdfLoadedImage entry, {
    required PdfLayoutMetrics metrics,
  }) {
    return pw.SizedBox(
      width: metrics.inlineColumnWidth,
      height: metrics.inlineSlotHeight,
      child: pw.Stack(
        children: [
          pw.Positioned.fill(
            child: pw.ClipRRect(
              horizontalRadius: 12,
              verticalRadius: 12,
              child: pw.Image(entry.image, fit: pw.BoxFit.cover),
            ),
          ),
          if (entry.label.trim().isNotEmpty)
            pw.Positioned(
              left: 28,
              bottom: 18,
              child: pw.Text(
                entry.label.trim(),
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 9),
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _ripotBranding() {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
        'Generated by Ripot',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
    );
  }

  pw.Widget _pageWithLetterhead({
    required pw.Widget body,
    required LetterheadTemplate? letterhead,
    required pw.MemoryImage? logo,
    required double headerReserve,
    required double footerReserve,
    required double usableHeight,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (letterhead != null)
          pw.SizedBox(
            height: headerReserve,
            child: _letterheadHeader(letterhead, logo),
          ),
        pw.SizedBox(height: usableHeight, child: body),
        if (letterhead != null)
          pw.SizedBox(
            height: footerReserve,
            child: _letterheadFooter(letterhead),
          ),
      ],
    );
  }

  Future<pw.MemoryImage?> _loadLogo(LetterheadTemplate lh) async {
    final path = lh.logoFilePath;
    if (path == null || path.isEmpty) return null;
    final bytes = await readFileBytes(path);
    if (bytes == null || bytes.isEmpty) return null;
    return pw.MemoryImage(bytes);
  }

  pw.Alignment _logoAlign(LetterheadLogoAlignment a) {
    switch (a) {
      case LetterheadLogoAlignment.center:
        return pw.Alignment.center;
      case LetterheadLogoAlignment.right:
        return pw.Alignment.centerRight;
      case LetterheadLogoAlignment.left:
      default:
        return pw.Alignment.centerLeft;
    }
  }

  pw.TextAlign _textAlignFromLogoAlign(LetterheadLogoAlignment a) {
    switch (a) {
      case LetterheadLogoAlignment.center:
        return pw.TextAlign.center;
      case LetterheadLogoAlignment.right:
        return pw.TextAlign.right;
      case LetterheadLogoAlignment.left:
      default:
        return pw.TextAlign.left;
    }
  }

  double _letterheadHeaderReserve(LetterheadTemplate? lh) {
    if (lh == null) return 0.0;
    final hasLogo = (lh.logoFilePath ?? '').trim().isNotEmpty;
    if (!hasLogo) return 36.0;
    if (lh.logoPlacement == LetterheadLogoPlacement.side) return 56.0;
    return 78.0;
  }

  double _letterheadFooterReserve(LetterheadTemplate? lh) {
    if (lh == null) return 0.0;
    final hasFooter =
        lh.footerLeft.trim().isNotEmpty || lh.footerRight.trim().isNotEmpty;
    // Do not reserve footer space when the letterhead footer is empty. The
    // previous fixed 45pt reserve wasted page-1 space and made the signature
    // fit test too conservative.
    return hasFooter ? 28.0 : 0.0;
  }

  pw.Widget _letterheadHeader(LetterheadTemplate lh, pw.MemoryImage? logo) {
    final align = _logoAlign(lh.logoAlign);
    final tAlign = _textAlignFromLogoAlign(lh.logoAlign);

    pw.Widget line(String text, {double size = 10, bool bold = false}) {
      final t = text.trim();
      if (t.isEmpty) return pw.SizedBox();
      return pw.Text(
        t,
        textAlign: tAlign,
        style: pw.TextStyle(
          fontSize: size,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      );
    }

    final textBlock = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        line(lh.headerLine1, size: 14, bold: true),
        line(lh.headerLine2, size: 10),
        line(lh.headerLine3, size: 10),
      ],
    );

    pw.Widget headerContent;
    if (logo != null && lh.logoPlacement == LetterheadLogoPlacement.side) {
      final logoWidget = pw.Container(
        width: 54,
        height: 44,
        alignment: pw.Alignment.center,
        child: pw.Image(logo, fit: pw.BoxFit.contain),
      );
      headerContent = pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: lh.logoAlign == LetterheadLogoAlignment.right
            ? [
                pw.Expanded(child: textBlock),
                pw.SizedBox(width: 10),
                logoWidget,
              ]
            : [
                logoWidget,
                pw.SizedBox(width: 10),
                pw.Expanded(child: textBlock),
              ],
      );
    } else {
      headerContent = pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (logo != null)
            pw.Container(
              alignment: align,
              height: 46,
              child: pw.Image(logo, fit: pw.BoxFit.contain),
            ),
          textBlock,
        ],
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [headerContent, pw.SizedBox(height: 2), pw.Divider()],
      ),
    );
  }

  pw.Widget _letterheadFooter(LetterheadTemplate lh) {
    final left = lh.footerLeft.trim();
    final right = lh.footerRight.trim();
    if (left.isEmpty && right.isEmpty) return pw.SizedBox();

    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Column(
        children: [
          pw.Divider(),
          pw.Row(
            children: [
              pw.SizedBox(
                width: 250,
                child: pw.Text(left, style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Spacer(),
              pw.Text(
                right,
                style: const pw.TextStyle(fontSize: 9),
                textAlign: pw.TextAlign.right,
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _hasFilledSubjectInfo(ReportDoc doc) =>
      _filledSubjectInfoFields(doc).isNotEmpty;

  String _visibleSubjectInfoHeading(ReportDoc doc) {
    final heading = doc.subjectInfoDef.heading.trim();
    // "Subject Info" is the editor's default label. Do not render it as a
    // report/PDF heading unless the user changes the title to a custom value.
    return heading.toLowerCase() == 'subject info' ? '' : heading;
  }

  List<SubjectFieldDef> _filledSubjectInfoFields(ReportDoc doc) {
    if (!doc.subjectInfoDef.enabled) return const <SubjectFieldDef>[];
    return doc.subjectInfoDef.orderedFields
        .where((f) => doc.subjectInfo.valueOf(f.key).trim().isNotEmpty)
        .toList(growable: false);
  }

  pw.Widget _subjectInfoBlock(ReportDoc doc, {required double fontScale}) {
    final def = doc.subjectInfoDef;
    final heading = _visibleSubjectInfoHeading(doc);
    final fields = _filledSubjectInfoFields(doc);
    final base = 10.5 * fontScale;

    if (fields.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(12),
        ),
        child: pw.Text(
          '(No subject info fields)',
          style: pw.TextStyle(fontSize: base, color: PdfColors.grey700),
        ),
      );
    }

    pw.Widget fieldRow(String label, String value) {
      final v = value.trim().isEmpty ? '-' : value.trim();
      return pw.Padding(
        padding: pw.EdgeInsets.only(bottom: 6 * fontScale),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 120,
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: base,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey900,
                  lineSpacing: 1.5,
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                v,
                style: pw.TextStyle(fontSize: base, lineSpacing: 1.5),
              ),
            ),
          ],
        ),
      );
    }

    late final pw.Widget body;
    if (def.columns == 2) {
      final items = fields
          .map((f) => (f.title, doc.subjectInfo.valueOf(f.key)))
          .toList();
      final rows = <pw.Widget>[];

      for (int i = 0; i < items.length; i += 2) {
        final left = items[i];
        final right = (i + 1 < items.length) ? items[i + 1] : null;

        rows.add(
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: fieldRow(left.$1, left.$2)),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: right == null
                    ? pw.SizedBox()
                    : fieldRow(right.$1, right.$2),
              ),
            ],
          ),
        );
      }

      body = pw.Column(children: rows);
    } else {
      body = pw.Column(
        children: fields
            .map((f) => fieldRow(f.title, doc.subjectInfo.valueOf(f.key)))
            .toList(growable: false),
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (heading.isNotEmpty) ...[
            pw.Text(
              heading,
              style: pw.TextStyle(
                fontSize: 12.4 * fontScale,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
          ],
          body,
        ],
      ),
    );
  }

  String _formatSignedDate(String iso) {
    final dt = DateTime.tryParse(iso) ?? DateTime.now();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
  }

  double _estimateSignatureBlockHeight(
    ReportDoc doc, {
    required bool hasSignatureImage,
    required double fontScale,
  }) {
    // Compact two-column signature block:
    // Endoscopist: Dr Name        Signature: [signature]
    // Assistant: Dr Name
    // Keep this budget aligned with _signatureBlock so pagination remains stable.
    final signerRow = hasSignatureImage ? 46.0 : 28.0;
    final assistantLine = doc.signature.assistantName.trim().isEmpty
        ? 0.0
        : 8.0 + (11.0 * fontScale * 1.25);
    return 3.0 + signerRow + assistantLine;
  }

  pw.Widget _signatureBlock(
    ReportDoc doc,
    pw.MemoryImage? signature, {
    required double fontScale,
  }) {
    final role = doc.signature.roleTitle.trim();
    final name = doc.signature.name.trim();
    final creds = doc.signature.credentials.trim();
    final assistantLabel = doc.signature.assistantLabel.trim().isEmpty
        ? 'Assistant'
        : doc.signature.assistantLabel.trim();
    final assistantName = doc.signature.assistantName.trim();

    final hasRoleAndName = role.isNotEmpty && name.isNotEmpty;
    final basePrimaryLine = hasRoleAndName
        ? '$role: $name'
        : name.isNotEmpty
        ? name
        : role;
    final primaryLine = creds.isNotEmpty && basePrimaryLine.isNotEmpty
        ? '$basePrimaryLine ($creds)'
        : basePrimaryLine;

    pw.Widget signerText() {
      if (primaryLine.isEmpty) return pw.SizedBox.shrink();
      if (hasRoleAndName) {
        return pw.RichText(
          textAlign: pw.TextAlign.left,
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                text: '$role: ',
                style: pw.TextStyle(
                  fontSize: 12 * fontScale,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.TextSpan(
                text: creds.isNotEmpty ? '$name ($creds)' : name,
                style: pw.TextStyle(
                  fontSize: 12 * fontScale,
                  fontWeight: pw.FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }
      return pw.Text(
        primaryLine,
        textAlign: pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 12 * fontScale,
          fontWeight: role.isNotEmpty && name.isEmpty
              ? pw.FontWeight.bold
              : pw.FontWeight.normal,
        ),
      );
    }

    pw.Widget signatureVisual() {
      if (signature != null) {
        return pw.SizedBox(
          height: 42,
          width: 105,
          child: pw.Image(signature, fit: pw.BoxFit.contain),
        );
      }
      return pw.Container(
        height: 24,
        width: 105,
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(width: 1, color: PdfColors.black),
          ),
        ),
      );
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 3),
      child: pw.Center(
        child: pw.ConstrainedBox(
          constraints: const pw.BoxConstraints(maxWidth: 500),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Expanded(flex: 62, child: signerText()),
                  pw.SizedBox(width: 14),
                  pw.Expanded(
                    flex: 38,
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.start,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          'Signature:',
                          style: pw.TextStyle(
                            fontSize: 11 * fontScale,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        signatureVisual(),
                      ],
                    ),
                  ),
                ],
              ),
              if (assistantName.isNotEmpty) ...[
                pw.SizedBox(height: 8),
                pw.Text(
                  '$assistantLabel: $assistantName',
                  textAlign: pw.TextAlign.left,
                  style: pw.TextStyle(fontSize: 11 * fontScale),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  int _estimateWrappedLines(String text, {required int charsPerLine}) {
    if (text.trim().isEmpty) return 1;

    final lines = text.split('\n');
    var total = 0;

    for (final line in lines) {
      final clean = line.trimRight();
      if (clean.isEmpty) {
        total += 1;
        continue;
      }
      total += (clean.length / charsPerLine).ceil().clamp(1, 1000);
    }

    return total.clamp(1, 10000);
  }

  int _safeBreakIndex(String text, int target) {
    if (text.isEmpty) return 0;
    var idx = text.lastIndexOf('\n', target);
    if (idx <= 0 || idx < (target * 0.6).floor()) {
      idx = text.lastIndexOf(' ', target);
    }
    if (idx <= 0 || idx < (target * 0.6).floor()) {
      idx = target;
    }
    if (idx <= 0) idx = min(text.length, max(1, target));
    if (idx > text.length) idx = text.length;
    return idx;
  }

  (String, String) _splitTemplateTextToFit(
    _PdfTemplate template, {
    required double availableHeight,
    required double bodyWidth,
    required double pageTextWidth,
  }) {
    final text = template.text;
    if (text.trim().isEmpty) return ('', '');

    final fullHeight = template.measureHeight(text, bodyWidth, pageTextWidth);
    if (fullHeight <= availableHeight) {
      return (text, '');
    }

    if (text.contains('\n')) {
      final parts = text.split('\n');
      var consumedChars = 0;
      var current = '';

      for (int i = 0; i < parts.length; i++) {
        final line = parts[i];
        final addition = current.isEmpty ? line : '$current\n$line';
        final h = template.measureHeight(addition, bodyWidth, pageTextWidth);
        if (h <= availableHeight) {
          current = addition;
          consumedChars += line.length;
          if (i < parts.length - 1) consumedChars += 1;
        } else {
          break;
        }
      }

      if (current.trim().isNotEmpty) {
        final remaining = text
            .substring(min(consumedChars, text.length))
            .replaceFirst(RegExp(r'^\s+'), '');
        return (current.trimRight(), remaining);
      }
    }

    int low = 1;
    int high = text.length;
    int best = 0;

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final idx = _safeBreakIndex(text, mid);
      final piece = text.substring(0, idx).trimRight();
      if (piece.isEmpty) {
        low = mid + 1;
        continue;
      }
      final h = template.measureHeight(piece, bodyWidth, pageTextWidth);
      if (h <= availableHeight) {
        best = idx;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    if (best <= 0) {
      best = _safeBreakIndex(text, min(text.length, 80));
    }
    if (best <= 0) best = min(text.length, max(1, min(20, text.length)));

    final pageText = text.substring(0, best).trimRight();
    final remainingText = text
        .substring(best)
        .replaceFirst(RegExp(r'^\s+'), '');
    return (pageText, remainingText);
  }

  (List<_PdfEntry>, List<_PdfTemplate>) _paginateTemplates(
    List<_PdfTemplate> templates, {
    required double availableHeight,
    required double bodyWidth,
    required double pageTextWidth,
  }) {
    if (templates.isEmpty) return (<_PdfEntry>[], <_PdfTemplate>[]);

    final pageEntries = <_PdfEntry>[];
    final working = List<_PdfTemplate>.from(templates);
    var heightLeft = availableHeight;

    while (working.isNotEmpty) {
      final t = working.first;
      final fullHeight = t.splittable
          ? t.measureHeight(t.text, bodyWidth, pageTextWidth)
          : t.fixedHeight;

      if (!t.splittable) {
        if (pageEntries.isEmpty || fullHeight <= heightLeft) {
          pageEntries.add(
            _PdfEntry(
              plain: t.plainOf(t.text),
              widget: t.buildWidget(t.text),
              height: fullHeight,
            ),
          );
          heightLeft -= fullHeight;
          working.removeAt(0);
          continue;
        }
        break;
      }

      if (fullHeight <= heightLeft) {
        pageEntries.add(
          _PdfEntry(
            plain: t.plainOf(t.text),
            widget: t.buildWidget(t.text),
            height: fullHeight,
          ),
        );
        heightLeft -= fullHeight;
        working.removeAt(0);
        continue;
      }

      if (heightLeft <= 8 && pageEntries.isNotEmpty) {
        break;
      }

      final split = _splitTemplateTextToFit(
        t,
        availableHeight: max(heightLeft, 8),
        bodyWidth: bodyWidth,
        pageTextWidth: pageTextWidth,
      );
      var piece = split.$1;
      var rest = split.$2;

      if (piece.trim().isEmpty) {
        if (t.text.trim().isEmpty) {
          pageEntries.add(
            _PdfEntry(
              plain: t.plainOf(''),
              widget: t.buildWidget(''),
              height: t.measureHeight('', bodyWidth, pageTextWidth),
            ),
          );
          working.removeAt(0);
          break;
        }

        final forcedIdx = _safeBreakIndex(t.text, min(t.text.length, 80));
        final safeIdx = forcedIdx.clamp(1, t.text.length);
        piece = t.text.substring(0, safeIdx).trimRight();
        rest = t.text.substring(safeIdx).replaceFirst(RegExp(r'^\s+'), '');
      }

      pageEntries.add(
        _PdfEntry(
          plain: t.plainOf(piece),
          widget: t.buildWidget(piece),
          height: t.measureHeight(piece, bodyWidth, pageTextWidth),
        ),
      );
      working.removeAt(0);
      if (rest.trim().isNotEmpty && t.continueWith != null) {
        working.insert(0, t.continueWith!(rest));
      }
      break;
    }

    return (pageEntries, working);
  }

  List<_PdfTemplate> _buildTemplates(
    ReportDoc doc, {
    required double contentFontSize,
    required PdfLayoutMetrics metrics,
  }) {
    final out = <_PdfTemplate>[];

    void walk(SectionNode s, [int treeDepth = 0]) {
      if (!_sectionConditionAllows(doc, s)) return;

      // Structural nesting is the source of truth for visual hierarchy.
      // max() preserves any deliberate larger indent already stored.
      final effectiveIndent = max(s.indent, treeDepth);
      final noteText = s.note.trim();

      final sectionChildren = s.children
          .whereType<SectionNode>()
          .where((child) => _sectionHasAnyPdfOutput(doc, child))
          .toList(growable: false);
      final contentChildren = s.children.whereType<ContentNode>().toList(
        growable: false,
      );

      final useContentIndent = doc.reportLayout == ReportLayout.block;
      final indentPx = doc.indentHierarchy ? 12.0 * effectiveIndent : 0.0;
      final contentIndentPx =
          indentPx + (useContentIndent && doc.indentContent ? 12.0 : 0.0);

      final double blockTitleSize = switch (s.style.level) {
        HeadingLevel.h1 => contentFontSize * 1.45,
        HeadingLevel.h2 => contentFontSize * 1.25,
        HeadingLevel.h3 => contentFontSize * 1.10,
        HeadingLevel.h4 => contentFontSize,
      };

      final blockTitleStyle = pw.TextStyle(
        fontSize: blockTitleSize,
        fontWeight: (effectiveIndent == 0 || s.style.bold)
            ? pw.FontWeight.bold
            : pw.FontWeight.normal,
      );

      final titleAlign = switch (s.style.align) {
        TitleAlign.left => pw.Alignment.centerLeft,
        TitleAlign.center => pw.Alignment.center,
        TitleAlign.right => pw.Alignment.centerRight,
      };

      final titleTextAlign = switch (s.style.align) {
        TitleAlign.left => pw.TextAlign.left,
        TitleAlign.center => pw.TextAlign.center,
        TitleAlign.right => pw.TextAlign.right,
      };

      pw.Widget titleWidget({String? overrideTitle}) {
        return pw.Padding(
          padding: pw.EdgeInsets.only(left: indentPx, bottom: 4),
          child: pw.Align(
            alignment: titleAlign,
            child: pw.Text(
              overrideTitle ?? s.title,
              textAlign: titleTextAlign,
              style: blockTitleStyle,
            ),
          ),
        );
      }

      pw.Widget contentWidget(String text) {
        final trimmed = text.trim();
        final value = _displayValue(
          trimmed,
          suppressPlaceholder: doc.showColonAfterTitlesWithContent,
        );
        return pw.Padding(
          padding: pw.EdgeInsets.only(left: contentIndentPx, bottom: 10),
          child: pw.Text(
            value,
            style: trimmed.isEmpty
                ? _placeholderStyle(contentFontSize)
                : pw.TextStyle(fontSize: contentFontSize, lineSpacing: 1.6),
          ),
        );
      }

      pw.Widget inlineWidget(
        String text, {
        required bool aligned,
        required bool showLabel,
      }) {
        final inlineTitleStyle = pw.TextStyle(
          fontSize: contentFontSize,
          fontWeight: (effectiveIndent == 0 || s.style.bold)
              ? pw.FontWeight.bold
              : pw.FontWeight.normal,
        );

        final trimmed = text.trim();
        final colon = doc.showColonAfterTitlesWithContent;
        final label = aligned
            ? (colon ? '${s.title}:' : s.title)
            : '${s.title}${colon ? ':' : ''}';
        final value = _displayValue(
          trimmed,
          suppressPlaceholder: doc.showColonAfterTitlesWithContent,
        );
        final valueStyle = trimmed.isEmpty
            ? _placeholderStyle(contentFontSize)
            : pw.TextStyle(fontSize: contentFontSize, lineSpacing: 1.6);

        if (!aligned) {
          final inlinePrefix = showLabel
              ? (doc.showColonAfterTitlesWithContent
                    ? '${s.title}: '
                    : '${s.title} ')
              : '';
          return pw.Padding(
            padding: pw.EdgeInsets.only(left: indentPx, bottom: 10),
            child: pw.RichText(
              text: pw.TextSpan(
                children: [
                  if (inlinePrefix.isNotEmpty)
                    pw.TextSpan(text: inlinePrefix, style: inlineTitleStyle),
                  pw.TextSpan(text: value, style: valueStyle),
                ],
              ),
            ),
          );
        }

        final titleCell = showLabel
            ? pw.SizedBox(
                width: _alignedTitleWidth,
                child: pw.Align(
                  alignment: titleAlign,
                  child: pw.Text(
                    label,
                    textAlign: titleTextAlign,
                    style: inlineTitleStyle,
                  ),
                ),
              )
            : pw.SizedBox(width: _alignedTitleWidth);

        final approxTitleCharsPerLine = max(
          8,
          (_alignedTitleWidth / (contentFontSize * 0.62)).floor(),
        );
        final titleLines = showLabel
            ? _estimateWrappedLines(
                label,
                charsPerLine: approxTitleCharsPerLine,
              )
            : 1;
        final valueTopPad = showLabel && titleLines > 1
            ? (titleLines - 1) * contentFontSize * 1.15
            : 0.0;

        return pw.Padding(
          padding: pw.EdgeInsets.only(left: indentPx, bottom: 10),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              titleCell,
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Padding(
                  padding: pw.EdgeInsets.only(top: valueTopPad),
                  child: pw.Text(value, style: valueStyle),
                ),
              ),
            ],
          ),
        );
      }

      int blockCharsPerLine(double bodyWidth, double pageTextWidth) {
        return max(12, (62 * (pageTextWidth / bodyWidth)).floor());
      }

      int inlineCharsPerLine(
        bool aligned,
        bool showLabel,
        double bodyWidth,
        double pageTextWidth,
      ) {
        double contentWidth;
        if (aligned) {
          contentWidth = pageTextWidth - _alignedTitleWidth - 10;
        } else if (showLabel) {
          final approxLabelWidth = max(
            40.0,
            s.title.length * contentFontSize * 0.62 + 10,
          );
          contentWidth = pageTextWidth - approxLabelWidth - 10;
        } else {
          contentWidth = pageTextWidth;
        }
        contentWidth = max(80.0, contentWidth);
        return max(8, (72 * (contentWidth / bodyWidth)).floor());
      }

      _PdfTemplate makeBlockContentTemplate(String text) {
        return _PdfTemplate(
          text: text.trim(),
          splittable: true,
          fixedHeight: 0,
          measureHeight: (piece, bodyWidth, pageTextWidth) {
            final lines = _estimateWrappedLines(
              piece,
              charsPerLine: blockCharsPerLine(bodyWidth, pageTextWidth),
            );
            return (lines * contentFontSize * 1.32) + 8;
          },
          buildWidget: (piece) => contentWidget(piece),
          plainOf: (piece) =>
              '${indentText(effectiveIndent + (doc.indentContent ? 1 : 0))}$piece\n\n',
          continueWith: (remainingText) =>
              makeBlockContentTemplate(remainingText),
        );
      }

      _PdfTemplate makeInlineTemplate(String text, {required bool showLabel}) {
        return _PdfTemplate(
          text: text.trim(),
          splittable: true,
          fixedHeight: 0,
          measureHeight: (piece, bodyWidth, pageTextWidth) {
            final lines = _estimateWrappedLines(
              piece,
              charsPerLine: inlineCharsPerLine(
                doc.reportLayout == ReportLayout.aligned,
                showLabel,
                bodyWidth,
                pageTextWidth,
              ),
            );
            final multiplier = doc.reportLayout == ReportLayout.aligned
                ? 1.32
                : 1.20;
            final extra = doc.reportLayout == ReportLayout.aligned ? 8.0 : 4.0;
            return (lines * contentFontSize * multiplier) + extra;
          },
          buildWidget: (piece) => inlineWidget(
            piece,
            aligned: doc.reportLayout == ReportLayout.aligned,
            showLabel: showLabel,
          ),
          plainOf: (piece) => showLabel
              ? '${indentText(effectiveIndent)}${s.title}${doc.showColonAfterTitlesWithContent ? ':' : ''} $piece\n\n'
              : '${indentText(effectiveIndent)}$piece\n\n',
          continueWith: (remainingText) =>
              makeInlineTemplate(remainingText, showLabel: false),
        );
      }

      // A structured value may be hidden from the PDF while its narrative
      // note remains report content.
      if (!s.showInPdf) {
        if (noteText.isNotEmpty) {
          out.add(makeInlineTemplate(noteText, showLabel: true));
        }
        for (final child in sectionChildren) {
          walk(child, treeDepth + 1);
        }
        return;
      }

      if (sectionChildren.isNotEmpty) {
        final introNode = contentChildren.isNotEmpty
            ? contentChildren.first
            : null;

        if (doc.reportLayout == ReportLayout.block || introNode == null) {
          out.add(
            _PdfTemplate(
              text: s.title,
              splittable: false,
              fixedHeight: blockTitleSize * 1.35 + 2,
              measureHeight: (_, __, ___) => blockTitleSize * 1.35 + 2,
              buildWidget: (_) => titleWidget(
                overrideTitle:
                    (doc.reportLayout == ReportLayout.block &&
                        doc.showColonAfterTitlesWithContent)
                    ? '${s.title}:'
                    : s.title,
              ),
              plainOf: (_) => '${indentText(effectiveIndent)}${s.title}\n',
              continueWith: null,
            ),
          );
        }

        if (introNode != null) {
          final introText = introNode.text.trim();
          if (introText.isNotEmpty) {
            out.add(
              doc.reportLayout == ReportLayout.block
                  ? makeBlockContentTemplate(introText)
                  : makeInlineTemplate(introText, showLabel: true),
            );
          }
        }

        if (noteText.isNotEmpty) {
          out.add(makeBlockContentTemplate(noteText));
        }

        for (final child in sectionChildren) {
          walk(child, treeDepth + 1);
        }
        return;
      }

      final leafText = contentChildren.isNotEmpty
          ? contentChildren.first.text.trim()
          : '';

      if (doc.reportLayout == ReportLayout.block) {
        out.add(
          _PdfTemplate(
            text: s.title,
            splittable: false,
            fixedHeight: blockTitleSize * 1.35 + 2,
            measureHeight: (_, __, ___) => blockTitleSize * 1.35 + 2,
            buildWidget: (_) => titleWidget(
              overrideTitle: doc.showColonAfterTitlesWithContent
                  ? '${s.title}:'
                  : s.title,
            ),
            plainOf: (_) => '${indentText(effectiveIndent)}${s.title}\n',
            continueWith: null,
          ),
        );

        if (leafText.isNotEmpty) {
          out.add(makeBlockContentTemplate(leafText));
        } else {
          out.add(
            _PdfTemplate(
              text: '',
              splittable: false,
              fixedHeight: contentFontSize * 1.32 + 8,
              measureHeight: (_, __, ___) => contentFontSize * 1.32 + 8,
              buildWidget: (_) => contentWidget(
                doc.showColonAfterTitlesWithContent ? '' : _emptyDots,
              ),
              plainOf: (_) => '\n',
              continueWith: null,
            ),
          );
        }

        if (noteText.isNotEmpty) {
          out.add(makeBlockContentTemplate(noteText));
        }
        return;
      }

      if (leafText.isNotEmpty) {
        out.add(makeInlineTemplate(leafText, showLabel: true));
      } else {
        out.add(
          _PdfTemplate(
            text: '',
            splittable: false,
            fixedHeight: contentFontSize * 1.32 + 8,
            measureHeight: (_, __, ___) => contentFontSize * 1.32 + 8,
            buildWidget: (_) => inlineWidget(
              '',
              aligned: doc.reportLayout == ReportLayout.aligned,
              showLabel: true,
            ),
            plainOf: (_) =>
                '${indentText(effectiveIndent)}${s.title}${doc.showColonAfterTitlesWithContent ? ':' : ''} \n\n',
            continueWith: null,
          ),
        );
      }

      if (noteText.isNotEmpty) {
        out.add(makeBlockContentTemplate(noteText));
      }
    }

    for (final s in doc.roots) {
      walk(s, 0);
    }

    return out;
  }

  List<_PdfLoadedImage> _inlineImagesThatFitWithin(
    List<_PdfLoadedImage> candidates, {
    required double maxHeight,
    required PdfLayoutMetrics metrics,
    required double fontScale,
  }) {
    final kept = <_PdfLoadedImage>[];
    var usedHeight = 0.0;
    final slotHeight = metrics.inlineSlotHeight * fontScale;
    final gap = metrics.inlineSlotGap * fontScale;

    for (final image in candidates) {
      final nextHeight = usedHeight == 0.0
          ? slotHeight
          : usedHeight + gap + slotHeight;

      if (nextHeight > maxHeight + _fitSlack) {
        break;
      }

      kept.add(image);
      usedHeight = nextHeight;
    }

    return kept;
  }

  List<_PdfLoadedImage> _inlineImagesThatEndBefore(
    List<_PdfLoadedImage> candidates, {
    required double maxBottom,
    required double pageBottom,
    required PdfLayoutMetrics metrics,
    required double fontScale,
  }) {
    final kept = <_PdfLoadedImage>[];
    var usedHeight = 0.0;

    for (final image in candidates) {
      final nextHeight = usedHeight == 0.0
          ? metrics.inlineSlotHeight
          : usedHeight + metrics.inlineSlotGap + metrics.inlineSlotHeight;

      final crossesSignature = nextHeight > maxBottom + _fitSlack;
      final crossesPage = nextHeight > pageBottom + _fitSlack;
      if (crossesSignature || crossesPage) {
        break;
      }

      kept.add(image);
      usedHeight = nextHeight;
    }

    return kept;
  }

  (List<_PdfLoadedImage>, List<_PdfLoadedImage>)
  _fitInlineImagesBeforeSignature({
    required List<_PdfLoadedImage> candidates,
    required double textHeight,
    required double availableHeight,
    required double signatureReserve,
    required PdfLayoutMetrics metrics,
  }) {
    if (candidates.isEmpty) {
      return (<_PdfLoadedImage>[], <_PdfLoadedImage>[]);
    }

    // Inline images are useful, but the signature is the final report block.
    // Keep as many inline images as possible while still allowing the
    // signature to sit after the report content on the same final-content page.
    // Images that do not fit become attachments.
    for (var count = candidates.length; count >= 0; count--) {
      final kept = candidates.take(count).toList(growable: false);
      final rowHeight = max(
        textHeight,
        _inlineColumnEstimatedHeight(kept, metrics: metrics, fontScale: 1.0),
      );
      if (rowHeight + signatureReserve <= availableHeight + _fitSlack) {
        return (kept, candidates.skip(count).toList(growable: false));
      }
    }

    // If the text itself cannot leave room for the signature, inline images
    // should not compete for that already-tight final-content space. Defer
    // them to attachment pages so every selected image remains visible and
    // the signature can follow the report body.
    return (<_PdfLoadedImage>[], candidates);
  }

  (List<_PdfLoadedImage>, List<_PdfLoadedImage>) _fitInlineImagesWithinHeight({
    required List<_PdfLoadedImage> candidates,
    required double availableHeight,
    required PdfLayoutMetrics metrics,
  }) {
    if (candidates.isEmpty) {
      return (<_PdfLoadedImage>[], <_PdfLoadedImage>[]);
    }

    for (var count = candidates.length; count >= 0; count--) {
      final kept = candidates.take(count).toList(growable: false);
      final imageHeight = _inlineColumnEstimatedHeight(
        kept,
        metrics: metrics,
        fontScale: 1.0,
      );
      if (imageHeight <= availableHeight + _fitSlack) {
        return (kept, candidates.skip(count).toList(growable: false));
      }
    }

    return (<_PdfLoadedImage>[], candidates);
  }

  double _entriesEstimatedHeight(List<_PdfEntry> entries) {
    if (entries.isEmpty) return 18.0;
    // Used only for deciding whether the final signature can share the
    // current inline page. _entriesBlock adds a 6pt top padding, while each
    // entry already carries its own measured bottom padding/line height.
    // Avoid an extra trailing buffer here; it made the fit test too
    // conservative and pushed the signature to a new page despite visible
    // available space.
    return entries.fold<double>(0.0, (sum, e) => sum + e.height);
  }

  bool _signatureFitsAvailableSpace({
    required double contentHeight,
    required double signatureHeight,
    required double availableHeight,
    required double estimateRelief,
  }) {
    // Balanced terminal fit rule:
    // 1) small base safety margin;
    // 2) dynamic extra margin only when signature is near the page bottom;
    // 3) tiny estimate relief to avoid wasting obvious visible space.
    final remainingWithoutMargin =
        availableHeight - contentHeight - signatureHeight;
    const baseSafetyMargin = 6.0;
    final dynamicMargin = remainingWithoutMargin < 14.0 ? 4.0 : 0.0;
    return contentHeight + signatureHeight + baseSafetyMargin + dynamicMargin <=
        availableHeight + estimateRelief;
  }

  double _signatureFitRelief({
    required bool hasLetterhead,
    required bool hasFooter,
    required bool hasInlineColumn,
    required double fontScale,
  }) {
    // Small tolerance for estimation drift only. Keep this intentionally tiny:
    // large slack allowed the signature to sit in the unstable terminal zone
    // and caused white/blank previews.
    var relief = 3.0 * fontScale;
    if (hasLetterhead) relief += 1.5;
    if (hasFooter) relief += 1.5;
    if (hasInlineColumn) relief += 1.0;
    return relief.clamp(3.0, 8.0);
  }

  double _inlineColumnEstimatedHeight(
    List<_PdfLoadedImage> images, {
    required PdfLayoutMetrics metrics,
    required double fontScale,
  }) {
    if (images.isEmpty) return 0.0;
    final slotH = metrics.inlineSlotHeight * fontScale;
    final gap = metrics.inlineSlotGap * fontScale;
    return (images.length * slotH) + ((images.length - 1) * gap);
  }

  pw.Widget _entriesBlock(
    List<_PdfEntry> entries, {
    required double contentFontSize,
  }) {
    if (entries.isEmpty) {
      return pw.Text(
        _emptyDots,
        style: pw.TextStyle(fontSize: contentFontSize),
      );
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: entries.map((e) => e.widget).toList(growable: false),
      ),
    );
  }

  pw.Widget _inlineColumnFixed(
    List<_PdfLoadedImage> images, {
    required double fontScale,
    required PdfLayoutMetrics metrics,
  }) {
    if (images.isEmpty) return pw.SizedBox();

    final slotH = metrics.inlineSlotHeight * fontScale;
    final gap = metrics.inlineSlotGap * fontScale;

    pw.Widget slot(_PdfLoadedImage entry) {
      return pw.SizedBox(
        height: slotH,
        child: pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.ClipRRect(
                horizontalRadius: 12,
                verticalRadius: 12,
                child: pw.Image(entry.image, fit: pw.BoxFit.cover),
              ),
            ),
            if (entry.label.trim().isNotEmpty)
              pw.Positioned(
                left: 18,
                bottom: 8,
                child: pw.Text(
                  entry.label.trim(),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  style: const pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 9,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final children = <pw.Widget>[];
    for (int i = 0; i < images.length; i++) {
      children.add(slot(images[i]));
      if (i != images.length - 1) {
        children.add(pw.SizedBox(height: gap));
      }
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: children,
    );
  }

  pw.Widget _attachmentsGridFixed(
    List<_PdfLoadedImage> images, {
    required PdfLayoutMetrics metrics,
  }) {
    final slots = metrics.attachmentImagesPerPage;
    const cols = 2;
    const gap = 10.0;
    // Slightly taller and a little narrower than before so more of each
    // attachment image is visible while preserving the 2 x 4 grid.
    const cellHeight = 144.0;

    pw.Widget cell(_PdfLoadedImage entry) {
      return pw.SizedBox(
        height: cellHeight,
        child: pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Image(entry.image, fit: pw.BoxFit.cover),
            ),
            if (entry.label.trim().isNotEmpty)
              pw.Positioned(
                left: 28,
                bottom: 8,
                child: pw.Text(
                  entry.label.trim(),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  style: const pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 9,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final visible = images.take(slots).toList(growable: false);
    final rows = <pw.Widget>[];

    for (int i = 0; i < visible.length; i += cols) {
      final left = visible[i];
      final right = (i + 1 < visible.length) ? visible[i + 1] : null;

      rows.add(
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 26),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: cell(left)),
              pw.SizedBox(width: gap),
              pw.Expanded(child: right == null ? pw.SizedBox() : cell(right)),
            ],
          ),
        ),
      );

      if (i + cols < visible.length) {
        rows.add(pw.SizedBox(height: gap));
      }
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Future<List<_PdfLoadedImage>> _loadLabeledImages(
    List<ImageAttachment> attachments,
  ) async {
    final out = <_PdfLoadedImage>[];
    for (final a in attachments) {
      final img = await _loadSingle(a.filePath);
      if (img != null) out.add(_PdfLoadedImage(image: img, label: a.label));
    }
    return out;
  }

  Future<pw.MemoryImage?> _loadSingle(String? path) async {
    if (path == null || path.isEmpty) return null;
    final bytes = await readFileBytes(path);
    if (bytes == null || bytes.isEmpty) return null;
    return pw.MemoryImage(bytes);
  }
}

class _PdfLoadedImage {
  const _PdfLoadedImage({required this.image, required this.label});

  final pw.MemoryImage image;
  final String label;
}

class _PdfEntry {
  const _PdfEntry({
    required this.plain,
    required this.widget,
    required this.height,
  });

  final String plain;
  final pw.Widget widget;
  final double height;
}

class _PdfTemplate {
  _PdfTemplate({
    required this.text,
    required this.splittable,
    required this.fixedHeight,
    required this.measureHeight,
    required this.buildWidget,
    required this.plainOf,
    required this.continueWith,
  });

  final String text;
  final bool splittable;
  final double fixedHeight;
  final double Function(String text, double bodyWidth, double pageTextWidth)
  measureHeight;
  final pw.Widget Function(String text) buildWidget;
  final String Function(String text) plainOf;
  final _PdfTemplate Function(String remainingText)? continueWith;
}

String indentText(int level, {int spacesPerLevel = 2}) {
  final n = (level.clamp(0, 30)) * spacesPerLevel;
  return ' ' * n;
}
