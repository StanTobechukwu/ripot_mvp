#!/usr/bin/env python3
"""
Ripot Stage 2: hybrid report-image flow.

Run from the Ripot project root on:
  ripot-structured-inputs-image-flow

Implements:
- report images remain report content (never reclassified as attachments)
- fixed 160 x 108 image size
- first-page vertical image column beside report text when space permits
- excess report images flow horizontally below report text
- maximum 3 report images per horizontal row
- horizontal rows paginate naturally across report pages
- signature comes after ALL report images
- only true attachments use attachment pages
"""

from pathlib import Path
import subprocess
import sys

ROOT = Path.cwd()
REL = "lib/features/reports/services/pdf_renderer_service.dart"
PATH = ROOT / REL

def die(msg):
    print(f"\nERROR: {msg}\nNo files were written.\n", file=sys.stderr)
    sys.exit(1)

def replace_one(text, old, new, label):
    c = text.count(old)
    if c != 1:
        die(f"{label}: expected exactly 1 match, found {c}.")
    return text.replace(old, new, 1)

if not PATH.exists():
    die(f"Missing {REL}. Run from the Flutter project root.")

try:
    branch = subprocess.check_output(["git", "branch", "--show-current"], text=True).strip()
except Exception:
    branch = ""

if branch and branch != "ripot-structured-inputs-image-flow":
    die(f"Current branch is '{branch}'. Switch to ripot-structured-inputs-image-flow first.")

original = PATH.read_text(encoding="utf-8")
t = original

# ------------------------------------------------------------------
# 1. Update renderer design comment.
# ------------------------------------------------------------------
t = replace_one(
    t,
    """    // Hybrid sequential renderer with a true first-page inline image column:
    // - first page keeps inline images in the right column as originally designed;
    // - left column flows title/subject/report content and the signature as final content;
    // - excess text continues on normal pages;
    // - excess inline images are moved to attachments, never dropped.
""",
    """    // Hybrid report-image renderer:
    // - report images remain report content throughout;
    // - first-page images use the fixed right-side vertical column when they fit;
    // - excess report images flow in fixed-size horizontal rows below report text;
    // - horizontal image rows may continue across report pages;
    // - the signature is always after all report images;
    // - only true attachments are rendered on attachment pages.
""",
    "renderer design comment",
)

# ------------------------------------------------------------------
# 2. No-report-image path: wording only (behavior already correct).
# ------------------------------------------------------------------
t = replace_one(
    t,
    """    // Stable default path: use the complex first-page right-column renderer
    // only when inline images are actually selected. Attachment-only and
    // no-image reports use MultiPage so content and signature flow naturally.
""",
    """    // Stable default path for reports with no report images. True
    // attachments remain separate and are rendered only after the signature.
""",
    "no-report-image comment",
)

