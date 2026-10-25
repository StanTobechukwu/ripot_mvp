#!/usr/bin/env python3
"""
Ripot template-save responsiveness + Navigator lock fix.

Run from ripot_mvp root on branch:
  ripot-structured-inputs-image-flow

Changes:
1. Template saves remain local-first and return immediately.
   Premium cloud structure sync runs asynchronously instead of blocking Save.
2. Template-editor exit pops are scheduled after the current frame,
   avoiding Navigator !_debugLocked assertions after closing the save dialog.
"""

from pathlib import Path
import subprocess
import sys

ROOT = Path.cwd()
FILES = [
    "lib/features/reports/data/templates_repository.dart",
    "lib/features/reports/ui/template_editor_screen.dart",
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
        die(f"Missing {rel}. Run this from the project root.")

try:
    branch = subprocess.check_output(["git", "branch", "--show-current"], text=True).strip()
except Exception:
    branch = ""

if branch and branch != "ripot-structured-inputs-image-flow":
    die(f"Current branch is '{branch}'. Switch to ripot-structured-inputs-image-flow first.")

original = {rel: (ROOT / rel).read_text(encoding="utf-8") for rel in FILES}
updated = dict(original)

# ----------------------------------------------------------
# 1) TemplatesRepository: local save should not await cloud.
# ----------------------------------------------------------
p = "lib/features/reports/data/templates_repository.dart"
t = updated[p]

# dart:async gives us unawaited().
if "import 'dart:async';" not in t:
    t = replace_one(
        t,
        "import 'dart:convert';",
        "import 'dart:async';\nimport 'dart:convert';",
        "templates_repository add dart:async",
    )

t = replace_one(
    t,
    """    await _syncStructureOnlyTemplate(
      template,
    );
""",
    """    // Local persistence is the Save operation. Cloud structure sync is
    // best-effort and must never make the user wait or make Save appear stuck.
    unawaited(
      _syncStructureOnlyTemplate(
        template,
      ),
    );
""",
    "templates_repository non-blocking cloud sync",
)

updated[p] = t

# ----------------------------------------------------------
# 2) TemplateEditor: defer route pop until Navigator unlocks.
# ----------------------------------------------------------
p = "lib/features/reports/ui/template_editor_screen.dart"
t = updated[p]

anchor = """  Future<void> _handleAttemptedExit(BuildContext context) async {
"""
helper = """  void _popEditorSafely(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      }
    });
  }

  Future<void> _handleAttemptedExit(BuildContext context) async {
"""
t = replace_one(t, anchor, helper, "template editor safe-pop helper")

# Only replace pops inside _handleAttemptedExit, not dialog pops elsewhere.
start = t.find("  Future<void> _handleAttemptedExit(BuildContext context) async {")
end = t.find("  Future<String?> _promptText(", start)
if start == -1 or end == -1:
    die("Could not isolate _handleAttemptedExit.")

block = t[start:end]
count = block.count("Navigator.of(context).pop();")
if count != 3:
    die(f"_handleAttemptedExit expected 3 editor pops, found {count}.")
block = block.replace("Navigator.of(context).pop();", "_popEditorSafely(context);")
t = t[:start] + block + t[end:]

updated[p] = t

# Write only after every check succeeds.
changed = [rel for rel in FILES if updated[rel] != original[rel]]
if len(changed) != 2:
    die(f"Expected 2 changed files, got {len(changed)}.")

for rel in changed:
    (ROOT / rel).write_text(updated[rel], encoding="utf-8")

print("Applied template-save responsiveness + Navigator lock fix successfully.")
print("Changed 2 files:")
for rel in changed:
    print(f"  - {rel}")
print("\nNext run:")
print("  dart format lib/features/reports/data/templates_repository.dart lib/features/reports/ui/template_editor_screen.dart")
print("  flutter analyze")
print("  flutter run -d chrome")
print("\nDo not commit until Save + Back/Save-prompt behavior has been tested.")
