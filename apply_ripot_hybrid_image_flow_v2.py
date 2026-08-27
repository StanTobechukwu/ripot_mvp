#!/usr/bin/env python3
"""
Ripot Stage 2B: deterministic hybrid report-image flow.

Run from the Ripot project root on:
  ripot-structured-inputs-image-flow

This is a SECOND-PASS patch intended after apply_ripot_hybrid_image_flow.py.

Fixes:
1. Inline/report images never become attachment images.
2. PdfPlanBuilder puts ALL remaining inline images into spillInlineImages.
3. First-page vertical column greedily uses up to 4 fixed 160x108 slots
   based on actual page space, not report-text height.
4. Remaining report images use spare space lower on page 1 when possible.
5. Horizontal overflow is fixed-size, max 3 per row, LEFT aligned.
6. Remaining horizontal rows paginate naturally across later report pages.
7. Signature appears only after all report images.
8. Only genuine attachment-mode images use "Image Attachments" pages.

The script fails safely if the expected current code is not found.
"""

from pathlib import Path
import subprocess
import sys

ROOT = Path.cwd()
RENDER_REL = "lib/features/reports/services/pdf_renderer_service.dart"
PLAN_REL = "lib/features/reports/domain/pdf/pdf_plan_builder.dart"
RENDER = ROOT / RENDER_REL
PLAN = ROOT / PLAN_REL

def die(msg):
    print(f"\nERROR: {msg}\nNo files were written.\n", file=sys.stderr)
    sys.exit(1)

def replace_one(text, old, new, label):
    count = text.count(old)
    if count != 1:
        die(f"{label}: expected exactly 1 match, found {count}.")
    return text.replace(old, new, 1)

if not RENDER.exists():
    die(f"Missing {RENDER_REL}. Run from the Flutter project root.")
if not PLAN.exists():
    die(f"Missing {PLAN_REL}. Run from the Flutter project root.")

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

render_original = RENDER.read_text(encoding="utf-8")
plan_original = PLAN.read_text(encoding="utf-8")
r = render_original
p = plan_original

# ---------------------------------------------------------------------------
# A. PLAN BUILDER
# When image placement is inline/report mode:
#   first 4 -> page-one candidates
#   ALL remaining -> spillInlineImages
#   attachments -> none
# Attachment mode continues to use attachmentPages.
# ---------------------------------------------------------------------------

old = """    final pageOneInline = doc.images.take(metrics.maxPage1InlineSlots).toList(growable: false);
    final attachmentImages = doc.images.skip(pageOneInline.length).toList(growable: false);

    return PdfPlan(
      title: title,
      inlineEnabled: true,
      pageOne: PageOnePlan(inlineImages: pageOneInline),
      finalContent: const FinalContentPlan(spillInlineImages: []),
      attachmentPages: [
        for (final chunk in chunked(attachmentImages, metrics.attachmentImagesPerPage))
          AttachmentPagePlan(images: chunk),
      ],
    );
"""

new = """    final pageOneInline = doc.images
        .take(metrics.maxPage1InlineSlots)
        .toList(growable: false);
    final spillInline = doc.images
        .skip(pageOneInline.length)
        .toList(growable: false);

    // Inline mode means every selected image is report content.
    // Images that do not fit the first-page side column remain report images
    // and are flowed horizontally by PdfRendererService. They must never be
    // reclassified as attachment-page images merely because of quantity.
    return PdfPlan(
      title: title,
      inlineEnabled: true,
      pageOne: PageOnePlan(inlineImages: pageOneInline),
      finalContent: FinalContentPlan(spillInlineImages: spillInline),
      attachmentPages: const [],
    );
"""

p = replace_one(p, old, new, "PdfPlanBuilder inline image classification")

# ---------------------------------------------------------------------------
# B. RENDERER — vertical column
# Old logic limits side images to report text height. That is why obvious
# vertical space is wasted. Let the side column use the actual first-page
# content area. maxPage1InlineSlots still caps it at 4.
# ---------------------------------------------------------------------------

old = """      final imageColumnLimit = max(0.0, firstPageTextHeight - 2.0);
      pageOneInlineImages = _inlineImagesThatFitWithin(
        pageOneInlineCandidates,
        maxHeight: imageColumnLimit,
        metrics: metrics,
        fontScale: fontScale,
      );
"""

