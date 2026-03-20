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

  Future<Uint8List> generatePdfBytes({
    required ReportDoc doc,
    required PdfPlan plan,
    LetterheadTemplate? letterhead,
  }) async {
    final double fontScale = doc.fontScale;
    final double contentFontSize = 11.5 * fontScale;
    final double reportTitleFontSize = contentFontSize;

    final theme = pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
    );

    final metrics = PdfLayoutMetrics(
      headerReserve: (letterhead != null) ? 90.0 : 0.0,
      footerReserve: (letterhead != null) ? 45.0 : 0.0,
    );

    final pageFormat = metrics.pageFormat;
    final pageMargin = metrics.pageMargin;
    final headerReserve = metrics.headerReserve;
    final footerReserve = metrics.footerReserve;
    final usableHeight = metrics.usableHeight;

    final titleText = plan.title;
    final bool showTitle = titleText.trim().isNotEmpty;
    final double titleReserve = estimateTitleReserve(
      title: titleText,
      fontScale: fontScale,
    );

    final double subjectReserve = estimateSubjectInfoReserve(
      doc,
      fontScale: fontScale,
    );

    final double signatureReserve = estimateSignatureHeight(
      fontScale: fontScale,
    );

    final inlineCandidates = await _loadImages(
      plan.pageOne.inlineImages.map((e) => e.filePath).toList(),
    );

    final spillInlineCandidates = await _loadImages(
      plan.finalContent.spillInlineImages.map((e) => e.filePath).toList(),
    );

    final attachmentImgs = await _loadImages(
      plan.attachmentPages
          .expand((p) => p.images)
          .map((e) => e.filePath)
          .toList(),
    );

    final signatureImg = await _loadSingle(doc.signature.signatureFilePath);
    final pw.MemoryImage? logo =
        (letterhead == null) ? null : await _loadLogo(letterhead);

    final bool inlineEnabled = plan.inlineEnabled;

    double availableMainHeightPage1({required bool reserveSignature}) {
      const gaps = 12.0;
      final remaining = usableHeight -
          titleReserve -
          subjectReserve -
          gaps -
          (reserveSignature ? signatureReserve : 0.0);
      return max(0, remaining);
    }

    final int page1InlineSlotsFit = inlineEnabled
        ? computeInlineSlotsThatFit(
            availableHeight: availableMainHeightPage1(
              reserveSignature: false,
            ),
            fontScale: fontScale,
            metrics: metrics,
          )
        : 0;

    final inlineImgsPage1 =
        inlineCandidates.take(page1InlineSlotsFit).toList(growable: false);
    final inlineImgsNotShownOnPage1 = inlineCandidates
        .skip(page1InlineSlotsFit)
        .toList(growable: false);

    final templates = _buildTemplates(
      doc,
      contentFontSize: contentFontSize,
      metrics: metrics,
    );

    final bool hasRealPage1InlineImages =
        inlineEnabled && inlineImgsPage1.isNotEmpty;
    final double page1TextWidth =
        hasRealPage1InlineImages ? metrics.page1TextWidth : metrics.bodyWidth;

    var firstPageSplit = _paginateTemplates(
      templates,
      availableHeight: availableMainHeightPage1(reserveSignature: false),
      bodyWidth: page1TextWidth,
      pageTextWidth: page1TextWidth,
    );
    var firstPageEntries = firstPageSplit.$1;
    var remainingTemplates = firstPageSplit.$2;

    var hasRemainingText = remainingTemplates.isNotEmpty;
    var canPlaceSignatureOnPage1 = !hasRemainingText;

    if (canPlaceSignatureOnPage1) {
      final adjusted = _paginateTemplates(
        templates,
        availableHeight: availableMainHeightPage1(reserveSignature: true),
        bodyWidth: page1TextWidth,
        pageTextWidth: page1TextWidth,
      );
      firstPageEntries = adjusted.$1;
      remainingTemplates = adjusted.$2;
      hasRemainingText = remainingTemplates.isNotEmpty;
      canPlaceSignatureOnPage1 = !hasRemainingText;
    }

    final spillInlineActive =
        inlineEnabled && hasRemainingText && spillInlineCandidates.isNotEmpty;

    final spillInlineImgs = spillInlineActive
        ? [
            ...inlineImgsNotShownOnPage1,
            ...spillInlineCandidates,
          ].take(metrics.maxSpillInlineSlots).toList(growable: false)
        : <pw.MemoryImage>[];

    final spillInlineRemainder = spillInlineActive
        ? [
            ...inlineImgsNotShownOnPage1,
            ...spillInlineCandidates,
          ].skip(spillInlineImgs.length).toList(growable: false)
        : <pw.MemoryImage>[
            ...inlineImgsNotShownOnPage1,
            ...spillInlineCandidates,
          ];

    final allAttachmentImgs = <pw.MemoryImage>[
      ...attachmentImgs,
      ...spillInlineRemainder,
    ];

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        theme: theme,
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.all(pageMargin),
        build: (_) {
          final mainContent = pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: hasRealPage1InlineImages
                ? pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.SizedBox(
                        width: metrics.page1TextWidth,
                        child: _entriesBlock(
                          firstPageEntries,
                          contentFontSize: contentFontSize,
                        ),
                      ),
                      pw.SizedBox(width: metrics.inlineToTextGap),
                      pw.SizedBox(
                        width: metrics.inlineColumnWidth,
                        child: _inlineColumnFixed(
                          inlineImgsPage1,
                          fontScale: fontScale,
                          metrics: metrics,
                        ),
                      ),
                    ],
                  )
                : _entriesBlock(
                    firstPageEntries,
                    contentFontSize: contentFontSize,
                  ),
          );

          final body = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              if (showTitle) ...[
                pw.Text(
                  titleText,
                  style: pw.TextStyle(
                    fontSize: reportTitleFontSize,
                    fontWeight: pw.FontWeight.bold,
                    height: 1.35,
                  ),
                ),
                pw.SizedBox(height: 12),
              ],
              if (doc.subjectInfoDef.enabled) ...[
                _subjectInfoBlock(doc, fontScale: fontScale),
                pw.SizedBox(height: 12),
              ],
              mainContent,
              if (canPlaceSignatureOnPage1) ...[
                pw.SizedBox(height: 12),
                _signatureBlock(doc, signatureImg, fontScale: fontScale),
              ],
            ],
          );

          return _pageWithLetterhead(
            body: body,
            letterhead: letterhead,
            logo: logo,
            headerReserve: headerReserve,
            footerReserve: footerReserve,
            usableHeight: usableHeight,
          );
        },
      ),
    );

    if (allAttachmentImgs.isNotEmpty) {
      final chunks = chunked(allAttachmentImgs, metrics.attachmentImagesPerPage);

      for (final chunk in chunks) {
        pdf.addPage(
          pw.Page(
            theme: theme,
            pageFormat: pageFormat,
            margin: pw.EdgeInsets.all(pageMargin),
            build: (_) {
              final titleH = 30.0 * fontScale;
              final gridH = usableHeight - titleH - 12;

              final body = pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(
                    'Image Attachments',
                    style: pw.TextStyle(
                      fontSize: 18 * fontScale,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.SizedBox(
                    height: gridH > 60 ? gridH : 60,
                    child: _attachmentsGridFixed(chunk, metrics: metrics),
                  ),
                ],
              );

              return _pageWithLetterhead(
                body: body,
                letterhead: letterhead,
                logo: logo,
                headerReserve: headerReserve,
                footerReserve: footerReserve,
                usableHeight: usableHeight,
              );
            },
          ),
        );
      }
    }

    if (!canPlaceSignatureOnPage1) {
      final double continuationUsable = usableHeight - 12.0;

      var currentRemainingTemplates = remainingTemplates;
      var firstContinuation = true;

      while (currentRemainingTemplates.isNotEmpty) {
        final pageSpillInlineImgs =
            firstContinuation ? spillInlineImgs : <pw.MemoryImage>[];
        final bool hasRealSpillInlineImages =
            inlineEnabled && pageSpillInlineImgs.isNotEmpty;
        final double continuationTextWidth = hasRealSpillInlineImages
            ? metrics.page1TextWidth
            : metrics.bodyWidth;

        final noSigSplit = _paginateTemplates(
          currentRemainingTemplates,
          availableHeight: continuationUsable,
          bodyWidth: metrics.bodyWidth,
          pageTextWidth: continuationTextWidth,
        );

        List<_PdfEntry> pageEntries;
        bool includeSignature = false;

        if (noSigSplit.$2.isEmpty) {
          final withSigSplit = _paginateTemplates(
            currentRemainingTemplates,
            availableHeight: max(0, continuationUsable - signatureReserve - 12.0),
            bodyWidth: metrics.bodyWidth,
            pageTextWidth: continuationTextWidth,
          );

          if (withSigSplit.$2.isEmpty) {
            pageEntries = withSigSplit.$1;
            currentRemainingTemplates = <_PdfTemplate>[];
            includeSignature = true;
          } else {
            pageEntries = noSigSplit.$1;
            currentRemainingTemplates = noSigSplit.$2;
          }
        } else {
          pageEntries = noSigSplit.$1;
          currentRemainingTemplates = noSigSplit.$2;
        }

        pdf.addPage(
          pw.Page(
            theme: theme,
            pageFormat: pageFormat,
            margin: pw.EdgeInsets.all(pageMargin),
            build: (_) {
              final body = pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(12),
                    ),
                    child: hasRealSpillInlineImages
                        ? pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.SizedBox(
                                width: metrics.page1TextWidth,
                                child: _entriesBlock(
                                  pageEntries,
                                  contentFontSize: contentFontSize,
                                ),
                              ),
                              pw.SizedBox(width: metrics.inlineToTextGap),
                              pw.SizedBox(
                                width: metrics.inlineColumnWidth,
                                child: _inlineColumnFixed(
                                  pageSpillInlineImgs,
                                  fontScale: fontScale,
                                  metrics: metrics,
                                ),
                              ),
                            ],
                          )
                        : _entriesBlock(
                            pageEntries,
                            contentFontSize: contentFontSize,
                          ),
                  ),
                  if (includeSignature) ...[
                    pw.SizedBox(height: 12),
                    _signatureBlock(doc, signatureImg, fontScale: fontScale),
                  ],
                ],
              );

              return _pageWithLetterhead(
                body: body,
                letterhead: letterhead,
                logo: logo,
                headerReserve: headerReserve,
                footerReserve: footerReserve,
                usableHeight: usableHeight,
              );
            },
          ),
        );

        firstContinuation = false;
      }
    }

    return pdf.save();
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

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (logo != null)
            pw.Container(
              alignment: align,
              height: 46,
              child: pw.Image(logo, fit: pw.BoxFit.contain),
            ),
          line(lh.headerLine1, size: 14, bold: true),
          line(lh.headerLine2, size: 10),
          line(lh.headerLine3, size: 10),
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
          if (name.isNotEmpty)
            pw.Text(
              name,
              style: pw.TextStyle(fontSize: 11 * fontScale),
            ),
          if (creds.isNotEmpty)
            pw.Text(
              creds,
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
        final forcedIdx = _safeBreakIndex(t.text, min(t.text.length, 80));
        piece = t.text.substring(0, max(1, forcedIdx)).trimRight();
        rest = t.text.substring(max(1, forcedIdx)).replaceFirst(RegExp(r'^\s+'), '');
      }

      pageEntries.add(
        _PdfEntry(
          plain: t.plainOf(piece),
          widget: t.buildWidget(piece),
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

      final useBlockIndent = doc.reportLayout == ReportLayout.block;
      final indentPx =
          useBlockIndent && doc.indentHierarchy ? 12.0 * s.indent : 0.0;
      final contentIndentPx =
          indentPx + (useBlockIndent && doc.indentContent ? 12.0 : 0.0);

      final double blockTitleSize = switch (s.style.level) {
        HeadingLevel.h1 => contentFontSize * 1.45,
        HeadingLevel.h2 => contentFontSize * 1.25,
        HeadingLevel.h3 => contentFontSize * 1.10,
        HeadingLevel.h4 => contentFontSize,
      };

      final blockTitleStyle = pw.TextStyle(
        fontSize: blockTitleSize,
        fontWeight:
            s.style.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
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

      pw.Widget titleWidget() {
        return pw.Padding(
          padding: pw.EdgeInsets.only(left: indentPx, bottom: 4),
          child: pw.Align(
            alignment: titleAlign,
            child: pw.Text(
              s.title,
              textAlign: titleTextAlign,
              style: blockTitleStyle,
            ),
          ),
        );
      }

      pw.Widget contentWidget(String text) {
        return pw.Padding(
          padding: pw.EdgeInsets.only(left: contentIndentPx, bottom: 10),
          child: pw.Text(
            text,
            style: pw.TextStyle(
              fontSize: contentFontSize,
              lineSpacing: 1.6,
            ),
          ),
        );
      }

      pw.Widget inlineWidget(String text, {required bool aligned, required bool showLabel}) {
        final inlineTitleStyle = pw.TextStyle(
          fontSize: contentFontSize,
          fontWeight: pw.FontWeight.bold,
        );

        final label = aligned ? s.title : '${s.title}:';
        final value = text.trim().isEmpty ? '(no content)' : text.trim();

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

        return pw.Padding(
          padding: pw.EdgeInsets.only(left: indentPx, bottom: 10),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              titleCell,
              if (showLabel || aligned) pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Text(
                  value,
                  style: pw.TextStyle(
                    fontSize: contentFontSize,
                    lineSpacing: 1.6,
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
              buildWidget: (_) => titleWidget(),
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
            buildWidget: (_) => titleWidget(),
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
              fixedHeight: 4,
              measureHeight: (_, __, ___) => 4,
              buildWidget: (_) => pw.SizedBox(height: 6),
              plainOf: (_) => '\n',
              continueWith: null,
            ),
          );
        }
        return;
      }

      out.add(makeInlineTemplate(leafText, showLabel: true));
    }

    for (final s in doc.roots) {
      walk(s);
    }

    return out;
  }

  pw.Widget _entriesBlock(
    List<_PdfEntry> entries, {
    required double contentFontSize,
  }) {
    if (entries.isEmpty) {
      return pw.Text(
        '(no content)',
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
    List<pw.MemoryImage> images, {
    required double fontScale,
    required PdfLayoutMetrics metrics,
  }) {
    if (images.isEmpty) return pw.SizedBox();

    final slotH = metrics.inlineSlotHeight * fontScale;
    final gap = metrics.inlineSlotGap * fontScale;

    pw.Widget slot(pw.MemoryImage img) {
      return pw.Container(
        height: slotH,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(12),
        ),
        child: pw.ClipRRect(
          horizontalRadius: 12,
          verticalRadius: 12,
          child: pw.Image(img, fit: pw.BoxFit.cover),
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
    List<pw.MemoryImage> images, {
    required PdfLayoutMetrics metrics,
  }) {
    final slots = metrics.attachmentImagesPerPage;
    const cols = 2;
    const gap = 10.0;
    const cellHeight = 160.0;

    pw.Widget cell(pw.MemoryImage? img) {
      return pw.Container(
        height: cellHeight,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.6, color: PdfColors.grey400),
          borderRadius: pw.BorderRadius.circular(10),
        ),
        padding: const pw.EdgeInsets.all(4),
        child: img == null
            ? pw.SizedBox()
            : pw.ClipRRect(
                horizontalRadius: 10,
                verticalRadius: 10,
                child: pw.Image(img, fit: pw.BoxFit.cover),
              ),
      );
    }

    final visible = images.take(slots).toList(growable: false);
    final rows = <pw.Widget>[];

    for (int i = 0; i < visible.length; i += cols) {
      final left = visible[i];
      final right = (i + 1 < visible.length) ? visible[i + 1] : null;

      rows.add(
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: cell(left)),
            pw.SizedBox(width: gap),
            pw.Expanded(child: cell(right)),
          ],
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

  Future<List<pw.MemoryImage>> _loadImages(List<String> paths) async {
    final out = <pw.MemoryImage>[];
    for (final p in paths) {
      final img = await _loadSingle(p);
      if (img != null) out.add(img);
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

class _PdfEntry {
  const _PdfEntry({
    required this.plain,
    required this.widget,
  });

  final String plain;
  final pw.Widget widget;
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