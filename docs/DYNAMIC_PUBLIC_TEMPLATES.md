# Dynamic public templates — implementation contract

Status: design and integration plan; NOT deployed. Do not claim runtime support until tests pass.

## Goal
Allow Ripot Web (and later Android deep links) to open newly approved patient-free reporting structures from ripot.app without a new app release for each specialty. Existing four built-in links remain supported.

## Publication format
- Stable slug, immutable version, title, specialty, attribution, reviewed status and source.
- HTTPS-only, same-origin `https://ripot.app/templates/catalog/<slug>/<version>.ripottemplate.json`.
- Published JSON uses the existing Ripot template export envelope, including schema/version metadata; never run code from a template.
- Public index exposes ONLY explicitly approved and clinically reviewed versions. Keep unreviewed submissions private.
- Generate public SEO page, downloadable export, manifest entry and sitemap atomically from the same approved version.
- Preserve historic approved versions for existing shared links; never silently replace personal templates.

## Web opening
- Accept `?template=<slug>&version=<version>` for public templates and retain existing built-in slug resolver as a fallback.
- Resolve slug only through a published allowlist manifest; no arbitrary URLs or redirect targets.
- Fetch manifest and versioned payload with size/time limits, no credentials, no patient data in URLs, no persistent personal-data analytics.
- Validate JSON envelope, supported schema, node types, maximum depth/count, unique node IDs, input options, units and conditional references before showing a preview.
- Explicitly show template source, version and contributor; require user confirmation to import.
- Import into an isolated new report or user template copy; never overwrite existing reports or user templates.
- Offline mode: built-ins and previously imported local templates remain available; show a clear offline error for uncached remote templates.

## Analytics and privacy
- Track aggregate page view, template-open click, successful import, report-start and completed-report events only after appropriate privacy configuration and consent where required.
- Use non-identifying template slug/version and event names. Do not send patient identifiers, findings, reports, images, clinician names or free text.
- UTM parameters are attribution labels, not evidence of completed reports.

## Acceptance tests
1. Existing four built-in deep links still work.
2. A newly published approved specialty template opens in Ripot Web without recompiling the app.
3. Unknown, unapproved, malformed, oversized, redirected or unsupported versions are rejected safely.
4. Import never overwrites an existing user template or report.
5. Links are usable on mobile and desktop; app works offline with existing templates.
6. Analytics contain no clinical or patient content; conversion counts reflect real events.
7. Clinical review approves obstetric ultrasound and surgical operative-note fields before their public manifest entries become visible.

## Rollout
1. Implement safe manifest/loader and Flutter import integration.
2. Add integration and security tests.
3. Publish approved obstetric and operative-note JSON through the same export pipeline.
4. Regenerate landing pages, verify sample previews and SEO, test on staging.
5. Deploy web before landing; add Android deep-link support in a subsequent signed release.
