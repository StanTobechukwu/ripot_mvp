import 'dart:math';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/models/letterhead_template.dart';
import '../domain/models/nodes.dart';
import '../domain/models/report_doc.dart';
import '../domain/pdf/pdf_estimates.dart';
import '../domain/pdf/pdf_layout_metrics.dart';
import '../domain/pdf/pdf_plan.dart';
import 'platforms/file_loader.dart';

class PdfRendererService {
  static const double _alignedTitleWidth = 160.0;
  static const String _emptyDots = '..........';

  String _displayValue(String text, {bool suppressPlaceholder = false}) =>
      text.trim().isEmpty ? (suppressPlaceholder ? '' : _emptyDots) : text.trim();

  pw.TextStyle _placeholderStyle(double fontSize) => pw.TextStyle(
        fontSize: fontSize,
        color: PdfColors.grey600,
      );


  Future<Uint8List> generatePdfBytes({
    required ReportDoc doc,
    required PdfPlan plan,
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

    final metrics = PdfLayoutMetrics(
      headerReserve: _letterheadHeaderReserve(letterhead),
      footerReserve: _letterheadFooterReserve(letterhead),
    );

    final pageFormat = metrics.pageFormat;
    final pageMargin = metrics.pageMargin;

    final titleText = plan.title.trim();
    final bool showTitle = titleText.isNotEmpty;

    final inlinePageOneImgs = await _loadLabeledImages(
      plan.pageOne.inlineImages,
    );
    final spillInlineImgs = await _loadLabeledImages(
      plan.finalContent.spillInlineImages,
    );
    final attachmentImgs = await _loadLabeledImages(
      plan.attachmentPages.expand((p) => p.images).toList(),
    );

    final signatureImg = await _loadSingle(doc.signature.signatureFilePath);
    final pw.MemoryImage? logo =
        (letterhead == null) ? null : await _loadLogo(letterhead);

    final pdf = pw.Document(theme: theme);

    final templates = _buildTemplates(
      doc,
      contentFontSize: contentFontSize,
      metrics: metrics,
    );

    final page1InlineImages = inlinePageOneImgs
        .take(metrics.maxPage1InlineSlots)
        .toList(growable: false);

    final useSpecialPageOne = plan.inlineEnabled && page1InlineImages.isNotEmpty;

    final continuedInline = <_PdfLoadedImage>[
      ...inlinePageOneImgs.skip(metrics.maxPage1InlineSlots),
      ...spillInlineImgs,
    ];
    final continuedInlinePageImages = continuedInline
        .take(metrics.maxSpillInlineSlots)
        .toList(growable: false);
    final overflowInlineToAttachments = continuedInline
        .skip(metrics.maxSpillInlineSlots)
        .toList(growable: false);
    final double signatureReserve = _estimateSignatureBlockHeight(
      doc,
      hasSignatureImage: signatureImg != null,
      fontScale: fontScale,
    );

    List<_PdfTemplate> remainingTemplates = templates;
    bool showSignatureOnPage1 = false;
    bool showSignatureOnContinuedPage = false;

    if (useSpecialPageOne) {
      final page1TopHeight = _estimatePage1TopStackHeight(
        doc,
        fontScale: fontScale,
        showTitle: showTitle,
        titleFontSize: reportTitleFontSize,
      );
      final availableBodyZoneHeight =
          max(80.0, metrics.usableHeight - page1TopHeight);

      var page1BodyZoneHeight = availableBodyZoneHeight;
      final page1Split = _paginateTemplates(
        templates,
        availableHeight: page1BodyZoneHeight,
        bodyWidth: metrics.bodyWidth,
        pageTextWidth: metrics.page1TextWidth,
      );
      final page1Entries = page1Split.$1;
      remainingTemplates = page1Split.$2;

      // Signature is a final-flow block. If this page is truly the final
      // content page, place it here only when it fits below the taller side
      // of the row (text or inline images). This preserves clinical order
      // without wasting a whole page unnecessarily.
      final estimatedPage1RowHeight = max(
        _entriesEstimatedHeight(page1Entries),
        _inlineColumnEstimatedHeight(
          page1InlineImages,
          metrics: metrics,
          fontScale: 1.0,
        ),
      ).clamp(0.0, availableBodyZoneHeight).toDouble();
      if (continuedInlinePageImages.isEmpty &&
          remainingTemplates.isEmpty &&
          estimatedPage1RowHeight + signatureReserve <= availableBodyZoneHeight + 8.0) {
        page1BodyZoneHeight = max(40.0, estimatedPage1RowHeight);
        showSignatureOnPage1 = true;
      }

      pdf.addPage(
        pw.Page(
          theme: theme,
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.all(pageMargin),
          build: (_) {
            final topWidgets = <pw.Widget>[];
            if (letterhead != null) {
              topWidgets.add(_letterheadHeader(letterhead, logo));
            }
            if (showTitle) {
              topWidgets.add(
                pw.Text(
                  titleText,
                  style: pw.TextStyle(
                    fontSize: reportTitleFontSize,
                    fontWeight: pw.FontWeight.bold,
                    height: 1.35,
                  ),
                ),
              );
              topWidgets.add(pw.SizedBox(height: 12));
            }
            if (doc.subjectInfoDef.enabled) {
              topWidgets.add(_subjectInfoBlock(doc, fontScale: fontScale));
              topWidgets.add(pw.SizedBox(height: 12));
            }

            final footerWidgets = <pw.Widget>[];
            if (letterhead != null) {
              footerWidgets.add(_letterheadFooter(letterhead));
            }
            if (attachmentImgs.isEmpty && showSignatureOnContinuedPage) {
              if (footerWidgets.isNotEmpty) footerWidgets.add(pw.SizedBox(height: 4));
              if (showRipotBranding) footerWidgets.add(_ripotBranding());
            }

            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                ...topWidgets,
                pw.SizedBox(
                  height: page1BodyZoneHeight,
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: _entriesBlock(
                          page1Entries,
                          contentFontSize: contentFontSize,
                        ),
                      ),
                      pw.SizedBox(width: metrics.inlineToTextGap),
                      pw.SizedBox(
                        width: metrics.inlineColumnWidth,
                        child: _inlineColumnFixed(
                          page1InlineImages,
                          fontScale: 1.0,
                          metrics: metrics,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showSignatureOnPage1) ...[
                  pw.SizedBox(height: 12),
                  _signatureBlock(doc, signatureImg, fontScale: fontScale),
                ],
                if (footerWidgets.isNotEmpty) ...[
                  pw.Spacer(),
                  ...footerWidgets,
                ],
              ],
            );
          },
        ),
      );
    }

    if (plan.inlineEnabled && continuedInlinePageImages.isNotEmpty) {
      var continuedBodyZoneHeight = metrics.usableHeight;
      final continuedSplit = _paginateTemplates(
        remainingTemplates,
        availableHeight: continuedBodyZoneHeight,
        bodyWidth: metrics.bodyWidth,
        pageTextWidth: metrics.page1TextWidth,
      );
      final continuedEntries = continuedSplit.$1;
      remainingTemplates = continuedSplit.$2;

      // Same final-flow rule for inline continuation pages.
      final estimatedContinuedRowHeight = max(
        _entriesEstimatedHeight(continuedEntries),
        _inlineColumnEstimatedHeight(
          continuedInlinePageImages,
          metrics: metrics,
          fontScale: 1.0,
        ),
      ).clamp(0.0, metrics.usableHeight).toDouble();
      if (remainingTemplates.isEmpty &&
          estimatedContinuedRowHeight + signatureReserve <= metrics.usableHeight + 8.0) {
        continuedBodyZoneHeight = max(40.0, estimatedContinuedRowHeight);
        showSignatureOnContinuedPage = true;
      }

      pdf.addPage(
        pw.Page(
          theme: theme,
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.all(pageMargin),
          build: (_) {
            final footerWidgets = <pw.Widget>[];
            if (letterhead != null) {
              footerWidgets.add(_letterheadFooter(letterhead));
            }
            if (attachmentImgs.isEmpty && showSignatureOnContinuedPage) {
              if (footerWidgets.isNotEmpty) footerWidgets.add(pw.SizedBox(height: 4));
              if (showRipotBranding) footerWidgets.add(_ripotBranding());
            }

            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.SizedBox(
                  height: continuedBodyZoneHeight,
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: _entriesBlock(
                          continuedEntries,
                          contentFontSize: contentFontSize,
                        ),
                      ),
                      pw.SizedBox(width: metrics.inlineToTextGap),
                      pw.SizedBox(
                        width: metrics.inlineColumnWidth,
                        child: _inlineColumnFixed(
                          continuedInlinePageImages,
                          fontScale: 1.0,
                          metrics: metrics,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showSignatureOnContinuedPage) ...[
                  pw.SizedBox(height: 12),
                  _signatureBlock(doc, signatureImg, fontScale: fontScale),
                ],
                if (footerWidgets.isNotEmpty) ...[
                  pw.Spacer(),
                  ...footerWidgets,
                ],
              ],
            );
          },
        ),
      );
    }

