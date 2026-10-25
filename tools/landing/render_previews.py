"""Rasterise the actual app-rendered PDFs; pages and downloads use identical bytes."""
import hashlib, json, subprocess
from additional_templates import TEMPLATES
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'landing/y/templates/previews'
manifest={}
closing_sections={item['slug']:item['groups'][-1][0] for item in TEMPLATES}
for pdf in sorted(OUT.glob('*.pdf')):
    slug=pdf.stem.rsplit('-',1)[0]
    if slug in closing_sections:
        text=subprocess.run(['pdftotext','-layout',str(pdf),'-'],check=True,capture_output=True,text=True).stdout
        pages=[page for page in text.split('\f') if page.strip()]
        if not pages or closing_sections[slug] not in pages[-1] or 'Clinician:' not in pages[-1]:
            raise SystemExit(f'{pdf.name}: closing section and signature must stay on the same page')
    for old_page in OUT.glob(pdf.stem+'-*.jpg'):old_page.unlink()
    subprocess.run(['pdftoppm','-jpeg','-jpegopt','quality=88','-scale-to','1500',str(pdf),str(pdf.with_suffix(''))],check=True)
    pages=sorted(OUT.glob(pdf.stem+'-*.jpg'),key=lambda p:int(p.stem.rsplit('-',1)[1]))
    if not pages:raise SystemExit(f'No pages rendered for {pdf}')
    manifest[pdf.stem]={'pdf':pdf.name,'sha256':hashlib.sha256(pdf.read_bytes()).hexdigest(),'pages':[p.name for p in pages]}
expected={slug+'-'+variant for slug in json.loads((ROOT/'tools/landing/example_values.json').read_text()) for variant in ('blank','example')}
if set(manifest)!=expected:raise SystemExit('PDF set does not match the template fixtures')
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Rendered',sum(len(m['pages']) for m in manifest.values()),'pages from',len(manifest),'actual Ripot PDFs')
