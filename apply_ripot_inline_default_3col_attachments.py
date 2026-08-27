#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys

ROOT = Path.cwd()
REPORT_REL = "lib/features/reports/domain/models/report_doc.dart"
METRICS_REL = "lib/features/reports/domain/pdf/pdf_layout_metrics.dart"
RENDER_REL = "lib/features/reports/services/pdf_renderer_service.dart"

REPORT = ROOT / REPORT_REL
METRICS = ROOT / METRICS_REL
RENDER = ROOT / RENDER_REL

def die(msg):
    print(f"\nERROR: {msg}\nNo files were written.\n", file=sys.stderr)
    sys.exit(1)

for p in (REPORT, METRICS, RENDER):
    if not p.exists():
        die(f"Missing {p.relative_to(ROOT)}")

try:
    branch = subprocess.check_output(["git", "branch", "--show-current"], text=True).strip()
except Exception:
    branch = ""

if branch and branch != "ripot-structured-inputs-image-flow":
    die(f"Wrong branch: {branch}")

r0 = REPORT.read_text(encoding="utf-8")
m0 = METRICS.read_text(encoding="utf-8")
p0 = RENDER.read_text(encoding="utf-8")

r, m, p = r0, m0, p0

old = "    this.placementChoice = ImagePlacementChoice.attachmentsOnly,"
new = "    this.placementChoice = ImagePlacementChoice.inlinePage1,"
if r.count(old) != 1:
    die(f"Expected exactly one ReportDoc default placement line, found {r.count(old)}")
r = r.replace(old, new, 1)

old = "    this.attachmentImagesPerPage = 8,"
new = "    this.attachmentImagesPerPage = 12,"
if m.count(old) != 1:
    die(f"Expected exactly one attachmentImagesPerPage default, found {m.count(old)}")
m = m.replace(old, new, 1)

start = p.find("  pw.Widget _attachmentsGridFixed(\n")
if start == -1:
    die("Could not find _attachmentsGridFixed.")

end = p.find("  Future<List<_PdfLoadedImage>> _loadLabeledImages(\n", start)
if end == -1:
    die("Could not find the end of _attachmentsGridFixed.")

old_helper = p[start:end]
for token in ["attachmentImagesPerPage", "_PdfLoadedImage", "pw.Widget"]:
    if token not in old_helper:
        die(f"Attachment helper does not look expected; missing {token}")

new_helper = '''  pw.Widget _attachmentsGridFixed(
    List<_PdfLoadedImage> images, {
    required PdfLayoutMetrics metrics,
  }) {
    // Dedicated attachment mode uses the same visual geometry as horizontal
    // report images: three fixed 160x108 positions spanning the full body width.
    const columns = 3;
    final visible = images
        .take(metrics.attachmentImagesPerPage)
        .toList(growable: false);
    final rows = <pw.Widget>[];

    pw.Widget cell(_PdfLoadedImage entry) {
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

    for (int i = 0; i < visible.length; i += columns) {
      final rowImages = visible
          .skip(i)
          .take(columns)
          .toList(growable: false);

      final slots = <pw.Widget>[];
      for (int slot = 0; slot < columns; slot++) {
        if (slot < rowImages.length) {
          slots.add(cell(rowImages[slot]));
        } else {
          slots.add(
            pw.SizedBox(
              width: metrics.inlineColumnWidth,
              height: metrics.inlineSlotHeight,
            ),
          );
        }
      }

      rows.add(
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: slots,
        ),
      );

      if (i + columns < visible.length) {
        rows.add(pw.SizedBox(height: metrics.inlineSlotGap));
      }
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: rows,
    );
  }

'''

p = p[:start] + new_helper + p[end:]

if "this.placementChoice = ImagePlacementChoice.inlinePage1" not in r:
    die("Inline default sanity check failed.")
if "this.attachmentImagesPerPage = 12" not in m:
    die("Attachment capacity sanity check failed.")
if "const columns = 3;" not in p:
    die("Three-column attachment grid sanity check failed.")

REPORT.write_text(r, encoding="utf-8")
METRICS.write_text(m, encoding="utf-8")
RENDER.write_text(p, encoding="utf-8")

print("\nSUCCESS")
print("Changed:")
print(f"  - {REPORT_REL}")
print(f"  - {METRICS_REL}")
print(f"  - {RENDER_REL}")
print("\nBehavior:")
print("  - New reports default to Inline / Integrated images.")
print("  - Existing reports with explicitly saved placement remain unchanged.")
print("  - Attachment pages use 3 fixed 160x108 positions per row.")
print("  - Partial rows preserve left / centre / right positions.")
print("  - Up to 12 attachment images fit per page (4 rows x 3).")
print("\nRun:")
print(f"  dart format {REPORT_REL} {METRICS_REL} {RENDER_REL}")
print(f"  flutter analyze {REPORT_REL} {METRICS_REL} {RENDER_REL}")
print("  flutter clean")
print("  flutter pub get")
print("  flutter run -d chrome")
print("\nTest new-report default mode and explicit Attachment mode before committing.")
