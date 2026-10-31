"""Build indexable pages from the published templates exported by Ripot."""
import html, json, hashlib, shutil
from template_page import page_body
from template_guides import GUIDES, BASE_REFERENCES
from pathlib import Path
from xml.etree import ElementTree as ET
ROOT = Path(__file__).resolve().parents[2]
PUBLIC = ROOT / 'landing/y'
CATALOG = [
 ('colonoscopy-report-template', 'Colonoscopy report template', 'Gastroenterology', 'Record bowel preparation, segmental findings, interventions and impressions in a reusable colonoscopy report.'),
 ('upper-gi-endoscopy-report-template', 'Upper GI endoscopy report template', 'Gastroenterology', 'An OGD / EGD reporting structure covering indication, sedation, anatomical findings, interventions and impression.'),
 ('abdominal-ultrasound-report-template', 'Abdominal ultrasound report template', 'Radiology', 'A reusable abdominopelvic ultrasound structure for organ findings, measurements and impression.'),
 ('echocardiogram-report-template', 'Echocardiogram report template', 'Cardiology', 'A 2D echocardiography reporting structure for chamber measurements, function, valve findings and impression.'),
]
SEO = {
 'colonoscopy-report-template': ('Colonoscopy Report Template – Findings, Bowel Prep & PDF', 'Preview a structured colonoscopy report template with bowel preparation, segmental findings and interventions. Copy a blank outline or open it in Ripot Web.'),
 'upper-gi-endoscopy-report-template': ('Upper GI Endoscopy Report Template – OGD / EGD & PDF', 'Explore an upper GI endoscopy (OGD / EGD) reporting template with oesophagus, stomach, duodenum and intervention sections. Open it in Ripot Web.'),
 'abdominal-ultrasound-report-template': ('Abdominal Ultrasound Report Template – Organs & Measurements', 'Use a structured abdominal ultrasound report template for liver, gallbladder, kidneys and other organs. Preview fields and open it in Ripot Web.'),
 'echocardiogram-report-template': ('2D Echo Report Template & PDF', 'Preview a 2D echocardiogram report template with chamber measurements, LVEF, Doppler and valve findings. Open the structured editor in Ripot Web.'),
}
EXTRA = json.loads((ROOT/'tools/landing/additional_catalog.json').read_text())
DISPLAY_NAMES = {
 'structured-upper-gi-endoscopy-report-template': 'Upper GI endoscopy report template — guided',
 'histopathology-report-template': 'Histopathology report template',
 'flexible-sigmoidoscopy-report-template': 'Flexible sigmoidoscopy report template',
 'obstetric-ultrasound-report-template': 'Obstetric ultrasound report template',
 'pelvic-transvaginal-ultrasound-report-template': 'Pelvic and transvaginal ultrasound report template',
 'thyroid-neck-ultrasound-report-template': 'Thyroid and neck ultrasound report template',
 'renal-artery-doppler-report-template': 'Renal ultrasound and renal artery Doppler report template',
 'holter-monitor-report-template': 'Holter monitor report template',
 'ambulatory-blood-pressure-report-template': 'Ambulatory blood pressure report template',
 'general-surgical-operation-note-template': 'General surgical operation note template',
 'caesarean-section-operation-note-template': 'Caesarean section operation note template',
 'appendectomy-operation-note-template': 'Appendectomy operation note template',
 'wound-debridement-minor-operation-note-template': 'Wound debridement operation note template',
}
for entry in EXTRA:
 CATALOG.append((entry['slug'], DISPLAY_NAMES[entry['slug']], entry['specialty'], entry['description']))
 SEO[entry['slug']] = (DISPLAY_NAMES[entry['slug']]+' | Editable & PDF', entry['description'])
