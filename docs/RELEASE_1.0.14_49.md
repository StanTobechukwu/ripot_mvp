# Ripot 1.0.14 (49) — prepared update

## Changes
- LinkedIn company-page link supplied by the founder: https://www.linkedin.com/company/ripot-technology/ (landing footer, contact page and template pages).
- Premium and active trial: no saved-final-PDF count cap. Free stays at 10. Device/browser storage remains finite; existing PDFs stay accessible after expiry.
- New approved R source artwork; the release workflow regenerates platform icons.
- support@ripot.app on all landing/legal/contact pages and in the Account sheet.
- Registry linking: suggested identities first, explicit broader search, visible names/IDs/facilities/date, confirmation, extra acknowledgement for uncertain matches, conflicting identifiers blocked, and links owned by another patient rejected (including dated-update source links).
- Four static starter-template pages, a hub, template download/import, copyable blank outlines, copyable public page links and exact web-editor links. Starter structures come from the app codec, not separate hand-maintained copies.

## Release order
1. Review the GitHub check results and generated assets.
2. Build Android/Windows from this branch with the new source icon. Sign the Android bundle with the existing upload key; upload version code 49 to Play Console. Do not change the package name or signing identity.
3. Review the generated web package; deploy to existing ripot-web hosting using its included deployment script.
4. Deploy the generated landing folder using Deploy-Landing.command. The web app update must precede template CTA publication.
5. After Android and Windows 49 are actually available, update the Windows download/version manifest through tools/windows/prepare_landing_download.py with the real release URL/hash. Do not advertise a nonexistent installer.
6. Change the landing future-tense saved-PDF wording to current tense after platform rollout. Existing links currently retain the released Windows 48 installer.

## External listing changes (manual, not submitted by this branch)
App title: Ripot: Clinical Report & PDF
Short description: Create structured clinical reports, signed medical PDFs & procedure logbooks.
Support email: support@ripot.app
Upload the new Play icon and reflect unlimited local Premium PDFs in the full description after release. Screenshots must come from the released app.

## Still needed

- Real demonstration video, reviewed before publication.
- Contributor-published/custom shareable template backend and review controls. The initial library credits Ripot and shares bundled starters only.
- Obstetric/operative templates need content/design review before adding to the starter set.
- Teams backend/subscription, direct web payments, iOS, EMR integrations and certificates remain separate roadmap work. This release does not upload clinical data or claim Teams/compliance certification.

## Existing decisions preserved
Structured-first Records, explicit narrative opt-in, state-aware Add/View/Update Record, durable Registry images, patient/dated fields, separate Logbook, Android and Windows update prompts, aligned colonoscopy preview and demonstration signature.

## Verification
GitHub Actions run 39646495984 verified app source commit 87abb677af82c8bb943f66aa33e90d0afb8fbeb4: analysis completed without errors (lint warnings remain), all app tests passed, launcher icons were generated, exact starter templates exported, static links checked and the release web app compiled. The generated icons and pages are checked into this branch for subsequent builds. A small-screen test covers the Registry picker with the keyboard open.

This is not confirmation of deployment, Play review, Windows installer testing, or a manual browser/device visual review.
