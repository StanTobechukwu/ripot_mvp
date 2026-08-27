#!/usr/bin/env python3
"""
Ripot finishing fixes for structured inputs.

Run from ripot_mvp root on:
  ripot-structured-inputs-image-flow

Fixes:
1. Bottom-sheet scrollbar sits at the sheet edge, while content keeps 16 px padding.
2. PDF hierarchy follows actual section nesting even when legacy/starter indent values are 0.
3. Optional structured notes are emitted by the ACTIVE PDF template renderer.
   Notes also remain visible when "Show value in PDF" is off.
"""

from pathlib import Path
import subprocess
import sys

ROOT = Path.cwd()
FILES = [
    "lib/features/reports/ui/template_editor_screen.dart",
    "lib/features/reports/services/pdf_renderer_service.dart",
]

def die(msg):
    print(f"\nERROR: {msg}\nNo files were written.\n", file=sys.stderr)
    sys.exit(1)

def replace_one(text, old, new, label):
    c = text.count(old)
    if c != 1:
        die(f"{label}: expected exactly 1 match, found {c}.")
    return text.replace(old, new, 1)

for rel in FILES:
    if not (ROOT / rel).exists():
        die(f"Missing {rel}. Run this script from the project root.")

try:
    branch = subprocess.check_output(["git", "branch", "--show-current"], text=True).strip()
except Exception:
    branch = ""

if branch and branch != "ripot-structured-inputs-image-flow":
    die(f"Current branch is '{branch}'. Switch to ripot-structured-inputs-image-flow first.")

original = {rel: (ROOT / rel).read_text(encoding="utf-8") for rel in FILES}
updated = dict(original)

# ---------------------------------------------------------
# 1) Template editor bottom-sheet scrollbar placement
# ---------------------------------------------------------
p = "lib/features/reports/ui/template_editor_screen.dart"
t = updated[p]

old = """    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Column(
"""
new = """    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: 16 + bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
"""
t = replace_one(t, old, new, "template editor sheet scrollbar placement")
updated[p] = t

# ---------------------------------------------------------
# 2 + 3) ACTIVE PDF renderer: tree depth + optional notes
# ---------------------------------------------------------
p = "lib/features/reports/services/pdf_renderer_service.dart"
t = updated[p]

# Isolate only _buildTemplates so we don't disturb the legacy helper renderer.
start = t.find("  List<_PdfTemplate> _buildTemplates(")
end = t.find("  List<_PdfLoadedImage> _inlineImagesThatFitWithin(", start)
if start == -1 or end == -1:
    die("Could not isolate _buildTemplates.")
block = t[start:end]

block = replace_one(
    block,
    """    void walk(SectionNode s) {
      if (!_sectionConditionAllows(doc, s)) return;

      if (!s.showInPdf) {
        for (final child in s.children.whereType<SectionNode>()) {
          walk(child);
        }
        return;
      }

      final sectionChildren = s.children
""",
    """    void walk(SectionNode s, [int treeDepth = 0]) {
      if (!_sectionConditionAllows(doc, s)) return;

      // Structural nesting is the source of truth for visual hierarchy.
      // max() preserves any deliberate larger indent already stored.
      final effectiveIndent = max(s.indent, treeDepth);
      final noteText = s.note.trim();

      final sectionChildren = s.children
""",
    "PDF buildTemplates walk header",
)

block = replace_one(
    block,
    """      final indentPx =
          doc.indentHierarchy ? 12.0 * s.indent : 0.0;
""",
    """      final indentPx =
          doc.indentHierarchy ? 12.0 * effectiveIndent : 0.0;
""",
    "PDF effective visual indent",
)

# Within _buildTemplates, all hierarchy-sensitive text/plain output should use effectiveIndent.
block = block.replace(
    "(s.indent == 0 || s.style.bold)",
    "(effectiveIndent == 0 || s.style.bold)",
)
block = block.replace(
    "indentText(s.indent + (doc.indentContent ? 1 : 0))",
    "indentText(effectiveIndent + (doc.indentContent ? 1 : 0))",
)
block = block.replace(
    "indentText(s.indent)",
    "indentText(effectiveIndent)",
)

# Add hidden-value behavior after local template builders exist.
needle = """      if (sectionChildren.isNotEmpty) {
"""
insert = """      // A structured value may be hidden from the PDF while its narrative
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
"""
block = replace_one(block, needle, insert, "PDF hidden structured value note behavior")

# Parent/section-as-field: append note before child sections.
old = """        for (final child in sectionChildren) {
          walk(child);
        }
        return;
"""
new = """        if (noteText.isNotEmpty) {
          out.add(makeBlockContentTemplate(noteText));
        }

        for (final child in sectionChildren) {
          walk(child, treeDepth + 1);
        }
        return;
"""
block = replace_one(block, old, new, "PDF parent optional note + recursive depth")

# Leaf block: note after structured/free text value.
old = """        }
        return;
      }

      if (leafText.isNotEmpty) {
"""
new = """        }

        if (noteText.isNotEmpty) {
          out.add(makeBlockContentTemplate(noteText));
        }
        return;
      }

      if (leafText.isNotEmpty) {
"""
block = replace_one(block, old, new, "PDF block leaf optional note")

# Leaf inline: append note after value/placeholder.
old = """      }
    }

    for (final s in doc.roots) {
      walk(s);
    }
"""
new = """      }

      if (noteText.isNotEmpty) {
        out.add(makeBlockContentTemplate(noteText));
      }
    }

    for (final s in doc.roots) {
      walk(s, 0);
    }
"""
block = replace_one(block, old, new, "PDF inline leaf optional note + root depth")

t = t[:start] + block + t[end:]
updated[p] = t

changed = [rel for rel in FILES if updated[rel] != original[rel]]
if len(changed) != 2:
    die(f"Expected exactly 2 changed files, got {len(changed)}.")

# Write only after all checks succeeded.
for rel in changed:
    (ROOT / rel).write_text(updated[rel], encoding="utf-8")

print("Applied Ripot finishing fixes successfully.")
print("Changed 2 files:")
for rel in changed:
    print(f"  - {rel}")
print("\nNext run:")
print("  dart format lib/features/reports/ui/template_editor_screen.dart lib/features/reports/services/pdf_renderer_service.dart")
print("  flutter analyze")
print("  flutter run -d chrome")
print("\nTest:")
print("  1. Edit-section sheet scrollbar should sit at the outer right edge.")
print("  2. Oesophagus should visibly parent Upper/Middle/Lower oesophagus in PDF.")
print("  3. Optional note should appear under the selected structured value.")
print("  4. With Show value in PDF off, the note should still appear.")
