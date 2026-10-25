"""Rasterise the actual app-rendered PDFs; pages and downloads use identical bytes."""
import hashlib, json, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'landing/y/templates/previews'
manifest={}
for pdf in sorted(OUT.glob('*.pdf')):
    for old_page in OUT.glob(pdf.stem+'-*.jpg'):old_page.unlink()
    subprocess.run(['pdftoppm','-jpeg','-jpegopt','quality=88','-scale-to','1500',str(pdf),str(pdf.with_suffix(''))],check=True)
    pages=sorted(OUT.glob(pdf.stem+'-*.jpg'),key=lambda p:int(p.stem.rsplit('-',1)[1]))
    if not pages:raise SystemExit(f'No pages rendered for {pdf}')
    manifest[pdf.stem]={'pdf':pdf.name,'sha256':hashlib.sha256(pdf.read_bytes()).hexdigest(),'pages':[p.name for p in pages]}
expected={slug+'-'+variant for slug in json.loads((ROOT/'tools/landing/example_values.json').read_text()) for variant in ('blank','example')}
if set(manifest)!=expected:raise SystemExit('PDF set does not match the template fixtures')
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Rendered',sum(len(m['pages']) for m in manifest.values()),'pages from',len(manifest),'actual Ripot PDFs')