REFERENCES = {**BASE_REFERENCES, **{entry['slug']:entry['references'] for entry in EXTRA}}
e = html.escape
CSS = (ROOT/'tools/landing/templates.css').read_text()
SCRIPT = (ROOT/'tools/landing/templates.js').read_text()
def shell(title,desc,path,body):
 return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{e(title)} | Ripot</title><meta name="description" content="{e(desc)}"><link rel="canonical" href="https://ripot.app{path}"><link rel="icon" href="/images/ripot-icon.png"><link rel="stylesheet" href="/templates/templates.css"><meta property="og:title" content="{e(title)}"><meta property="og:description" content="{e(desc)}"><meta property="og:url" content="https://ripot.app{path}"><meta property="og:image" content="https://ripot.app/images/ripot-report-share.jpg"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="og:image:alt" content="A finished Ripot report with fictional demonstration details"><meta name="twitter:card" content="summary_large_image"><meta name="twitter:image" content="https://ripot.app/images/ripot-report-share.jpg"></head><body><header><a class="brand" href="/"><img src="/images/ripot-icon.png" alt="">Ripot</a><nav aria-label="Main"><a href="/templates/">Templates</a><a href="/#download">Get Ripot</a><a href="/contact.html">Support</a></nav></header><main>{body}</main><footer><p>Ripot · Smarter Clinical Reporting</p><nav><a href="mailto:support@ripot.app">support@ripot.app</a><a href="/privacy.html">Privacy</a><a href="/terms.html">Terms</a><a href="https://www.linkedin.com/company/ripot-technology/" target="_blank" rel="noopener noreferrer">Follow Ripot on LinkedIn</a></nav><p class="note">A documentation tool, not a substitute for clinical judgement.</p></footer><script src="/templates/template-funnel.js" defer></script><script src="/templates/templates.js" defer></script><script src="/templates/community.js" defer></script></body></html>'''
def walk(nodes,depth=0):
 for n in nodes:
  if n.get('type')=='section':
   yield (n.get('title',''),depth,n.get('unit',''))
   yield from walk(n.get('children',[]),depth+1)
def card(item):
 slug,title,specialty,desc=item
 return f'<article class="card"><span class="eyebrow">{e(specialty)}</span><h2><a href="/templates/{slug}/">{e(title)}</a></h2><p>{e(desc)}</p><p class="note">Contributor: Ripot · Starter template</p><a href="/templates/{slug}/">Preview and use →</a></article>'
def catalog_sections():
 groups = [
  ('endoscopy', 'Endoscopy', 'Gastroenterology'),
  ('ultrasound', 'Ultrasound', 'Radiology'),
  ('cardiology', 'Cardiology', 'Cardiology'),
  ('operation-notes', 'Operation notes', 'Surgery'),
  ('pathology', 'Pathology', 'Pathology'),
 ]
 navigation='<nav class="actions" aria-label="Template specialties">'+''.join(f'<a class="button secondary" href="#specialty-{key}">{label} ({sum(item[2]==specialty for item in CATALOG)})</a>' for key,label,specialty in groups)+'</nav>'
 sections=''.join(f'<section id="specialty-{key}"><h2>{label}</h2><div class="cards">'+''.join(card(item) for item in CATALOG if item[2]==specialty)+'</div></section>' for key,label,specialty in groups)
 return navigation+sections

def main():
 out=PUBLIC/'templates';out.mkdir(exist_ok=True)
 (out/'templates.css').write_text(CSS)
 (out/'templates.js').write_text(SCRIPT)
 shutil.copyfile(ROOT/'tools/landing/community.js', out/'community.js')
 shutil.copyfile(ROOT/'web/template-funnel.js', out/'template-funnel.js')
 (out/'community.html').write_text(shell('Community reporting template','Preview an approved community reporting structure and use it in Ripot.','/templates/community.html','<p id="community-status" role="status">Loading template…</p><section id="community-preview"></section><a href="/templates/">Back to all templates</a>'))
 (out/'index.html').write_text(shell('Clinical report templates','Browse endoscopy, ultrasound, cardiology and surgical report structures. Preview, download or open a template in Ripot.','/templates/', '<span class="eyebrow">The Ripot template library</span><h1>A clear starting point for your next report.</h1><p class="lead">Choose a specialty, explore the fields and make the report your own.</p><p>Explore reporting templates across endoscopy, ultrasound, cardiology, operation notes and pathology. Download a printable PDF, or open an editable template in Ripot. Blank forms and clearly labelled fictional examples are available separately.</p>'+catalog_sections()+'<section id="community-section" hidden><h2>From the Ripot community</h2><p id="community-status" role="status"></p><div id="community-templates" class="cards"></div></section><section class="card"><h2>Have a useful reporting structure?</h2><p>Submit a patient-free reporting structure with your specialty and contributor credit. An authorised reviewer checks it before publication; contributors cannot review their own submissions. You receive an email when it is approved, rejected or needs changes, with a reason for rejection or requested changes. Feedback also stays in My submissions.</p><p>Changed your mind? Open the three-dot menu on your pending submission in My submissions and choose Withdraw submission. Your saved template is kept, and you can resubmit later.</p><div class="actions"><a class="button" href="https://ripot-web.web.app/?templateLibrary=contribute">Contribute a template</a><a class="button secondary" href="https://ripot-web.web.app/?templateLibrary=mine">My submissions</a><a class="button secondary" href="https://ripot-web.web.app/?templateLibrary=browse">Browse in Ripot</a></div></section>'))
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
  manifest.append({'slug':slug,'version':version,'name':title,'specialty':specialty,'contributor':'Ripot','status':'approved','url':f'/templates/catalog/{slug}/{version}.ripottemplate.json','sha256':hashlib.sha256(raw).hexdigest(), 'versions':[{'version':p.stem.split('.')[0], 'sha256':hashlib.sha256(p.read_bytes()).hexdigest(), 'url':f'/templates/catalog/{slug}/{p.name}'} for p in sorted(version_dir.glob('*.ripottemplate.json'))]})
  payload=json.loads(raw)
  template=payload['template']
  body=page_body(slug,title,specialty,desc,template,version,''.join(card(i) for i in sorted((i for i in CATALOG if i!=item), key=lambda i:i[2]!=specialty)[:4]))
  guide='<section class="outline-box"><h2>Using this reporting structure</h2>'+''.join(f'<h3>{e(heading)}</h3><p>{e(text)}</p>' for heading,text in GUIDES[slug])+'<p class="note">Documentation help, not clinical guidance. Use current specialty guidance and local protocols. Review every report before signing or sharing.</p></section>'
  if slug in ('upper-gi-endoscopy-report-template', 'structured-upper-gi-endoscopy-report-template'):
   body = '<section class="card"><h2>Choose your reporting style</h2><p><a href="/templates/upper-gi-endoscopy-report-template/">Narrative: flexible free-text sections</a> · <a href="/templates/structured-upper-gi-endoscopy-report-template/">Guided: conditional follow-up fields</a></p></section>' + body
  body=body.replace('<section><h2>Explore other templates</h2>',guide+'<section><h2>Explore other templates</h2>')
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
 home=PUBLIC/'index.html'
 home_text=home.read_text()
 start='<!-- TEMPLATE_LINKS_START -->';end='<!-- TEMPLATE_LINKS_END -->'
 if start in home_text and end in home_text:
  links='<nav class="template-highlights" aria-label="Featured templates">'+''.join(f'<a class="text-link" href="/templates/{slug}/">{e(title)}</a>' for slug,title,_,_ in CATALOG[:2])+'</nav>'
  before,rest=home_text.split(start,1);_,after=rest.split(end,1)
  home.write_text(before+start+'\n'+links+'\n'+end+after)
 print(f'Built hub and {len(CATALOG)} template pages with app-rendered PDF previews and labelled downloads.')
if __name__=='__main__':main()
