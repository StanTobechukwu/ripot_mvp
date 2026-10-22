"""Check static links and release claims before packaging."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import urlsplit,unquote
ROOT=Path(__file__).resolve().parents[2]/'landing/y'
class Links(HTMLParser):
 def __init__(self):super().__init__();self.links=[]
 def handle_starttag(self,tag,attrs):
  a=dict(attrs)
  for key in ('href','src'):
   if key in a:self.links.append(a[key])
errors=[]
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
for slug in ('upper-gi-endoscopy-report-template','colonoscopy-report-template','abdominal-ultrasound-report-template','echocardiogram-report-template'):
 page=ROOT/'templates'/slug/'index.html'
 if not page.exists() or f'?template={slug}' not in page.read_text():errors.append(f'{slug}: missing deep link')
 if page.exists() and '\\n' in page.read_text():errors.append(f'{slug}: literal newline escapes in copyable example')
if errors:raise SystemExit('\n'.join(errors))
print('Static links, support address, PDF copy and template targets verified.')
