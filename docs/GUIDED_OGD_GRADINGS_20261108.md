# Guided OGD grading update — 8 November 2026

The guided OGD template now exposes reference help for Los Angeles, Prague C/M,
Forrest, Sarin, Baveno size/red signs, EREFS components and optional Paris
morphology. Choices remain specific to the relevant repeatable finding and
start blank. Guides and template options share the bundled JSON reference.

EREFS uses the ESGE 2025 component definitions with binary furrows, without
an automatic total. No risk flags, surveillance intervals, treatment suggestions
or MDCalc integration are added. Prague C/M are joined only when both are finite,
non-negative and M >= C. Partial/inconsistent entries remain visible separately
and trigger the existing pre-export review prompt. Draft saving stays available.

Preserved: collapsed additional procedure details, separate safety choices,
medications with dose/unit/route, independent findings, anatomical PDF order,
one biopsy summary, images, editable descriptions, separate Registry/research
configuration and old saved reports/catalogue versions.

The landing page and guided-template page name the classifications, retain
Dr Nduaguba Tobechukwu Stanley as clinical contributor, and display the update
date. This date records a template update, not independent clinical validation.

Release candidate: 1.0.27+62. Version 1.0.26+61 remains reserved for the separate
Microsoft billing work. This branch is based on the Windows landing PR, not the
billing candidate; subscription checkout remains disabled. Merge the two changes
deliberately before the next combined Store release.

Deployment order: verified web build, then landing/template catalogue. The new
fields remain readable in compatible older clients, but installed Android and
Windows clients need their next app update for guide buttons and Prague checks.
No backend deployment or data migration is required for this template update.

Validation: the dedicated workflow runs old guided-workflow tests, new grading
tests, copy/PDF assertions, preview generation and a production web build. The
landing workflow checks downloads, disclosures and mobile/desktop layout.
Successful CI is a software check, not clinical validation.
