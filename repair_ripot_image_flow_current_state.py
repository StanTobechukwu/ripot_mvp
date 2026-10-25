#!/usr/bin/env python3
from pathlib import Path
import subprocess, sys

ROOT = Path.cwd()
RENDER = ROOT / "lib/features/reports/services/pdf_renderer_service.dart"
PLAN = ROOT / "lib/features/reports/domain/pdf/pdf_plan_builder.dart"

def fail(msg):
    print(f"\nERROR: {msg}\nNo files were written.\n", file=sys.stderr)
    sys.exit(1)

def replace_exact(text, old, new, label):
    n = text.count(old)
    if n != 1:
        fail(f"{label}: expected 1 exact match, found {n}")
    return text.replace(old, new, 1)

if not RENDER.exists() or not PLAN.exists():
    fail("Run this script from the Ripot Flutter project root.")

branch = subprocess.check_output(["git","branch","--show-current"], text=True).strip()
if branch != "ripot-structured-inputs-image-flow":
    fail(f"Wrong branch: {branch}")

r0 = RENDER.read_text(encoding="utf-8")
p0 = PLAN.read_text(encoding="utf-8")
r = r0
p = p0

# ------------------------------------------------------------------
# 1) PLAN BUILDER: inline mode => overflow stays report content
# ------------------------------------------------------------------

old = """    final pageOneInline = doc.images
        .take(metrics.maxPage1InlineSlots)
        .toList(growable: false);
    final attachmentImages = doc.images
        .skip(pageOneInline.length)
        .toList(growable: false);

    return PdfPlan(
      title: title,
      inlineEnabled: true,
      pageOne: PageOnePlan(inlineImages: pageOneInline),
      finalContent: const FinalContentPlan(spillInlineImages: []),
      attachmentPages: [
        for (final chunk in chunked(
          attachmentImages,
          metrics.attachmentImagesPerPage,
        ))
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

    return PdfPlan(
      title: title,
      inlineEnabled: true,
      pageOne: PageOnePlan(inlineImages: pageOneInline),
      finalContent: FinalContentPlan(spillInlineImages: spillInline),
      attachmentPages: const [],
    );
"""

p = replace_exact(p, old, new, "planner inline-mode classification")

# ------------------------------------------------------------------
# 2) FIRST-PAGE VERTICAL COLUMN:
#    do NOT limit by text height. Use actual page height.
# ------------------------------------------------------------------

old = """      final imageColumnLimit = max(0.0, firstPageTextHeight - 2.0);
      pageOneInlineImages = _inlineImagesThatFitWithin(
        pageOneInlineCandidates,
        maxHeight: imageColumnLimit,
        metrics: metrics,
        fontScale: fontScale,
      );
"""

new = """      final imageColumnLimit = max(0.0, availableAfterTop);
      pageOneInlineImages = _inlineImagesThatFitWithin(
        pageOneInlineCandidates,
        maxHeight: imageColumnLimit,
        metrics: metrics,
        fontScale: fontScale,
      );
"""

r = replace_exact(r, old, new, "vertical-column capacity")

# ------------------------------------------------------------------
# 3) Replace current simple reportOverflow block with page-1 allocation.
# ------------------------------------------------------------------

old = """    // Everything not used by the first-page side column remains report
    // content. Preserve source order and flow it below report text.
    final reportOverflowImages = <_PdfLoadedImage>[
      ...allInlineCandidates.skip(pageOneInlineImages.length),
    ];

    // True attachments are the only images allowed on attachment pages.
    final attachmentImgs = <_PdfLoadedImage>[...plannedAttachmentImgs];

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

    // The first-page top row height is whichever is taller:
    // report text or the vertical image column.
    final firstPageImageColumnHeight = _inlineColumnEstimatedHeight(
      pageOneInlineImages,
      metrics: metrics,
      fontScale: fontScale,
    );
    final firstPageTopRowHeight = max(
      firstPageTextHeight + 6.0,
      firstPageImageColumnHeight,
    );

    // Use any actual remaining first-page space for horizontal report images.
    final pageOneHorizontalAvailable = max(
      0.0,
      availableAfterTop - firstPageTopRowHeight,
    );
    final pageOneHorizontalRows = _horizontalImageRowsThatFit(
      availableHeight: pageOneHorizontalAvailable,
      metrics: metrics,
    );
    final pageOneHorizontalCapacity = pageOneHorizontalRows * 3;

    final pageOneReportOverflowImages = allReportOverflowImages
        .take(pageOneHorizontalCapacity)
        .toList(growable: false);

    final reportOverflowImages = allReportOverflowImages
        .skip(pageOneReportOverflowImages.length)
        .toList(growable: false);

    // Only genuine attachment-mode images belong on attachment pages.
    final attachmentImgs = <_PdfLoadedImage>[...plannedAttachmentImgs];

    // Signature must appear after every report image.
    if (allReportOverflowImages.isNotEmpty) {
      canPlaceSignatureOnFirstPage = false;
    }

    final hasMoreContentPages =
        remainingTemplates.isNotEmpty ||
        reportOverflowImages.isNotEmpty ||
        !canPlaceSignatureOnFirstPage;
"""

r = replace_exact(r, old, new, "page-one horizontal allocation")

# ------------------------------------------------------------------
# 4) Insert first-page horizontal rows immediately under top row.
# ------------------------------------------------------------------

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

r = replace_exact(r, old, new, "page-one horizontal rows insertion")

# ------------------------------------------------------------------
# 5) LEFT align horizontal rows, not center.
# ------------------------------------------------------------------

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

r = replace_exact(r, old, new, "left alignment")

# ------------------------------------------------------------------
# 6) Add row-fit helper immediately before _reportImageOverflowRows.
# ------------------------------------------------------------------

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

r = replace_exact(r, anchor, helper, "row-fit helper")

# ------------------------------------------------------------------
# 7) Sanity checks before writing.
# ------------------------------------------------------------------

required_renderer = [
    "pageOneReportOverflowImages",
    "_horizontalImageRowsThatFit(",
    "mainAxisAlignment: pw.MainAxisAlignment.start",
]
for item in required_renderer:
    if item not in r:
        fail(f"Renderer sanity check failed: missing {item}")

if "inlineToAttachments" in r:
    fail("Renderer still contains inlineToAttachments.")

if "final attachmentImages = doc.images" in p:
    fail("Planner still contains old attachmentImages path.")

if "spillInlineImages: spillInline" not in p:
    fail("Planner did not gain spillInlineImages: spillInline.")

if "attachmentPages: const []" not in p:
    fail("Planner did not gain attachmentPages: const [].")

# write only after all checks pass
RENDER.write_text(r, encoding="utf-8")
PLAN.write_text(p, encoding="utf-8")

print("\nSUCCESS: repaired current local image-flow state.")
print("\nChanged:")
print("  lib/features/reports/services/pdf_renderer_service.dart")
print("  lib/features/reports/domain/pdf/pdf_plan_builder.dart")

print("\nRun:")
print("  dart format lib/features/reports/services/pdf_renderer_service.dart lib/features/reports/domain/pdf/pdf_plan_builder.dart")
print("  flutter analyze lib/features/reports/services/pdf_renderer_service.dart lib/features/reports/domain/pdf/pdf_plan_builder.dart")
print("  flutter clean")
print("  flutter pub get")
print("  flutter run -d chrome")
print("\nDo not commit until the 8-image test is visually correct.")
