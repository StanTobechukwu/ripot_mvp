"""Accessible landing previews and clipboard formats from the published structure."""
import html,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
e=html.escape

def outline(template, values=None):
    example=values is not None
    text=[template['name'].upper()]
    rich=[f"<h1>{e(template['name'])}</h1>"]
    if example:
        text += ['FICTIONAL EXAMPLE - NOT FOR CLINICAL USE', 'Illustrative content only; not a clinical reference.']
        rich += ['<p><strong>FICTIONAL EXAMPLE - NOT FOR CLINICAL USE</strong><br>Illustrative content only; not a clinical reference.</p>']
    patient='FICTIONAL PATIENT' if example else '________________'
    identifier='DEMO-001' if example else '________________'
    date='01 January 2026' if example else '________________'
    text += ['',f'Patient: {patient}',f'Identifier: {identifier}',f'Date: {date}','']
    rich += [f'<p>Patient: {patient}<br>Identifier: {identifier}<br>Date: {date}</p>']
    def walk(nodes, depth=0):
        for n in nodes:
            if n.get('type')!='section':continue
            children=[c for c in n.get('children',[]) if c.get('type')=='section']
            title=n.get('title','')
            if example and n.get('conditionalParentSectionId'):
                parent=values.get(n['conditionalParentSectionId'],'')
                if n.get('conditionalEquals','').casefold() not in [v.strip().casefold() for v in parent.split(';')]:continue
            if children:
                text.extend(['',title.upper() if depth==0 else title])
                rich.append(f'<h{min(depth+2,4)}>{e(title)}</h{min(depth+2,4)}>')
                walk(children,depth+1)
            else:
                unit=n.get('unit','')
                label=title+(f' ({unit})' if unit else '')
                value=values[n['id']] if example else '________________'
                # Don't print units after unmeasured example values.
                line=f'{label}: {value}'
                if depth==0:text.append('')
                text.append(line)
                rich.append(f'<p><strong>{e(label)}:</strong> {e(value)}</p>')
    walk(template['roots'])
    clinician='DEMONSTRATION ONLY - NOT SIGNED' if example else '________________'
    text.extend(['',f'Clinician: {clinician}']+([] if example else ['Signature: ________________']))
    if example:text.append('FICTIONAL EXAMPLE - NOT FOR CLINICAL USE')
    rich.append(f'<p>Clinician: {clinician}</p>')
    return '\n'.join(text).strip()+'\n',''.join(rich)

