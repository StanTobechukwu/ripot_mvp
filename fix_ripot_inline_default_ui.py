#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys

ROOT = Path.cwd()
PROVIDER_REL = "lib/features/reports/providers/report_editor_provider.dart"
UI_REL = "lib/features/reports/ui/report_editor_screen.dart"

PROVIDER = ROOT / PROVIDER_REL
UI = ROOT / UI_REL

def die(msg):
    print(f"\nERROR: {msg}\nNo files were written.\n", file=sys.stderr)
    sys.exit(1)

for p in (PROVIDER, UI):
    if not p.exists():
        die(f"Missing {p.relative_to(ROOT)}")

try:
    branch = subprocess.check_output(["git", "branch", "--show-current"], text=True).strip()
except Exception:
    branch = ""

if branch and branch != "ripot-structured-inputs-image-flow":
    die(f"Wrong branch: {branch}")

pr = PROVIDER.read_text(encoding="utf-8")
ui = UI.read_text(encoding="utf-8")

# Provider explicitly overrides the model default in two NEW-report paths.
old_provider = "      placementChoice: ImagePlacementChoice.attachmentsOnly,"
count = pr.count(old_provider)
if count != 2:
    die(f"Expected exactly 2 new-report attachment defaults in provider, found {count}")
pr = pr.replace(
    old_provider,
    "      placementChoice: ImagePlacementChoice.inlinePage1,"
)

old_segments = """              segments: const [
                ButtonSegment(
                  value: ImagePlacementChoice.attachmentsOnly,
                  label: Text('Attachments only'),
                ),
                ButtonSegment(
                  value: ImagePlacementChoice.inlinePage1,
                  label: Text('Inline Page 1'),
                ),
"""
new_segments = """              segments: const [
                ButtonSegment(
                  value: ImagePlacementChoice.inlinePage1,
                  label: Text('Inline'),
                ),
                ButtonSegment(
                  value: ImagePlacementChoice.attachmentsOnly,
                  label: Text('Attachments'),
                ),
"""
if ui.count(old_segments) != 1:
    die(f"Expected one image placement segmented control, found {ui.count(old_segments)}")
ui = ui.replace(old_segments, new_segments, 1)

old_summary = """          'Selected: ${vm.doc.images.length} • '
          'Mode: ${vm.doc.placementChoice == ImagePlacementChoice.inlinePage1 ? "Inline enabled (up to 12 total)" : "Attachments only (8 per page)"}',
"""
new_summary = """          'Selected: ${vm.doc.images.length} • '
          'Mode: ${vm.doc.placementChoice == ImagePlacementChoice.inlinePage1 ? "Inline" : "Attachments (12 per page)"}',
"""
if ui.count(old_summary) != 1:
    die(f"Expected one Images card summary, found {ui.count(old_summary)}")
ui = ui.replace(old_summary, new_summary, 1)

old_capacity = """            child: Text(vm.doc.placementChoice == ImagePlacementChoice.attachmentsOnly ? '8 images per attachment page' : 'Max images in this mode: ${vm.doc.maxImages}'),
"""
new_capacity = """            child: Text(
              vm.doc.placementChoice == ImagePlacementChoice.attachmentsOnly
                  ? '12 images per attachment page'
                  : 'Integrated into report • Max ${vm.doc.maxImages} images',
            ),
"""
if ui.count(old_capacity) != 1:
    die(f"Expected one attachment capacity label, found {ui.count(old_capacity)}")
ui = ui.replace(old_capacity, new_capacity, 1)

if pr.count("placementChoice: ImagePlacementChoice.inlinePage1,") < 2:
    die("Provider inline default sanity check failed.")
if "label: Text('Inline')" not in ui or "label: Text('Attachments')" not in ui:
    die("UI segment order sanity check failed.")
if "12 images per attachment page" not in ui:
    die("Attachment UI copy sanity check failed.")

PROVIDER.write_text(pr, encoding="utf-8")
UI.write_text(ui, encoding="utf-8")

print("\nSUCCESS")
print("Changed:")
print(f"  - {PROVIDER_REL}")
print(f"  - {UI_REL}")
print("\nResult:")
print("  - New blank reports default to Inline.")
print("  - Reports started from templates default to Inline.")
print("  - Existing saved reports keep their saved mode.")
print("  - UI order is Inline | Attachments.")
print("  - UI text reflects 12 images per attachment page.")
print("\nRun:")
print(f"  dart format {PROVIDER_REL} {UI_REL}")
print(f"  flutter analyze {PROVIDER_REL} {UI_REL}")
print("  flutter clean")
print("  flutter pub get")
print("  flutter run -d chrome")
print("\nTest with a genuinely NEW report.")
