# Public report previews

Run these commands from the repository root, not from `landing/`:

```sh
flutter test tools/export_template_previews.dart
python3 tools/landing/render_previews.py
python3 tools/landing/build_templates.py
python3 tools/landing/verify.py
```

Rendering requires Poppler's `pdftoppm`. The **Export template PDF previews**
GitHub workflow runs the first two commands and supplies a downloadable artifact.
Commit its PDFs, JPEG pages and manifest together before rebuilding the pages.

The PDF exporter reads the published `.ripottemplate.json` files without changing
them, then uses the production `PdfRendererService` to produce a blank form and a
clearly labelled fictional example. The landing-page JPEGs come from those exact
PDFs; the manifest records the download hashes and page order. Blank printed forms
include conditional fields so they remain available for handwriting. Filled
examples respect the template's conditional fields. Preview content never changes
the imported template or prefills the live editor.

`example_values.json` holds deliberately authored fictional examples for every
leaf field. They illustrate layout, not clinical guidance or approved normal
findings. Any new public template requires review of its structure and examples.

`templates.css`, `templates.js` and `template_page.py` are the source for the static
pages. Edit these sources, then rebuild; do not edit generated HTML directly.
The browser smoke test checks mobile/desktop layout, actual PDF downloads, page
navigation, zoom, rich/plain clipboard fallbacks and import-file integrity:

```sh
node tools/landing/smoke_template_previews.cjs
```

It requires Playwright and Chrome, and runs in the main CI workflow. The packaged
`Deploy-Landing.command` deploys the generated pages and all preview assets to the
separate `ripot-landing` Firebase project. Deploying the web app alone does not
update these public pages.


## Expanded catalogue (25 October 2026)

The four bundled starters retain their published payload bytes. Eleven additional
catalogue-only templates are authored in `additional_templates.py`: flexible
sigmoidoscopy, obstetric/morphology ultrasound, pelvic/transvaginal ultrasound,
thyroid/neck ultrasound, renal/renal artery Doppler, Holter, ambulatory blood
pressure, general operation note, caesarean section, appendectomy and wound
 debridement/minor operation. Holter and ABPM are separate investigations.

From the repository root:

```sh
python3 tools/landing/export_additional_templates.py
flutter test tools/export_template_previews.dart
python3 tools/landing/render_previews.py
python3 tools/landing/build_templates.py
python3 tools/landing/verify.py
```

The PDF exporter uses the production renderer and keeps short sections and the
closing signature together for the added printable forms. Keep the existing
four templates' committed PDF bytes when importing a CI preview artifact; merge
only the new template entries into the preview manifest. Before publishing,
inspect both blank and fictional variants, including every continuation page.

Fixtures are layout demonstrations, not verified normal reports. The imports
contain no findings, diagnosis defaults, risk thresholds, automatic TI-RADS
scores or automated obstetric growth interpretation. Reference links describe
relevant documentation resources; no external society endorses these templates.
Clinicians should adapt the fields and review suitability for their service.

The hub groups templates by specialty. Each new page has a canonical URL,
description, sitemap entry, actual PDF preview, blank/example downloads, a clean
copyable outline and a versioned link into the web editor. SEO traffic is not
guaranteed and no search-volume claims are published.
