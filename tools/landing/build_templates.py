"""Build indexable pages from the exact starter templates exported by Ripot."""
import html, json, hashlib, shutil
from template_page import page_body
from pathlib import Path
from xml.etree import ElementTree as ET
ROOT = Path(__file__).resolve().parents[2]
PUBLIC = ROOT / 'landing/y'
CATALOG = [
 ('colonoscopy-report-template', 'Colonoscopy report template', 'Endoscopy', 'Record bowel preparation, segmental findings, interventions and impressions in a reusable colonoscopy report.'),
 ('upper-gi-endoscopy-report-template', 'Upper GI endoscopy report template', 'Endoscopy', 'An OGD / EGD reporting structure covering indication, sedation, anatomical findings, interventions and impression.'),
 ('abdominal-ultrasound-report-template', 'Abdominal ultrasound report template', 'Ultrasound', 'A reusable abdominopelvic ultrasound structure for organ findings, measurements and impression.'),
 ('echocardiogram-report-template', 'Echocardiogram report template', 'Cardiology', 'A 2D echocardiography reporting structure for chamber measurements, function, valve findings and impression.'),
]
SEO = {
 'colonoscopy-report-template': ('Colonoscopy Report Template – Findings, Bowel Prep & PDF', 'Preview a structured colonoscopy report template with bowel preparation, segmental findings and interventions. Copy a blank outline or open it in Ripot Web.'),
 'upper-gi-endoscopy-report-template': ('Upper GI Endoscopy Report Template – OGD / EGD & PDF', 'Explore an upper GI endoscopy (OGD / EGD) reporting template with oesophagus, stomach, duodenum and intervention sections. Open it in Ripot Web.'),
 'abdominal-ultrasound-report-template': ('Abdominal Ultrasound Report Template – Organs & Measurements', 'Use a structured abdominal ultrasound report template for liver, gallbladder, kidneys and other organs. Preview fields and open it in Ripot Web.'),
 'echocardiogram-report-template': ('Echocardiogram Report Template – 2D Echo Measurements & PDF', 'Preview a 2D echocardiogram report template with chamber measurements, LVEF, Doppler and valve findings. Open the structured editor in Ripot Web.'),
}
EXTRA = json.loads((ROOT/'tools/landing/additional_catalog.json').read_text())
for entry in EXTRA:
 CATALOG.append((entry['slug'], entry['name']+' template', entry['specialty'], entry['description']))
 SEO[entry['slug']] = (entry['name']+' Template | Editable Report & PDF', entry['description'])