def page_body(slug,title,specialty,desc,template,version,other_cards):
    manifest=json.loads((ROOT/'landing/y/templates/previews/manifest.json').read_text())
    variants={key:manifest[f'{slug}-{key}'] for key in ('blank','example')}
    samples=json.loads((ROOT/'tools/landing/example_values.json').read_text())[slug]
    plain,rich=outline(template)
    sample,sample_rich=outline(template,samples)
    directory=ROOT/'landing/y/templates/downloads'
    (directory/f'{slug}-outline.txt').write_text(plain)
    blank=variants['blank']; pages=len(blank['pages'])
    details=[]
    def fields(nodes):
        for n in nodes:
            if n.get('type')=='section':
                details.append(e(n['title']))
                fields(n.get('children',[]))
    fields(template['roots'])
    return f'''<a href="/templates/">← All templates</a>
<p class="eyebrow">{e(specialty)} · Contributor: Ripot</p>
<h1>{e(title)}</h1><p class="lead">{e(desc)}</p>
<div class="actions"><a class="button" data-adoption-event="editor_open" data-template="{slug}" href="https://ripot-web.web.app/?template={slug}&amp;version={version}&amp;utm_source=ripot_templates&amp;utm_medium=referral&amp;utm_campaign=template_library">Use in Ripot Web →</a><a id="download-pdf" class="button secondary" data-adoption-event="pdf_download" data-template="{slug}" href="/templates/previews/{blank['pdf']}" download>Download blank PDF</a></div>
<p class="note">Open an editable report in your browser, or download a printable PDF. The working template starts without clinical findings.</p>
<div class="preview-layout">
<section class="preview-card" data-report-viewer data-title="{e(template['name'],quote=True)}" aria-label="Report preview">
<div class="preview-heading"><h2>See the report</h2><div class="variant-tabs" role="group" aria-label="Choose preview"><button type="button" data-variant="blank" aria-pressed="true">Blank template</button><button type="button" data-variant="example" aria-pressed="false">Fictional example</button></div><p class="preview-note" data-preview-note>Actual PDF preview. Tap the page to enlarge. Complete only applicable fields.</p></div>
<div class="page-frame"><button class="page-zoom" type="button" data-enlarge aria-label="Enlarge report preview"><img data-page-image src="/templates/previews/{blank['pages'][0]}" alt="{e(template['name'])} blank template, page 1 of {pages}" width="1061" height="1500" fetchpriority="high"></button></div>
<div class="preview-controls"><button type="button" data-previous aria-label="Previous preview page" disabled>← Previous</button><span data-page-count aria-live="polite">Page 1 of {pages}</span><button type="button" data-next aria-label="Next preview page" {'disabled' if pages==1 else ''}>Next →</button></div></section>
<aside class="preview-aside"><h2>A report you can make your own.</h2><p>Start with this structure in Ripot. Enter your observations, adapt the fields and review the PDF before sharing.</p><ul><li><strong>Editable sections</strong><br>Keep the structure and customise it for your workflow.</li><li><strong>Your own findings</strong><br>Fictional examples are shown separately and never inserted into your new report.</li><li><strong>Preview matches the PDF</strong><br>These pages were generated with Ripot’s report renderer. The PDF download is the document shown here.</li></ul><p class="note">The example demonstrates layout, not clinical guidance or a verified normal report. Available app features and plan limits are shown in Ripot.</p>
<details class="import-options"><summary>Import this template into Ripot</summary><p class="import-note">Already have Ripot? Download the editable template file, then choose <strong>Templates → Import</strong> inside the app. This file is for app import; use the PDF above for reading or printing.</p><a class="button secondary" href="/templates/downloads/{slug}.ripottemplate.json" download data-adoption-event="template_download" data-template="{slug}">Download Ripot import file</a></details></aside></div>
<section class="outline-box"><h2>Copy a clean report outline</h2><p>Clear headings and blank fields, ready to paste. Compatible editors also receive formatted text.</p><button type="button" data-copy="outline">Copy report outline</button><p class="copy-status" data-copy-status role="status"></p><details><summary>Read the blank outline</summary><pre id="outline">{e(plain)}</pre></details><div id="outline-rich" hidden>{rich}</div></section>
<section class="outline-box"><h2>Fictional example text</h2><p class="note">A demonstration of the layout using invented observations. It is not a patient report, normal-report default or clinical reference.</p><button class="secondary" type="button" data-copy="example">Copy fictional example</button><p class="copy-status" data-copy-status role="status"></p><details><summary>Read the fictional example</summary><pre id="example">{e(sample)}</pre></details><div id="example-rich" hidden>{sample_rich}</div></section>
<section><details><summary>View all included fields</summary><ul class="fields">{''.join('<li>'+f+'</li>' for f in details)}</ul></details></section>
<section><h2>Explore other templates</h2><div class="cards">{other_cards}</div></section>
<dialog class="zoom-dialog" id="report-zoom" aria-label="Enlarged report preview"><div class="zoom-toolbar"><strong data-zoom-title>Report preview</strong><button class="secondary" type="button" data-zoom-toggle>Zoom in</button><button type="button" data-close>Close preview</button></div><div class="zoom-body"><img alt="Enlarged report preview"></div><p class="zoom-help">Zoom in to read the text. On a phone, drag to move around the enlarged page.</p></dialog>
<script id="preview-data" type="application/json">{json.dumps(variants).replace('<',chr(92)+'u003c')}</script>'''
