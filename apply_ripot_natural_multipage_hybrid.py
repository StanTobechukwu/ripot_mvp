#!/usr/bin/env python3
"""
Ripot: switch hybrid report-image rendering to natural MultiPage flow.

Run from the Ripot Flutter project root on:
  ripot-structured-inputs-image-flow

PRECONDITION:
  First checkpoint/commit the current "much better" hybrid image state.

Only modifies:
  lib/features/reports/services/pdf_renderer_service.dart
"""

from pathlib import Path
import subprocess
import sys

ROOT = Path.cwd()
REL = "lib/features/reports/services/pdf_renderer_service.dart"
PATH = ROOT / REL

def die(msg):
    print(f"\nERROR: {msg}\nNo file was written.\n", file=sys.stderr)
    sys.exit(1)

if not PATH.exists():
    die(f"Missing {REL}. Run from the Flutter project root.")

try:
    branch = subprocess.check_output(
        ["git", "branch", "--show-current"], text=True
    ).strip()
except Exception:
    branch = ""

if branch and branch != "ripot-structured-inputs-image-flow":
    die(
        f"Current branch is '{branch}'. "
        "Switch to ripot-structured-inputs-image-flow first."
    )

text = PATH.read_text(encoding="utf-8")

start_markers = [
    "    // Page 1 begins with a report-text / vertical-image top row.\n",
    "    // Page 1 is treated as two independent zones:\n",
    "    // Hybrid rendering strategy:\n",
]
start = -1
for marker in start_markers:
    start = text.find(marker)
    if start != -1:
        break

if start == -1:
    die("Could not find the start of the current hybrid first-page renderer.")

end_marker = "    if (attachmentImgs.isNotEmpty) {\n"
end = text.find(end_marker, start)
if end == -1:
    die("Could not find attachment-page rendering boundary.")

old_block = text[start:end]
for token in ["pageOneInlineImages", "remainingTemplates", "_reportImageOverflowRows"]:
    if token not in old_block:
        die(f"Current hybrid block is not the expected state; missing '{token}'.")

new_block = """    // Hybrid rendering strategy:
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
        ..._reportImageOverflowRows(
          reportOverflowImages,
          metrics: metrics,
        ),
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

"""

text = text[:start] + new_block + text[end:]

helper_start = text.find("  List<pw.Widget> _reportImageOverflowRows(\n")
if helper_start == -1:
    die("Could not find _reportImageOverflowRows helper.")

helper_end = text.find("  pw.Widget _inlineImageCell(\n", helper_start)
if helper_end == -1:
    die("Could not find end of _reportImageOverflowRows helper.")

new_helper = """  List<pw.Widget> _reportImageOverflowRows(
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
              child: _inlineImageCell(
                rowImages[slot],
                metrics: metrics,
              ),
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

"""

text = text[:helper_start] + new_helper + text[helper_end:]

# Remove the temporary/manual row-fit helper if present.
row_fit_start = text.find("  int _horizontalImageRowsThatFit({\n")
if row_fit_start != -1:
    row_fit_end = text.find(
        "  List<pw.Widget> _reportImageOverflowRows(\n",
        row_fit_start,
    )
    if row_fit_end == -1:
        die("Found row-fit helper but could not identify its end.")
    text = text[:row_fit_start] + text[row_fit_end:]

# Sanity checks.
for token in [
    "final naturalFlowWidgets = <pw.Widget>[",
    "mainAxisAlignment: pw.MainAxisAlignment.spaceBetween",
    "final reportOverflowImages = <_PdfLoadedImage>[",
]:
    if token not in text:
        die(f"Sanity check failed; missing '{token}'.")

hybrid_end = text.find(end_marker, start)
hybrid_preview = text[start:hybrid_end]
for forbidden in [
    "canPlaceSignatureOnFirstPage",
    "_signatureFitsAvailableSpace(",
    "_signatureFitRelief(",
    "pageOneReportOverflowImages",
    "_horizontalImageRowsThatFit(",
]:
    if forbidden in hybrid_preview:
        die(f"Manual-fit logic still remains in hybrid path: '{forbidden}'.")

PATH.write_text(text, encoding="utf-8")

print("\nSUCCESS: hybrid image rendering now uses natural MultiPage flow.")
print(f"Changed only: {REL}")
print("\nRun next:")
print(f"  dart format {REL}")
print(f"  flutter analyze {REL}")
print("  flutter clean")
print("  flutter pub get")
print("  flutter run -d chrome")
print("\nTest before committing this experiment.")