    final signatureAlreadyRendered = showSignatureOnPage1 || showSignatureOnContinuedPage;

    final bodyWidgets = <pw.Widget>[];
    if (!useSpecialPageOne) {
      if (showTitle) {
        bodyWidgets.add(
          pw.Text(
            titleText,
            style: pw.TextStyle(
              fontSize: reportTitleFontSize,
              fontWeight: pw.FontWeight.bold,
              height: 1.35,
            ),
          ),
        );
        bodyWidgets.add(pw.SizedBox(height: 12));
      }

      if (doc.subjectInfoDef.enabled) {
        bodyWidgets.add(_subjectInfoBlock(doc, fontScale: fontScale));
        bodyWidgets.add(pw.SizedBox(height: 12));
      }

      bodyWidgets.addAll(
        _buildBodyWidgets(
          doc,
          contentFontSize: contentFontSize,
        ),
      );
    } else {
      bodyWidgets.addAll(_templatesToWidgets(remainingTemplates));
    }

    if (!signatureAlreadyRendered) {
      bodyWidgets.add(pw.SizedBox(height: 12));
      bodyWidgets.add(_signatureBlock(doc, signatureImg, fontScale: fontScale));
    }

    if (bodyWidgets.isNotEmpty) {
      pdf.addPage(
        pw.MultiPage(
        theme: theme,
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.all(pageMargin),
        header: (_) => (!useSpecialPageOne && letterhead != null)
            ? _letterheadHeader(letterhead, logo)
            : pw.SizedBox(),
        footer: (context) {
          final footerParts = <pw.Widget>[];
          if (!useSpecialPageOne && letterhead != null) {
            footerParts.add(_letterheadFooter(letterhead));
          }
          final showBranding = attachmentImgs.isEmpty &&
              context.pageNumber == context.pagesCount;
          if (showBranding) {
            if (footerParts.isNotEmpty) footerParts.add(pw.SizedBox(height: 4));
            if (showRipotBranding) footerParts.add(_ripotBranding());
          }
          if (footerParts.isEmpty) return pw.SizedBox();
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            mainAxisSize: pw.MainAxisSize.min,
            children: footerParts,
          );
        },
        build: (_) => bodyWidgets,
      ),
    );
    }

    final allAttachmentImgs = <_PdfLoadedImage>[
      ...overflowInlineToAttachments,
      ...attachmentImgs,
    ];

    if (allAttachmentImgs.isNotEmpty) {
      final chunks = chunked(allAttachmentImgs, metrics.attachmentImagesPerPage);
      for (int i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        final isLastAttachmentPage = i == chunks.length - 1;
        pdf.addPage(
          pw.Page(
            theme: theme,
            pageFormat: pageFormat,
            margin: pw.EdgeInsets.all(pageMargin),
            build: (_) {
              final footerChildren = <pw.Widget>[];
              if (letterhead != null) {
                footerChildren.add(_letterheadFooter(letterhead));
              }
              if (isLastAttachmentPage) {
                if (footerChildren.isNotEmpty) footerChildren.add(pw.SizedBox(height: 4));
                if (showRipotBranding) footerChildren.add(_ripotBranding());
              }

              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  if (letterhead != null) _letterheadHeader(letterhead, logo),
                  pw.Text(
                    'Image Attachments',
                    style: pw.TextStyle(
                      fontSize: 18 * fontScale,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  _attachmentsGridFixed(chunk, metrics: metrics),
                  if (footerChildren.isNotEmpty) ...[
                    pw.Spacer(),
                    ...footerChildren,
                  ],
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
    return templates
        .map((t) => t.buildWidget(t.text))
        .toList(growable: false);
  }

  double _estimatePage1TopStackHeight(
    ReportDoc doc, {
    required double fontScale,
    required bool showTitle,
    required double titleFontSize,
  }) {
    var h = 0.0;
    if (showTitle) {
      h += (titleFontSize * 1.35) + 12;
    }
    if (doc.subjectInfoDef.enabled) {
      final def = doc.subjectInfoDef;
      final fieldCount = def.orderedFields.length;
      final rows = def.columns == 2
          ? (fieldCount / 2).ceil().clamp(1, 1000)
          : fieldCount.clamp(1, 1000);
      final headingH = def.heading.trim().isEmpty ? 0.0 : (12.4 * fontScale) + 8;
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
        _sectionWidgets(
          root,
          doc: doc,
          contentFontSize: contentFontSize,
        ),
      );
    }
    if (widgets.isEmpty) {
      widgets.add(
        pw.Text(
          _emptyDots,
          style: _placeholderStyle(contentFontSize),
        ),
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
    final sectionChildren = s.children.whereType<SectionNode>().toList(growable: false);
    final contentChildren = s.children.whereType<ContentNode>().toList(growable: false);

    final useContentIndent = doc.reportLayout == ReportLayout.block;
    final indentPx = doc.indentHierarchy ? 12.0 * s.indent : 0.0;
    final contentIndentPx = indentPx + (useContentIndent && doc.indentContent ? 12.0 : 0.0);

    final double titleFontSize = switch (s.style.level) {
      HeadingLevel.h1 => contentFontSize * 1.45,
      HeadingLevel.h2 => contentFontSize * 1.25,
      HeadingLevel.h3 => contentFontSize * 1.10,
      HeadingLevel.h4 => contentFontSize,
    };

    final titleStyle = pw.TextStyle(
      fontSize: titleFontSize,
      fontWeight: s.style.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
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
          _displayValue(trimmed, suppressPlaceholder: doc.showColonAfterTitlesWithContent),
          style: trimmed.isEmpty
              ? _placeholderStyle(contentFontSize)
              : pw.TextStyle(
                  fontSize: contentFontSize,
                  lineSpacing: 1.6,
                ),
        ),
      );
    }

    pw.Widget inlineWidget(String text, {required bool aligned, required bool showLabel}) {
      final inlineTitleStyle = pw.TextStyle(
        fontSize: contentFontSize,
        fontWeight: pw.FontWeight.normal,
      );
      final trimmed = text.trim();
      final colon = doc.showColonAfterTitlesWithContent;
      final label = aligned ? (colon ? '${s.title}:' : s.title) : '${s.title}${colon ? ':' : ''}';
      final value = _displayValue(trimmed, suppressPlaceholder: doc.showColonAfterTitlesWithContent);
      final valueStyle = trimmed.isEmpty
          ? _placeholderStyle(contentFontSize)
          : pw.TextStyle(
              fontSize: contentFontSize,
              lineSpacing: 1.6,
            );

      final titleCell = showLabel
          ? (aligned
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
              : pw.Container(
                  alignment: titleAlign,
                  child: pw.Text(
                    label,
                    textAlign: titleTextAlign,
                    style: inlineTitleStyle,
                  ),
                ))
          : (aligned ? pw.SizedBox(width: _alignedTitleWidth) : pw.SizedBox());

      final approxTitleCharsPerLine = max(8, (_alignedTitleWidth / (contentFontSize * 0.62)).floor());
      final titleLines = aligned && showLabel
          ? _estimateWrappedLines(label, charsPerLine: approxTitleCharsPerLine)
          : 1;
      final valueTopPad = aligned && showLabel && titleLines > 1
          ? (titleLines - 1) * contentFontSize * 1.15
          : 0.0;

      return pw.Padding(
        padding: pw.EdgeInsets.only(left: indentPx, bottom: 10),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            titleCell,
            if (showLabel || aligned) pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Padding(
                padding: pw.EdgeInsets.only(top: valueTopPad),
                child: pw.Text(
                  value,
                  style: valueStyle,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (sectionChildren.isNotEmpty) {
      final introNode = contentChildren.isNotEmpty ? contentChildren.first : null;
      if (doc.reportLayout == ReportLayout.block || introNode == null) {
        final introHasText = introNode != null && introNode.text.trim().isNotEmpty;
        final colonTitle = doc.reportLayout == ReportLayout.block && doc.showColonAfterTitlesWithContent ? '${s.title}:' : s.title;
        out.add(titleWidget(overrideTitle: colonTitle));
      }
      if (introNode != null && introNode.text.trim().isNotEmpty) {
        out.add(
          doc.reportLayout == ReportLayout.block
              ? blockContentWidget(introNode.text.trim())
              : inlineWidget(introNode.text.trim(), aligned: doc.reportLayout == ReportLayout.aligned, showLabel: true),
        );
      }
      for (final child in sectionChildren) {
        out.addAll(
          _sectionWidgets(child, doc: doc, contentFontSize: contentFontSize),
        );
      }
      return out;
    }

    final leafText = contentChildren.isNotEmpty ? contentChildren.first.text.trim() : '';
    if (doc.reportLayout == ReportLayout.block) {
      final colonTitle = doc.showColonAfterTitlesWithContent ? '${s.title}:' : s.title;
      out.add(titleWidget(overrideTitle: colonTitle));
      out.add(blockContentWidget(leafText));
      return out;
    }

    out.add(
      inlineWidget(
        leafText,
        aligned: doc.reportLayout == ReportLayout.aligned,
        showLabel: true,
      ),
    );
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
              child: right == null ? pw.SizedBox() : _inlineImageCell(right, metrics: metrics),
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

  pw.Widget _inlineImageCell(
    _PdfLoadedImage entry, {
    required PdfLayoutMetrics metrics,
  }) {
    return pw.SizedBox(
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

  pw.Widget _ripotBranding() {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
        'Generated by Ripot',
        style: const pw.TextStyle(
          fontSize: 8,
          color: PdfColors.grey600,
        ),
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
    if (!hasLogo) return 52.0;
    if (lh.logoPlacement == LetterheadLogoPlacement.side) return 60.0;
    return 86.0;
  }

  double _letterheadFooterReserve(LetterheadTemplate? lh) {
    if (lh == null) return 0.0;
    final hasFooter = lh.footerLeft.trim().isNotEmpty ||
        lh.footerRight.trim().isNotEmpty;
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
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          headerContent,
          pw.SizedBox(height: 4),
          pw.Divider(),
        ],
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
                child: pw.Text(
                  left,
                  style: const pw.TextStyle(fontSize: 9),
                ),
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

  pw.Widget _subjectInfoBlock(
    ReportDoc doc, {
    required double fontScale,
  }) {
    final def = doc.subjectInfoDef;
    final fields = def.orderedFields;
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
          style: pw.TextStyle(
            fontSize: base,
            color: PdfColors.grey700,
          ),
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
      final items =
          fields.map((f) => (f.title, doc.subjectInfo.valueOf(f.key))).toList();
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
                child: right == null ? pw.SizedBox() : fieldRow(right.$1, right.$2),
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
          if (def.heading.trim().isNotEmpty) ...[
            pw.Text(
              def.heading.trim(),
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
      'Dec'
    ];
    return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
  }

  double _estimateSignatureBlockHeight(
    ReportDoc doc, {
    required bool hasSignatureImage,
    required double fontScale,
  }) {
    final name = doc.signature.name.trim();
    final creds = doc.signature.credentials.trim();
    final hasNameLine = name.isNotEmpty || creds.isNotEmpty;

    final roleLine = 12.0 * fontScale * 1.25;
    final nameLine = hasNameLine ? 11.0 * fontScale * 1.25 : 0.0;
    final dateLine = 11.0 * fontScale * 1.35;
    final imageOrLine = hasSignatureImage ? 60.0 : 32.0;

    // Mirrors _signatureBlock as closely as possible, with a small safety
    // buffer. This is intentionally tighter than the old fixed 135pt reserve
    // so the signature is kept on the final content page when it truly fits.
    return 4.0 + roleLine + 6.0 + nameLine + dateLine + 10.0 + imageOrLine + 8.0;
  }

  pw.Widget _signatureBlock(
    ReportDoc doc,
    pw.MemoryImage? signature, {
    required double fontScale,
  }) {
    final role = doc.signature.roleTitle.trim().isEmpty
        ? 'Reporter'
        : doc.signature.roleTitle.trim();
    final name = doc.signature.name.trim();
    final creds = doc.signature.credentials.trim();
    final signedDate = _formatSignedDate(doc.updatedAtIso);

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            role,
            style: pw.TextStyle(
              fontSize: 12 * fontScale,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          if (name.isNotEmpty || creds.isNotEmpty)
            pw.Text(
              creds.isEmpty ? name : '$name ($creds)',
              style: pw.TextStyle(fontSize: 11 * fontScale),
            ),
          pw.Text(
            signedDate,
            style: pw.TextStyle(
              fontSize: 11 * fontScale,
              lineSpacing: 1.4,
            ),
          ),
          pw.SizedBox(height: 10),
          if (signature != null)
            pw.SizedBox(
              height: 60,
              child: pw.Image(signature, fit: pw.BoxFit.contain),
            )
          else
            pw.Container(
              height: 32,
              width: 180,
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(
                    width: 1,
                    color: PdfColors.black,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  int _estimateWrappedLines(
    String text, {
    required int charsPerLine,
  }) {
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
    final remainingText = text.substring(best).replaceFirst(RegExp(r'^\s+'), '');
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

    void walk(SectionNode s) {
      final sectionChildren =
          s.children.whereType<SectionNode>().toList(growable: false);
      final contentChildren =
          s.children.whereType<ContentNode>().toList(growable: false);

      final useContentIndent = doc.reportLayout == ReportLayout.block;
      final indentPx =
          doc.indentHierarchy ? 12.0 * s.indent : 0.0;
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
        fontWeight: s.style.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
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
        final value = _displayValue(trimmed, suppressPlaceholder: doc.showColonAfterTitlesWithContent);
        return pw.Padding(
          padding: pw.EdgeInsets.only(left: contentIndentPx, bottom: 10),
          child: pw.Text(
            value,
            style: trimmed.isEmpty
                ? _placeholderStyle(contentFontSize)
                : pw.TextStyle(
                    fontSize: contentFontSize,
                    lineSpacing: 1.6,
                  ),
          ),
        );
      }

      pw.Widget inlineWidget(String text, {required bool aligned, required bool showLabel}) {
        final inlineTitleStyle = pw.TextStyle(
          fontSize: contentFontSize,
          fontWeight: pw.FontWeight.normal,
        );

        final trimmed = text.trim();
        final colon = doc.showColonAfterTitlesWithContent;
        final label = aligned ? (colon ? '${s.title}:' : s.title) : '${s.title}${colon ? ':' : ''}';
        final value = _displayValue(trimmed, suppressPlaceholder: doc.showColonAfterTitlesWithContent);
        final valueStyle = trimmed.isEmpty
            ? _placeholderStyle(contentFontSize)
            : pw.TextStyle(
                fontSize: contentFontSize,
                lineSpacing: 1.6,
              );

        final titleCell = showLabel
            ? (aligned
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
                : pw.Container(
                    alignment: titleAlign,
                    child: pw.Text(
                      label,
                      textAlign: titleTextAlign,
                      style: inlineTitleStyle,
                    ),
                  ))
            : (aligned ? pw.SizedBox(width: _alignedTitleWidth) : pw.SizedBox());

        final approxTitleCharsPerLine = max(8, (_alignedTitleWidth / (contentFontSize * 0.62)).floor());
        final titleLines = aligned && showLabel
            ? _estimateWrappedLines(label, charsPerLine: approxTitleCharsPerLine)
            : 1;
        final valueTopPad = aligned && showLabel && titleLines > 1
            ? (titleLines - 1) * contentFontSize * 1.15
            : 0.0;

        return pw.Padding(
          padding: pw.EdgeInsets.only(left: indentPx, bottom: 10),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              titleCell,
              if (showLabel || aligned) pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Padding(
                  padding: pw.EdgeInsets.only(top: valueTopPad),
                  child: pw.Text(
                    value,
                    style: valueStyle,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      int blockCharsPerLine(double bodyWidth, double pageTextWidth) {
        return max(12, (62 * (pageTextWidth / bodyWidth)).floor());
      }

      int inlineCharsPerLine(bool aligned, bool showLabel, double bodyWidth, double pageTextWidth) {
        double contentWidth;
        if (aligned) {
          contentWidth = pageTextWidth - _alignedTitleWidth - 10;
        } else if (showLabel) {
          final approxLabelWidth = max(40.0, s.title.length * contentFontSize * 0.62 + 10);
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
          plainOf: (piece) => '${indentText(s.indent + (doc.indentContent ? 1 : 0))}$piece\n\n',
          continueWith: (remainingText) => makeBlockContentTemplate(remainingText),
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
            final multiplier =
                doc.reportLayout == ReportLayout.aligned ? 1.32 : 1.20;
            final extra =
                doc.reportLayout == ReportLayout.aligned ? 8.0 : 4.0;
            return (lines * contentFontSize * multiplier) + extra;
          },
          buildWidget: (piece) => inlineWidget(
            piece,
            aligned: doc.reportLayout == ReportLayout.aligned,
            showLabel: showLabel,
          ),
          plainOf: (piece) => showLabel
              ? '${indentText(s.indent)}${s.title}: $piece\n\n'
              : '${indentText(s.indent)}$piece\n\n',
          continueWith: (remainingText) => makeInlineTemplate(remainingText, showLabel: false),
        );
      }

      if (sectionChildren.isNotEmpty) {
        final introNode =
            contentChildren.isNotEmpty ? contentChildren.first : null;

        if (doc.reportLayout == ReportLayout.block || introNode == null) {
          out.add(
            _PdfTemplate(
              text: s.title,
              splittable: false,
              fixedHeight: blockTitleSize * 1.35 + 2,
              measureHeight: (_, __, ___) => blockTitleSize * 1.35 + 2,
              buildWidget: (_) => titleWidget(overrideTitle: (doc.reportLayout == ReportLayout.block && doc.showColonAfterTitlesWithContent) ? '${s.title}:' : s.title),
              plainOf: (_) => '${indentText(s.indent)}${s.title}\n',
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

        for (final child in sectionChildren) {
          walk(child);
        }
        return;
      }

      final leafText =
          contentChildren.isNotEmpty ? contentChildren.first.text.trim() : '';

      if (doc.reportLayout == ReportLayout.block) {
        out.add(
          _PdfTemplate(
            text: s.title,
            splittable: false,
            fixedHeight: blockTitleSize * 1.35 + 2,
            measureHeight: (_, __, ___) => blockTitleSize * 1.35 + 2,
            buildWidget: (_) => titleWidget(overrideTitle: doc.showColonAfterTitlesWithContent ? '${s.title}:' : s.title),
            plainOf: (_) => '${indentText(s.indent)}${s.title}\n',
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
              buildWidget: (_) => contentWidget(doc.showColonAfterTitlesWithContent ? '' : _emptyDots),
              plainOf: (_) => '\n',
              continueWith: null,
            ),
          );
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
            buildWidget: (_) => inlineWidget('', aligned: doc.reportLayout == ReportLayout.aligned, showLabel: true),
            plainOf: (_) => '${indentText(s.indent)}${s.title}: \n\n',
            continueWith: null,
          ),
        );
      }
    }

    for (final s in doc.roots) {
      walk(s);
    }

    return out;
  }

  double _entriesEstimatedHeight(List<_PdfEntry> entries) {
    if (entries.isEmpty) return 18.0;
    // Used only for deciding whether the final signature can share the
    // current inline page. _entriesBlock adds a 6pt top padding, while each
    // entry already carries its own measured bottom padding/line height.
    // Avoid an extra trailing buffer here; it made the fit test too
    // conservative and pushed the signature to a new page despite visible
    // available space.
    return entries.fold<double>(6.0, (sum, e) => sum + e.height);
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
    const cellHeight = 190.0;

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
          padding: const pw.EdgeInsets.symmetric(horizontal: 10),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: cell(left)),
              pw.SizedBox(width: gap),
              pw.Expanded(
                child: right == null ? pw.SizedBox() : cell(right),
              ),
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
  const _PdfLoadedImage({
    required this.image,
    required this.label,
  });

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