new = """      // The side column may extend below the report text. The page itself,
      // not the text height, is the true vertical boundary. This lets Ripot
      // use all available fixed slots (up to maxPage1InlineSlots) instead of
      // prematurely moving images out of the vertical column.
      final imageColumnLimit = max(0.0, availableAfterTop);
      pageOneInlineImages = _inlineImagesThatFitWithin(
        pageOneInlineCandidates,
        maxHeight: imageColumnLimit,
        metrics: metrics,
        fontScale: fontScale,
      );
"""

r = replace_one(r, old, new, "first-page vertical image capacity")

# ---------------------------------------------------------------------------
# C. Replace V1 report-overflow block with:
# - all overflow stays report content
# - fill complete horizontal rows into remaining page-1 space
# - carry the rest to continuation pages
# ---------------------------------------------------------------------------

old = """    // Everything not used by the first-page side column remains report
    // content. Preserve source order and flow it below report text.
    final reportOverflowImages = <_PdfLoadedImage>[
      ...allInlineCandidates.skip(pageOneInlineImages.length),
    ];

    // True attachments are the only images allowed on attachment pages.
    final attachmentImgs = <_PdfLoadedImage>[
      ...plannedAttachmentImgs,
    ];

    // If report images still remain, the signature must move after them.
    if (reportOverflowImages.isNotEmpty) {
      canPlaceSignatureOnFirstPage = false;
    }

    final hasMoreContentPages =
        remainingTemplates.isNotEmpty ||
        reportOverflowImages.isNotEmpty ||
        !canPlaceSignatureOnFirstPage;
"""

new = """    // Everything not used by the first-page side column remains report
    // content. Preserve source order.
    final allReportOverflowImages = <_PdfLoadedImage>[
      ...allInlineCandidates.skip(pageOneInlineImages.length),
    ];

    // Calculate the real height occupied by the first page's top row:
    // whichever is taller — report text or the vertical image column.
    final firstPageImageColumnHeight = _inlineColumnEstimatedHeight(
      pageOneInlineImages,
      metrics: metrics,
      fontScale: fontScale,
    );
    final firstPageTopRowHeight = max(
      firstPageTextHeight + 6.0,
      firstPageImageColumnHeight,
    );

    // Any remaining space below that top row can be used immediately on page 1
    // for horizontal report-image rows. Rows are fixed 108pt high, have the
    // normal 10pt gap, and contain at most 3 images.
    final pageOneHorizontalAvailable = max(
      0.0,
      availableAfterTop - firstPageTopRowHeight,
    );
    final pageOneHorizontalRowCount = _horizontalImageRowsThatFit(
      availableHeight: pageOneHorizontalAvailable,
      metrics: metrics,
    );
    final pageOneHorizontalCapacity = pageOneHorizontalRowCount * 3;

    final pageOneReportOverflowImages = allReportOverflowImages
        .take(pageOneHorizontalCapacity)
        .toList(growable: false);
    final reportOverflowImages = allReportOverflowImages
        .skip(pageOneReportOverflowImages.length)
        .toList(growable: false);

    // True attachments are the only images allowed on attachment pages.
    final attachmentImgs = <_PdfLoadedImage>[
      ...plannedAttachmentImgs,
    ];

    // Any horizontal report-image flow means signature placement must occur
    // AFTER that image flow. We deliberately do not let the signature appear
    // inside the first-page text column before lower-page report images.
    if (allReportOverflowImages.isNotEmpty) {
      canPlaceSignatureOnFirstPage = false;
    }

    final hasMoreContentPages =
        remainingTemplates.isNotEmpty ||
        reportOverflowImages.isNotEmpty ||
        !canPlaceSignatureOnFirstPage;
"""

r = replace_one(r, old, new, "first-page horizontal overflow allocation")

# ---------------------------------------------------------------------------
# D. Put page-one horizontal overflow immediately below the top row.
# ---------------------------------------------------------------------------

old = """              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: firstPageTextWidth,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        _entriesBlock(
                          firstPageEntries,
                          contentFontSize: contentFontSize,
                        ),
                        if (canPlaceSignatureOnFirstPage) ...[
                          pw.SizedBox(height: 6),
                          _signatureBlock(
                            doc,
                            signatureImg,
                            fontScale: fontScale,
                          ),
                        ],
                      ],
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
"""

new = """              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: firstPageTextWidth,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        _entriesBlock(
                          firstPageEntries,
                          contentFontSize: contentFontSize,
                        ),
                        if (canPlaceSignatureOnFirstPage) ...[
                          pw.SizedBox(height: 6),
                          _signatureBlock(
                            doc,
                            signatureImg,
                            fontScale: fontScale,
                          ),
                        ],
                      ],
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
              if (pageOneReportOverflowImages.isNotEmpty) ...[
                pw.SizedBox(height: metrics.inlineSlotGap),
                ..._reportImageOverflowRows(
                  pageOneReportOverflowImages,
                  metrics: metrics,
                ),
              ],
"""

