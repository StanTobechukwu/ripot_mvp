# Release hardening — 2026-10-25

Base: `codex/template-contributions-20261023`. Work on this branch only; do not merge or deploy until acceptance tests pass.

## Data safety
- On first successful web report save, show a dismissible explanation that browser storage is local and may be cleared. Offer **Back up to device** and **Not now**. Never imply PDF export is a full backup.
- After five saved reports without a backup, offer a backup prompt. After 20 additional new/modified records since the last successful backup, remind again; do not prompt on every save.
- Backups must use the existing encrypted backup format, with no patient data in analytics. Show backup success only after the file is actually saved, and display last successful backup date.
- Verify backup/restore for reports, registry, logbook, templates, images and links; warn clearly about any unsupported content.
- Do not claim a downloaded backup is safely stored until the browser confirms completion as far as its API permits.

## PDF
- Free tier: discreet `Generated with Ripot | ripot.app` footer, outside clinical content; Premium and eligible trial: no footer.
- Test multi-page PDFs with long findings, image grids and signatures, both PDF viewing and printed output. Verify no collisions or clipped content.
- Confirm the Premium letterhead placeholder appears in preview UI only, never in a finalized PDF.

## Templates and community
- Existing built-in deep links and approved versioned links must work; old approved versions must remain resolvable or give an explicit compatibility notice.
- Require explicit review and patient-data checks before publishing community templates; hide empty/loading-only community sections.
- Validate template imports, malformed payload rejection, user-confirmed copy, mobile and offline fallback.
- Check downloaded template formatting, previews, sitemap and deep-link destinations.

## Landing, entitlement and analytics
- Remove stale promises about future PDF limits if already shipped.
- Ensure web trial messaging does not promise unavailable payment checkout.
- Validate CTAs, editor screenshots and support/LinkedIn links.
- Measure only non-patient identifying funnel events; ensure consent requirements.

## Release gates
1. Static and automated tests green.
2. Flutter web build and Android build verified.
3. Browser smoke test on mobile and desktop.
4. Backup/restore round-trip with synthetic data.
5. PDF visual/print regression on free, trial and Premium.
6. Staging web then landing deployment; production only after approval.
7. Record exact commit, build version and deployment URLs.

Status: checklist committed; implementation and end-to-end verification remain outstanding until evidenced by tests.
