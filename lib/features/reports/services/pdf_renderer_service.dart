import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/models/letterhead_template.dart';
import '../domain/models/nodes.dart';
import '../domain/models/report_doc.dart';
import '../domain/pdf/pdf_plan.dart';
import 'platforms/file_loader.dart';

class PdfRendererService {
  Future<Uint8List> generatePdfBytes({
    required ReportDoc doc,
    required PdfPlan plan,
    LetterheadTemplate? letterhead,
  }) async {
    final theme = pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
    );

    // ---------- Text ----------
    final entries = _buildEntries(doc);
    final plain = entries.map((e) => e.plain).join();

    final (firstPagePlain, remainingPlain) = _splitForFirstPage(
      plain,
      inlineEnabled: doc.placementChoice == ImagePlacementChoice.inlinePage1,
    );

    final splitIndex = firstPagePlain.length;
    final (firstPageEntries, remainingEntries) = _splitEntries(entries, splitIndex);

    // ---------- Images ----------
    final inlineImgs = await _loadImages(
      plan.page1InlineImages.map((e) => e.filePath).toList(),
    );

    final attachmentImgs = await _loadImages(
      plan.attachmentPages.expand((p) => p.images).map((e) => e.filePath).toList(),
    );

    // ---------- Signature ----------
    final signatureImg = await _loadSingle(doc.signature.signatureFilePath);

    // ---------- Letterhead logo ----------
    final pw.MemoryImage? logo = (letterhead == null) ? null : await _loadLogo(letterhead);

    // ---------- Title ----------
    final subjectName = doc.subjectInfo.valueOf('subjectName').trim();
    final titleText = doc.reportTitle.trim().isNotEmpty
        ? doc.reportTitle.trim()
        : (subjectName.isEmpty ? 'Medical Report' : '$subjectName Report');

    // ---------- Page rules ----------
    final hasAttachments = attachmentImgs.isNotEmpty;
    final hasRemainingText = remainingPlain.trim().isNotEmpty;

    // Signature only allowed on page 1 if nothing else follows.
    final canPlaceSignatureOnPage1 = !hasAttachments && !hasRemainingText;

    // A4
    const pageFormat = PdfPageFormat.a4;
    const pageMargin = 28.0;

    final headerReserve = (letterhead != null) ? 90.0 : 0.0;
    final footerReserve = (letterhead != null) ? 45.0 : 0.0;

    final usableHeight =
        pageFormat.height - (pageMargin * 2) - headerReserve - footerReserve;

    final pdf = pw.Document();

