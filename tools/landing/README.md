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