# ------------------------------------------------------------------
# 3. Replace report-image -> attachment reclassification with true overflow.
# ------------------------------------------------------------------
old = """    final inlineToAttachments = <_PdfLoadedImage>[
      ...pageOneInlineCandidates.skip(pageOneInlineImages.length),
      ...allInlineCandidates.skip(pageOneInlineCandidates.length),
    ];

    final attachmentImgs = <_PdfLoadedImage>[
      ...inlineToAttachments,
      ...plannedAttachmentImgs,
    ];

    final hasMoreContentPages =
        remainingTemplates.isNotEmpty || !canPlaceSignatureOnFirstPage;
"""
new = """    // Everything not used by the first-page side column remains report
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
t = replace_one(t, old, new, "report overflow classification")

# ------------------------------------------------------------------
# 4. Continuation flow: text -> report overflow rows -> signature.
# ------------------------------------------------------------------
old = """    if (remainingTemplates.isNotEmpty || !canPlaceSignatureOnFirstPage) {
      final continuationWidgets = <pw.Widget>[
        ..._templatesToWidgets(remainingTemplates),
        pw.SizedBox(height: 6),
        _signatureBlock(doc, signatureImg, fontScale: fontScale),
      ];
"""
new = """    if (remainingTemplates.isNotEmpty ||
        reportOverflowImages.isNotEmpty ||
        !canPlaceSignatureOnFirstPage) {
      final continuationWidgets = <pw.Widget>[
        ..._templatesToWidgets(remainingTemplates),
        if (reportOverflowImages.isNotEmpty) ...[
          if (remainingTemplates.isNotEmpty) pw.SizedBox(height: 8),
          ..._reportImageOverflowRows(
            reportOverflowImages,
            metrics: metrics,
          ),
        ],
        pw.SizedBox(height: 6),
        _signatureBlock(doc, signatureImg, fontScale: fontScale),
      ];
"""
t = replace_one(t, old, new, "continuation report-image flow")

# ------------------------------------------------------------------
# 5. Add fixed 3-across overflow-row helper before _inlineImageCell.
# Each row is its own MultiPage child, so rows can paginate naturally.
# ------------------------------------------------------------------
anchor = """  pw.Widget _inlineImageCell(
    _PdfLoadedImage entry, {
    required PdfLayoutMetrics metrics,
  }) {
"""
helper = """  List<pw.Widget> _reportImageOverflowRows(
    List<_PdfLoadedImage> images, {
    required PdfLayoutMetrics metrics,
  }) {
    if (images.isEmpty) return const <pw.Widget>[];

    final widgets = <pw.Widget>[];
    const imagesPerRow = 3;

    for (int i = 0; i < images.length; i += imagesPerRow) {
      final rowImages = images
          .skip(i)
          .take(imagesPerRow)
          .toList(growable: false);

      final rowChildren = <pw.Widget>[];
      for (int j = 0; j < rowImages.length; j++) {
        if (j > 0) {
          rowChildren.add(pw.SizedBox(width: metrics.inlineSlotGap));
        }
        rowChildren.add(
          pw.SizedBox(
            width: metrics.inlineColumnWidth,
            height: metrics.inlineSlotHeight,
            child: _inlineImageCell(
              rowImages[j],
              metrics: metrics,
            ),
          ),
        );
      }

      widgets.add(
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: rowChildren,
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
"""
t = replace_one(t, anchor, helper, "fixed overflow row helper")

# ------------------------------------------------------------------
# 6. Make the image cell itself fixed-size everywhere, not just by parent.
# ------------------------------------------------------------------
old = """    return pw.SizedBox(
      height: metrics.inlineSlotHeight,
      child: pw.Stack(
"""
new = """    return pw.SizedBox(
      width: metrics.inlineColumnWidth,
      height: metrics.inlineSlotHeight,
      child: pw.Stack(
"""
t = replace_one(t, old, new, "fixed 160x108 image cell")

# ------------------------------------------------------------------
# 7. Update first-page explanatory comments so semantics are unambiguous.
# ------------------------------------------------------------------
t = t.replace(
    "the first image that enters the signature area and later images move\n    //    to attachments.",
    "the first image that enters the signature area and later images flow\n    //    below the report text.",
    1,
)
t = t.replace(
    "// Otherwise the image is moved to attachments, never dropped.",
    "// Otherwise the image flows below the report text, never dropped.",
    1,
)

if t == original:
    die("Script made no changes.")

PATH.write_text(t, encoding="utf-8")

print("Applied Ripot hybrid report-image flow successfully.")
print("Changed 1 file:")
print(f"  - {REL}")
print("\nImplemented:")
print("  - fixed 160 x 108 report images")
print("  - first-page vertical side column when space permits")
print("  - excess report images flow below text, max 3 per row")
print("  - rows paginate naturally")
print("  - signature follows all report images")
print("  - true attachments remain separate")
print("\nNext run:")
print(f"  dart format {REL}")
print(f"  flutter analyze {REL}")
print("  flutter run -d chrome")
print("\nDo not commit until PDF behavior has been tested.")
