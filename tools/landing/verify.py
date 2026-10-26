"""Check static links and release claims before packaging."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import urlsplit,unquote
import hashlib,json
ROOT=Path(__file__).resolve().parents[2]/'landing/y'
class Links(HTMLParser):
 def __init__(self):super().__init__();self.links=[]
 def handle_starttag(self,tag,attrs):
  a=dict(attrs)
  for key in ('href','src'):
   if key in a:self.links.append(a[key])
errors=[]
source=Path(__file__).resolve().parent/'community.js'
if source.read_bytes() != (ROOT/'templates/community.js').read_bytes():
 errors.append('Community script differs from its generator source; rebuild templates before packaging.')
for page in ROOT.rglob('*.html'):
 text=page.read_text();parser=Links();parser.feed(text)
 for url in parser.links:
  parts=urlsplit(url)
  if parts.scheme or parts.netloc or not parts.path:continue
  target=(ROOT/parts.path.lstrip('/')) if parts.path.startswith('/') else page.parent/parts.path
  target=Path(unquote(str(target)))
  if not target.exists():errors.append(f'{page.relative_to(ROOT)}: missing {parts.path}')
 if 'ripottechnologies@gmail.com' in text:errors.append(f'{page}: old support address')
 if 'up to 100 final PDFs' in text:errors.append(f'{page}: old PDF limit')
catalog=json.loads((ROOT/'templates/catalog/manifest.json').read_text())['templates']
for slug in [entry['slug'] for entry in catalog]:
 page=ROOT/'templates'/slug/'index.html'
 if not page.exists() or f'?template={slug}' not in page.read_text():errors.append(f'{slug}: missing deep link')
 if page.exists() and '\\n' in page.read_text():errors.append(f'{slug}: literal newline escapes in copyable example')
if errors:raise SystemExit('\n'.join(errors))
previews=ROOT/'templates/previews'
manifest=json.loads((previews/'manifest.json').read_text())
assert set(manifest)=={entry['slug']+'-'+variant for entry in catalog for variant in ('blank','example')}, 'Every template needs blank and fictional PDFs'
for key,entry in manifest.items():
 raw=(previews/entry['pdf']).read_bytes()
 assert raw.startswith(b'%PDF-'), f'{key}: not a PDF'
 assert hashlib.sha256(raw).hexdigest()==entry['sha256'], f'{key}: changed PDF bytes'
 assert entry['pages'] and all((previews/name).is_file() for name in entry['pages']), f'{key}: missing preview pages'
 slug,variant=key.rsplit('-',1)
 page=(ROOT/'templates'/slug/'index.html').read_text()
 assert entry['pdf'] in page and all(name in page for name in entry['pages'])
 assert 'Download Ripot import file' in page and 'Download blank PDF' in page
 outline=(ROOT/'templates/downloads'/f'{slug}-outline.txt').read_text()
 assert '[enter]' not in outline and 'FICTIONAL PATIENT' not in outline
 assert 'Patient: ________________' in outline
print('Static links, support address, PDF copy and template targets verified.')
print(f'{len(manifest)} PDF hashes, preview pages, clear download labels and blank outlines verified.')
