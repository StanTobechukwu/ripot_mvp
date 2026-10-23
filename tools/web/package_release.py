"""Package compiled web bytes and the exact app Hosting target for deployment."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil

root = Path(__file__).resolve().parents[2]
web = root / 'build/web'
for name in ('index.html', 'main.dart.js', 'flutter_bootstrap.js'):
    if not (web / name).is_file():
        raise SystemExit(f'Missing web build output: {name}')
match = re.search(r'^version:\s*(\S+)\+(\d+)\s*$', (root / 'pubspec.yaml').read_text(), re.M)
if not match:
    raise SystemExit('Missing version')
version, build = match.group(1), int(match.group(2))
source = os.environ.get('GITHUB_SHA')
if not source or not re.fullmatch(r'[0-9a-f]{40}', source):
    raise SystemExit('Missing verified CI source commit')
release = {'version': version, 'build': build, 'sourceCommit': source}
(web / 'release.json').write_text(json.dumps(release, indent=2) + '\n')
stage = root / 'build/web-distribution' / f'Ripot-Web-{version}-{build}-{source[:8]}'
stage.mkdir(parents=True, exist_ok=True)
shutil.copytree(web, stage / 'web', dirs_exist_ok=True)
config = json.loads((root / 'firebase.json').read_text())['hosting']
aliases = json.loads((root / '.firebaserc').read_text())
if config['target'] != 'webapp' or aliases['targets']['ripot-4edf7']['hosting']['webapp'] != ['ripot-web']:
    raise SystemExit('Unexpected Hosting target')
config['public'] = 'web'
config['headers'] = [
    {'source': name, 'headers': [{'key': 'Cache-Control', 'value': 'no-cache, max-age=0, must-revalidate'}]}
    for name in ('/', '/index.html', '/flutter_bootstrap.js', '/flutter_service_worker.js', '/main.dart.js', '/version.json', '/release.json')
]
(stage / 'firebase.json').write_text(json.dumps({'hosting': config}, indent=2) + '\n')
(stage / '.firebaserc').write_text(json.dumps(aliases, indent=2) + '\n')
(stage / 'Deploy-Web.command').write_text(f'''#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
shasum -a 256 -c SHA256SUMS.txt
firebase deploy --only hosting:webapp --project ripot-4edf7
echo "Deployment completed. Open https://ripot-web.web.app and verify version {version} ({build})."
''')
(stage / 'Deploy-Web.command').chmod(0o755)
(stage / 'README.txt').write_text(f'''Ripot web {version} ({build})
Source: {source}

This folder contains the combined web update; Flutter is not required to deploy it.
Included: updated branding/support, safer Registry report linking, unlimited
saved PDFs for Premium/active trials, dynamic public templates, the Free-user
letterhead invitation, Web/Windows checkout-availability messaging, and the
community template library with submissions and reviewer screens.
The contribution backend, reviewer account and SMTP notification setup must
be deployed separately using the included TEMPLATE_LIBRARY.md instructions.
Direct online payment checkout is not enabled. Android and Windows installers
are separate releases.

Use this complete folder rather than copying files into an older download.
On the Mac already used for Firebase deployment, open Terminal in this folder:
  bash Deploy-Web.command
If Firebase asks you to sign in, run firebase login and try again.
The destination is ripot-web in project ripot-4edf7.
This does not deploy the separate ripot.app landing page.
Check /release.json on the live web app to confirm the exact release.
Reload existing tabs after deployment. Do not clear browser storage containing local data.
''')
shutil.copyfile(root / 'functions/TEMPLATE_LIBRARY.md', stage / 'TEMPLATE_LIBRARY.md')
checks = []
for path in sorted(stage.rglob('*')):
    if path.is_file():
        checks.append(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(stage)}')
(stage / 'SHA256SUMS.txt').write_text('\n'.join(checks) + '\n')
archive = shutil.make_archive(str(stage), 'zip', stage.parent, stage.name)
shutil.rmtree(stage)
print(archive)