    // ================= PAGE 1 =================
    pdf.addPage(
      pw.Page(
        theme: theme,
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(pageMargin),
        build: (_) {
          final mainContent = pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: doc.placementChoice == ImagePlacementChoice.inlinePage1
                ? pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: pageFormat.width - (pageMargin * 2) - 160 - 12,
                        child: _entriesBlock(firstPageEntries),
                      ),
                      pw.SizedBox(width: 12),
                      pw.SizedBox(
                        width: 160,
                        child: _inlineColumnFixed(inlineImgs, totalHeight: 420),
                      ),
                    ],
                  )
                : _entriesBlock(firstPageEntries),
          );

          final titleHeight = 34.0;
          final subjectBlockHeight = (doc.subjectInfoDef.enabled) ? 90.0 : 0.0;
          final signatureHeight = canPlaceSignatureOnPage1 ? 130.0 : 0.0;

          final mainHeight =
              usableHeight - titleHeight - subjectBlockHeight - signatureHeight - 12;

          final body = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(
                titleText,
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 12),
              if (doc.subjectInfoDef.enabled) ...[
                _subjectInfoBlock(doc),
                pw.SizedBox(height: 12),
              ],
              pw.SizedBox(
                height: mainHeight > 60 ? mainHeight : 60,
                child: mainContent,
              ),
              if (canPlaceSignatureOnPage1) ...[
                pw.SizedBox(height: 12),
                _signatureBlock(doc, signatureImg),
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

    // ================= ATTACHMENT PAGES =================
    if (attachmentImgs.isNotEmpty) {
      final chunks = _chunk(attachmentImgs, 8);

      for (final chunk in chunks) {
        pdf.addPage(
          pw.Page(
            theme: theme,
            pageFormat: pageFormat,
            margin: const pw.EdgeInsets.all(pageMargin),
            build: (_) {
              final titleH = 30.0;
              final gridH = usableHeight - titleH - 12;

              final body = pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(
                    'Image Attachments',
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 12),
                  pw.SizedBox(
                    height: gridH > 60 ? gridH : 60,
                    child: _attachmentsGridFixed(chunk),
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

    // ================= FINAL PAGE =================
    if (!canPlaceSignatureOnPage1) {
      pdf.addPage(
        pw.Page(
          theme: theme,
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(pageMargin),
          build: (_) {
            final sigH = 135.0;
            final textH = usableHeight - sigH - 12;

            final body = pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                if (hasRemainingText)
                  pw.SizedBox(
                    height: textH > 60 ? textH : 60,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey300),
                        borderRadius: pw.BorderRadius.circular(12),
                      ),
                      child: _entriesBlock(remainingEntries),
                    ),
                  )
                else
                  pw.SizedBox(height: textH > 0 ? textH : 0),
                pw.SizedBox(height: 12),
                _signatureBlock(doc, signatureImg),
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
          pw.SizedBox(height: headerReserve, child: _letterheadHeader(letterhead, logo)),
        pw.SizedBox(height: usableHeight, child: body),
        if (letterhead != null)
          pw.SizedBox(height: footerReserve, child: _letterheadFooter(letterhead)),
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
              height: 40,
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
              pw.Container(
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

  pw.Widget _subjectInfoBlock(ReportDoc doc) {
    final def = doc.subjectInfoDef;
    final fields = def.orderedFields;

    if (fields.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(12),
        ),
        child: pw.Text(
          '(No subject info fields)',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      );
    }

    pw.Widget fieldRow(String label, String value) {
      final v = value.trim().isEmpty ? '-' : value.trim();
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 120,
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey800,
                ),
              ),
            ),
            pw.Container(
              width: 260,
              child: pw.Text(v, style: const pw.TextStyle(fontSize: 10)),
            ),
          ],
        ),
      );
    }

    pw.Widget body;
    if (def.columns == 2) {
      final items = fields.map((f) => (f.title, doc.subjectInfo.valueOf(f.key))).toList();
      final rows = <pw.Widget>[];
      for (int i = 0; i < items.length; i += 2) {
        final left = items[i];
        final right = (i + 1 < items.length) ? items[i + 1] : null;
        rows.add(
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(width: 250, child: fieldRow(left.$1, left.$2)),
              pw.SizedBox(width: 12),
              pw.Container(
                width: 250,
                child: right == null ? pw.SizedBox() : fieldRow(right.$1, right.$2),
              ),
            ],
          ),
        );
      }
      body = pw.Column(children: rows);
    } else {
      body = pw.Column(
        children: fields.map((f) => fieldRow(f.title, doc.subjectInfo.valueOf(f.key))).toList(),
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
          pw.Text(
            'Subject Info',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          body,
        ],
      ),
    );
  }

  pw.Widget _signatureBlock(ReportDoc doc, pw.MemoryImage? signature) {
    final role =
        doc.signature.roleTitle.trim().isEmpty ? 'Reporter' : doc.signature.roleTitle.trim();
    final name = doc.signature.name.trim();
    final creds = doc.signature.credentials.trim();

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(14),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(role, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (name.isNotEmpty) pw.Text(name),
          if (creds.isNotEmpty) pw.Text(creds),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'Signature:',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(width: 8),
              pw.Container(
                height: 60,
                width: 340,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                alignment: pw.Alignment.centerLeft,
                padding: const pw.EdgeInsets.symmetric(horizontal: 8),
                child: signature == null
                    ? pw.Text(
                        '(not provided)',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      )
                    : pw.Image(signature, fit: pw.BoxFit.contain),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _textBlock(String text) => pw.Text(
        text.trim().isEmpty ? '(no content)' : text.trim(),
        style: const pw.TextStyle(fontSize: 11, lineSpacing: 2),
      );

  List<_PdfEntry> _buildEntries(ReportDoc doc) {
    final out = <_PdfEntry>[];

    void walk(SectionNode s) {
      final sectionChildren = s.children.whereType<SectionNode>().toList(growable: false);
      final contentChildren = s.children.whereType<ContentNode>().toList(growable: false);

      final indentPx = 12.0 * s.indent;
      final contentIndentPx = indentPx + (doc.indentContent ? 12.0 : 0.0);

      final double titleSize = switch (s.style.level) {
        HeadingLevel.h1 => 16,
        HeadingLevel.h2 => 14,
        HeadingLevel.h3 => 12,
        HeadingLevel.h4 => 11,
      };

      final titleStyle = pw.TextStyle(
        fontSize: titleSize,
        fontWeight: s.style.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      );

      final titleAlign = switch (s.style.align) {
        TitleAlign.left => pw.Alignment.centerLeft,
        TitleAlign.center => pw.Alignment.center,
        TitleAlign.right => pw.Alignment.centerRight,
      };

      pw.Widget titleWidget() {
        return pw.Padding(
          padding: pw.EdgeInsets.only(left: indentPx, bottom: 2),
          child: pw.Align(
            alignment: titleAlign,
            child: pw.Text(s.title, style: titleStyle),
          ),
        );
      }

      pw.Widget contentWidget(String text) {
        return pw.Padding(
          padding: pw.EdgeInsets.only(left: contentIndentPx, bottom: 6),
          child: pw.Text(text, style: const pw.TextStyle(fontSize: 11)),
        );
      }

      pw.Widget inlineWidget(String text, {required bool aligned}) {
        final titleCell = pw.Container(
          width: aligned ? 160 : null,
          child: pw.Align(
            alignment: titleAlign,
            child: pw.Text(aligned ? s.title : '${s.title}:', style: titleStyle),
          ),
        );

        return pw.Padding(
          padding: pw.EdgeInsets.only(left: indentPx, bottom: 6),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              titleCell,
              pw.SizedBox(width: 10),
              pw.Expanded(child: pw.Text(text, style: const pw.TextStyle(fontSize: 11))),
            ],
          ),
        );
      }

      // Container section
      if (sectionChildren.isNotEmpty) {
        final introNode = contentChildren.isNotEmpty ? contentChildren.first : null;

        if (doc.reportLayout == ReportLayout.block || introNode == null) {
          out.add(_PdfEntry(
            plain: '${indentText(s.indent)}${s.title}\n',
            widget: titleWidget(),
          ));
        }

        if (introNode != null) {
          final introText = introNode.text.trim();
          if (introText.isNotEmpty) {
            if (doc.reportLayout == ReportLayout.block) {
              out.add(_PdfEntry(
                plain:
                    '${indentText(s.indent + (doc.indentContent ? 1 : 0))}$introText\n\n',
                widget: contentWidget(introText),
              ));
            } else {
              out.add(_PdfEntry(
                plain: '${indentText(s.indent)}${s.title}: $introText\n\n',
                widget: inlineWidget(
                  introText,
                  aligned: doc.reportLayout == ReportLayout.aligned,
                ),
              ));
            }
          }
        }

        for (final child in sectionChildren) {
          walk(child);
        }
        return;
      }

      // Leaf section
      final leafText = contentChildren.isNotEmpty ? contentChildren.first.text.trim() : '';

      if (doc.reportLayout == ReportLayout.block) {
        out.add(_PdfEntry(
          plain: '${indentText(s.indent)}${s.title}\n',
          widget: titleWidget(),
        ));

        if (leafText.isNotEmpty) {
          out.add(_PdfEntry(
            plain:
                '${indentText(s.indent + (doc.indentContent ? 1 : 0))}$leafText\n\n',
            widget: contentWidget(leafText),
          ));
        } else {
          out.add(_PdfEntry(plain: '\n', widget: pw.SizedBox(height: 6)));
        }
        return;
      }

      out.add(_PdfEntry(
        plain: '${indentText(s.indent)}${s.title}: $leafText\n\n',
        widget: inlineWidget(
          leafText,
          aligned: doc.reportLayout == ReportLayout.aligned,
        ),
      ));
    }

    for (final s in doc.roots) {
      walk(s);
    }

    return out;
  }

  (List<_PdfEntry>, List<_PdfEntry>) _splitEntries(List<_PdfEntry> entries, int splitIndex) {
    if (splitIndex <= 0) return (<_PdfEntry>[], entries);
    var seen = 0;
    final first = <_PdfEntry>[];
    final rest = <_PdfEntry>[];
    for (final e in entries) {
      final next = seen + e.plain.length;
      if (next <= splitIndex) {
        first.add(e);
      } else {
        rest.add(e);
      }
      seen = next;
    }
    return (first, rest);
  }

  pw.Widget _entriesBlock(List<_PdfEntry> entries) {
    if (entries.isEmpty) return _textBlock('');
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: entries.map((e) => e.widget).toList(growable: false),
    );
  }

  pw.Widget _inlineColumnFixed(
    List<pw.MemoryImage> images, {
    required double totalHeight,
  }) {
    const slots = 4;
    const gap = 10.0;

    final slotHeight = (totalHeight - (gap * (slots - 1))) / slots;

    pw.Widget slot(pw.MemoryImage? img) {
      return pw.Container(
        height: slotHeight,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(12),
        ),
        child: img == null
            ? pw.Center(
                child: pw.Text(
                  '(empty)',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                ),
              )
            : pw.ClipRRect(
                horizontalRadius: 12,
                verticalRadius: 12,
                child: pw.Image(img, fit: pw.BoxFit.cover),
              ),
      );
    }

    final filled = List<pw.MemoryImage?>.generate(
      slots,
      (i) => i < images.length ? images[i] : null,
    );

    final children = <pw.Widget>[];
    for (int i = 0; i < slots; i++) {
      children.add(slot(filled[i]));
      if (i != slots - 1) children.add(pw.SizedBox(height: gap));
    }

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: children);
  }

  pw.Widget _attachmentsGridFixed(List<pw.MemoryImage> images) {
    const slots = 8;
    const cols = 2;
    const gap = 10.0;

    pw.Widget cell(pw.MemoryImage? img) {
      return pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.6, color: PdfColors.grey400),
          borderRadius: pw.BorderRadius.circular(10),
        ),
        padding: const pw.EdgeInsets.all(4),
        child: img == null
            ? pw.Center(
                child: pw.Text(
                  '(empty)',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                ),
              )
            : pw.ClipRRect(
                horizontalRadius: 10,
                verticalRadius: 10,
                child: pw.Image(img, fit: pw.BoxFit.cover),
              ),
      );
    }

    final filled = List<pw.MemoryImage?>.generate(
      slots,
      (i) => i < images.length ? images[i] : null,
    );

    return pw.GridView(
      crossAxisCount: cols,
      mainAxisSpacing: gap,
      crossAxisSpacing: gap,
      childAspectRatio: 1.25,
      children: filled.map(cell).toList(),
    );
  }

  (String, String) _splitForFirstPage(
    String text, {
    required bool inlineEnabled,
  }) {
    if (text.trim().isEmpty) return ('', '');
    final approxChars = inlineEnabled ? 900 : 1400;
    if (text.length <= approxChars) return (text, '');

    final cut = text.lastIndexOf('\n', approxChars);
    final idx = cut > 200 ? cut : approxChars;

    return (text.substring(0, idx).trim(), text.substring(idx).trim());
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

  List<List<T>> _chunk<T>(List<T> items, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < items.length; i += size) {
      chunks.add(items.sublist(i, (i + size).clamp(0, items.length)));
    }
    return chunks;
  }
}

class _PdfEntry {
  const _PdfEntry({required this.plain, required this.widget});
  final String plain;
  final pw.Widget widget;
}

String indentText(int level, {int spacesPerLevel = 2}) {
  final n = (level.clamp(0, 30)) * spacesPerLevel;
  return ' ' * n;
}