r = replace_one(r, old, new, "page-one horizontal report-image rows")

# ---------------------------------------------------------------------------
# E. V1 overflow helper centered partial rows.
# Change to left/start alignment.
# ---------------------------------------------------------------------------

old = """        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: rowChildren,
        ),
"""

new = """        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.start,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: rowChildren,
        ),
"""

r = replace_one(r, old, new, "left-align horizontal report-image rows")

# ---------------------------------------------------------------------------
# F. Add exact row-fit helper before _reportImageOverflowRows.
# It counts only COMPLETE rows. No partial row is inserted if it would cross
# the physical first-page content boundary.
# ---------------------------------------------------------------------------

anchor = """  List<pw.Widget> _reportImageOverflowRows(
    List<_PdfLoadedImage> images, {
    required PdfLayoutMetrics metrics,
  }) {
"""

helper = """  int _horizontalImageRowsThatFit({
    required double availableHeight,
    required PdfLayoutMetrics metrics,
  }) {
    if (availableHeight < metrics.inlineSlotHeight) return 0;

    // n rows require:
    //   n * slotHeight + (n - 1) * gap
    // Rearranged to a simple floor calculation.
    return ((availableHeight + metrics.inlineSlotGap) /
            (metrics.inlineSlotHeight + metrics.inlineSlotGap))
        .floor()
        .clamp(0, 1000);
  }

  List<pw.Widget> _reportImageOverflowRows(
    List<_PdfLoadedImage> images, {
    required PdfLayoutMetrics metrics,
  }) {
"""

r = replace_one(r, anchor, helper, "horizontal row-fit helper")

# ---------------------------------------------------------------------------
# G. Clean misleading old first-page comments.
# ---------------------------------------------------------------------------

r = r.replace(
"""    // Page 1 is treated as two independent zones:
    // - left zone: title/subject/report content + signature as final content;
    // - right zone: inline image column only.
    // Keep an inline image only if it fits the page and does not extend below
    // the bottom of the signature block when both are present on page 1.
    // Otherwise the image flows below the report text, never dropped.
""",
"""    // Page 1 begins with a report-text / vertical-image top row.
    // The vertical side column may extend below shorter report text, up to the
    // physical page boundary and the configured four-slot maximum.
    // Remaining report images then use horizontal rows below that top row.
""",
1,
)

r = r.replace(
"""    // More accurate first-page decision:
    // 1) Lay out the left report column first using the same width that will
    //    be used when a right-side inline image column is present.
    // 2) Place the signature as the next left-column content block.
    // 3) Use the resulting signature top as the right-column image boundary.
    //    This is per-image: images that end before the signature remain inline;
    //    the first image that enters the signature area and later images flow
    //    below the report text.
""",
"""    // First lay out the report text at the same narrow width used beside the
    // fixed side column. The side column is then allowed to fill independently
    // to the page boundary. Signature placement is resolved only after every
    // report image has been allocated.
""",
1,
)

# ---------------------------------------------------------------------------
# H. Safety checks before writing.
# ---------------------------------------------------------------------------

if r == render_original:
    die("Renderer patch made no changes.")
if p == plan_original:
    die("Plan-builder patch made no changes.")

# Write only after ALL replacements have succeeded.
RENDER.write_text(r, encoding="utf-8")
PLAN.write_text(p, encoding="utf-8")

print("\nApplied Ripot deterministic hybrid image-flow fix successfully.")
print("Changed 2 files:")
print(f"  - {RENDER_REL}")
print(f"  - {PLAN_REL}")

print("\nExpected behavior now:")
print("  1. Up to 4 report images greedily fill the page-1 vertical column.")
print("  2. Remaining report images use spare lower page-1 space.")
print("  3. Horizontal rows are fixed 160x108, max 3 per row, LEFT aligned.")
print("  4. Remaining rows continue across page 2, page 3, etc.")
print("  5. Signature comes after ALL report images.")
print("  6. Inline/report images never become Image Attachments.")
print("  7. Attachment-mode images still render on attachment pages.")

print("\nRun next:")
print(f"  dart format {RENDER_REL} {PLAN_REL}")
print(f"  flutter analyze {RENDER_REL} {PLAN_REL}")
print("  flutter run -d chrome")

print("\nTest before committing.")
