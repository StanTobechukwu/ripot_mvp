#!/usr/bin/env python3
from pathlib import Path
import subprocess, re, sys

ROOT = Path.cwd()

targets = [
    Path("lib/features/reports/services/pdf_renderer_service.dart"),
    Path("lib/features/reports/domain/pdf/pdf_plan_builder.dart"),
]

print("=== RIPOT IMAGE FLOW DIAGNOSTIC ===\n")

try:
    branch = subprocess.check_output(["git","branch","--show-current"], text=True).strip()
except Exception:
    branch = "(unknown)"
print("Branch:", branch)
print("Root:", ROOT)
print()

for p in targets:
    print(f"--- {p} ---")
    if not p.exists():
        print("MISSING")
        continue
    text = p.read_text(encoding="utf-8")
    checks = {
        "planner spillInline assignment":
            "spillInlineImages: spillInline" in text,
        "planner has no attachment pages in inline mode":
            "attachmentPages: const []" in text,
        "renderer page1 horizontal allocation":
            "pageOneReportOverflowImages" in text,
        "renderer continuation overflow rows":
            "_reportImageOverflowRows(" in text,
        "renderer left aligned rows":
            "mainAxisAlignment: pw.MainAxisAlignment.start" in text,
        "renderer horizontal row fit helper":
            "_horizontalImageRowsThatFit(" in text,
        "OLD report-overflow-to-attachments path still present":
            "inlineToAttachments" in text,
        "OLD planner attachmentImages variable still present":
            "final attachmentImages = doc.images.skip" in text,
    }
    for k, v in checks.items():
        print(f"{'YES' if v else 'NO ':3}  {k}")
    print()

print("=== SEARCHING WHOLE LIB/ FOR CONFLICTING IMAGE FLOW CODE ===")
patterns = [
    "Image Attachments",
    "inlineToAttachments",
    "attachmentImages = doc.images.skip",
    "spillInlineImages",
    "PdfPlanBuilder",
    "generatePdfBytes",
]

for pat in patterns:
    print(f"\nPATTERN: {pat}")
    hits = []
    for f in Path("lib").rglob("*.dart"):
        try:
            text = f.read_text(encoding="utf-8")
        except Exception:
            continue
        if pat in text:
            lines = [i+1 for i,l in enumerate(text.splitlines()) if pat in l]
            hits.append((str(f), lines[:8]))
    if not hits:
        print("  no hits")
    else:
        for f, lines in hits:
            print(f"  {f}: {lines}")

print("\n=== GIT DIFF SUMMARY ===")
try:
    print(subprocess.check_output(["git","diff","--stat"], text=True))
except Exception as e:
    print("Could not read git diff:", e)

print("\n=== EXPECTED ===")
print("For inline/report image mode:")
print("  - pdf_plan_builder.dart must have spillInlineImages: spillInline")
print("  - pdf_plan_builder.dart must have attachmentPages: const []")
print("  - pdf_renderer_service.dart must NOT have inlineToAttachments")
print("  - renderer must have pageOneReportOverflowImages and _reportImageOverflowRows")
print()
print("Paste this entire diagnostic output back into ChatGPT.")