REFERENCES = {entry['slug']:entry['references'] for entry in EXTRA}
e = html.escape
CSS = (ROOT/'tools/landing/templates.css').read_text()
SCRIPT = (ROOT/'tools/landing/templates.js').read_text()
def shell(title,desc,path,body):
 return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{e(title)} | Ripot</title><meta name="description" content="{e(desc)}"><link rel="canonical" href="https://ripot.app{path}"><link rel="icon" href="/images/ripot-icon.png"><link rel="stylesheet" href="/templates/templates.css"><meta property="og:title" content="{e(title)}"><meta property="og:description" content="{e(desc)}"><meta property="og:url" content="https://ripot.app{path}"></head><body><header><a class="brand" href="/"><img src="/images/ripot-icon.png" alt="">Ripot</a><nav aria-label="Main"><a href="/templates/">Templates</a><a href="/#download">Get Ripot</a><a href="/contact.html">Support</a></nav></header><main>{body}</main><footer><p>Ripot · Smarter Clinical Reporting</p><nav><a href="mailto:support@ripot.app">support@ripot.app</a><a href="/privacy.html">Privacy</a><a href="/terms.html">Terms</a><a href="https://www.linkedin.com/company/ripot-technology/" target="_blank" rel="noopener noreferrer">Follow Ripot on LinkedIn</a></nav><p class="note">A documentation tool, not a substitute for clinical judgement.</p></footer><script src="/templates/templates.js" defer></script><script src="/templates/community.js" defer></script></body></html>'''
def walk(nodes,depth=0):
 for n in nodes:
  if n.get('type')=='section':
   yield (n.get('title',''),depth,n.get('unit',''))
   yield from walk(n.get('children',[]),depth+1)
def card(item):
 slug,title,specialty,desc=item
 return f'<article class="card"><span class="eyebrow">{e(specialty)}</span><h2><a href="/templates/{slug}/">{e(title)}</a></h2><p>{e(desc)}</p><p class="note">Contributor: Ripot · Starter template</p><a href="/templates/{slug}/">Preview and use →</a></article>'
def main():
 out=PUBLIC/'templates';out.mkdir(exist_ok=True)
 (out/'templates.css').write_text(CSS)
 (out/'templates.js').write_text(SCRIPT)
 shutil.copyfile(ROOT/'tools/landing/community.js', out/'community.js')
 (out/'community.html').write_text(shell('Community reporting template','Preview an approved community reporting structure and use it in Ripot.','/templates/community.html','<p id="community-status" role="status">Loading template…</p><section id="community-preview"></section><a href="/templates/">Back to all templates</a>'))
 (out/'index.html').write_text(shell('Clinical report templates','Browse endoscopy, ultrasound, cardiology and surgical report structures. Preview, download or open a template in Ripot.','/templates/', '<span class="eyebrow">The Ripot template library</span><h1>A clear starting point for your next report.</h1><p class="lead">Choose a specialty, explore the fields and make the report your own.</p><p>Preview the reporting templates, download a printable PDF, or open an editable template in Ripot. Blank forms and clearly labelled fictional examples are available separately.</p><div class="cards">'+''.join(map(card,CATALOG))+'</div><section><h2>From the Ripot community</h2><p id="community-status" role="status">Loading approved contributions…</p><div id="community-templates" class="cards"></div></section><section class="card"><h2>Have a useful reporting structure?</h2><p>Submit a patient-free template with your specialty and contributor credit. Track feedback in My submissions. Only reviewed and approved structures appear publicly.</p><div class="actions"><a class="button" href="https://ripot-web.web.app/?templateLibrary=contribute">Contribute a template</a><a class="button secondary" href="https://ripot-web.web.app/?templateLibrary=browse">Browse in Ripot</a></div></section>'))
 manifest=[]
 for item in CATALOG:
  slug,title,specialty,desc=item
  seo_title,seo_desc=SEO[slug]
  source=out/'downloads'/f'{slug}.ripottemplate.json'
  raw=source.read_bytes()
  version=hashlib.sha256(raw).hexdigest()[:16]
  version_dir=out/'catalog'/slug
  version_dir.mkdir(parents=True,exist_ok=True)
  version_file=version_dir/f'{version}.ripottemplate.json'
  version_file.write_bytes(raw)
  manifest.append({'slug':slug,'version':version,'name':title,'specialty':specialty,'contributor':'Ripot','status':'approved','url':f'/templates/catalog/{slug}/{version}.ripottemplate.json','sha256':hashlib.sha256(raw).hexdigest()})
  payload=json.loads(raw)
  template=payload['template']
  body=page_body(slug,title,specialty,desc,template,version,''.join(card(i) for i in sorted((i for i in CATALOG if i!=item), key=lambda i:i[2]!=specialty)[:4]))
  if slug in REFERENCES:
   body += '<section class="note"><h2>Documentation references</h2><p>Adapt these fields to your examination and local protocol. These editable structures have not undergone independent clinical validation; no organisation listed here endorses Ripot.</p><ul>'+''.join(f'<li><a href="{e(url,quote=True)}" target="_blank" rel="noopener noreferrer">{e(label)}</a></li>' for label,url in REFERENCES[slug])+'</ul></section>'
  dest=out/slug;dest.mkdir(exist_ok=True)
  (dest/'index.html').write_text(shell(seo_title,seo_desc,'/templates/'+slug+'/',body))
 (out/'catalog'/'manifest.json').write_text(json.dumps({'schemaVersion':1,'templates':manifest},indent=2)+'\n')
 sitemap=PUBLIC/'sitemap.xml';ns='http://www.sitemaps.org/schemas/sitemap/0.9';ET.register_namespace('',ns);tree=ET.parse(sitemap);root=tree.getroot()
 existing={u.find('{'+ns+'}loc').text for u in root}
 for path in ['/templates/']+['/templates/'+i[0]+'/' for i in CATALOG]:
  if 'https://ripot.app'+path not in existing:
   entry=ET.SubElement(root,'{'+ns+'}url');ET.SubElement(entry,'{'+ns+'}loc').text='https://ripot.app'+path
   ET.SubElement(entry,'{'+ns+'}lastmod').text='2026-10-25'
 tree.write(sitemap,encoding='utf-8',xml_declaration=True)
 print(f'Built hub and {len(CATALOG)} template pages with app-rendered PDF previews and labelled downloads.')
if __name__=='__main__':main()
