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
(stage / 'firebase.json').write_text(json.dumps({'hosting': config, 'functions': {'source': 'functions', 'runtime': 'nodejs20'}, 'firestore': {'rules': 'firestore.rules'}}, indent=2) + '\n')
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
The four starter templates now include real PDF previews, blank and fictional
example PDF downloads, page zoom and readable plain/formatted copied outlines.
To apply these landing-page improvements, run bash Deploy-Landing.command.
The contribution backend, reviewer account and SMTP notification setup must
be deployed separately using the included TEMPLATE_LIBRARY.md instructions.
Direct online payment checkout is not enabled. Android and Windows installers
are separate releases.

Use this complete folder rather than copying files into an older download.
On the Mac already used for Firebase deployment, open Terminal in this folder:
  bash Deploy-Web.command
If Firebase asks you to sign in, run firebase login and try again.
The destination is ripot-web in project ripot-4edf7.
For all three parts of this update, finish the one-time reviewer and SMTP setup
in TEMPLATE_LIBRARY.md, then run these scripts from THIS same folder:
  bash Deploy-Template-Services.command
  bash Deploy-Web.command
  bash Deploy-Landing.command
The first deploys the new backend (Node 20 required); the third updates ripot.app.
The web-only script does not deploy the separate landing page or backend.
Check /release.json on the live web app to confirm the exact release.
Reload existing tabs after deployment. Do not clear browser storage containing local data.
''')
shutil.copyfile(root / 'functions/TEMPLATE_LIBRARY.md', stage / 'TEMPLATE_LIBRARY.md')
# Package only tracked deployment sources, never credentials, dotenv files or node_modules.
(stage / 'functions/scripts').mkdir(parents=True, exist_ok=True)
for source_file in sorted((root / 'functions').glob('*.js')):
    shutil.copyfile(source_file, stage / 'functions' / source_file.name)
for name in ('package.json', 'package-lock.json', 'TEMPLATE_LIBRARY.md'):
    shutil.copyfile(root / 'functions' / name, stage / 'functions' / name)
shutil.copyfile(root / 'functions/scripts/template-reviewer.js', stage / 'functions/scripts/template-reviewer.js')
shutil.copyfile(root / 'firestore.rules', stage / 'firestore.rules')
shutil.copytree(root / 'landing/y', stage / 'landing/y', dirs_exist_ok=True)
for name in ('firebase.json', '.firebaserc'):
    shutil.copyfile(root / 'landing' / name, stage / 'landing' / name)
(stage / 'Deploy-Template-Services.command').write_text('''#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
shasum -a 256 -c SHA256SUMS.txt
npm ci --prefix functions
firebase deploy --project ripot-4edf7 --only functions:submitTemplateContribution,functions:listTemplateContributions,functions:reviewTemplateContribution,functions:publicTemplateLibrary,functions:notifyTemplateContribution,firestore:rules
echo "Template services deployed. Complete reviewer and email verification in TEMPLATE_LIBRARY.md."
''')
(stage / 'Deploy-Landing.command').write_text('''#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
shasum -a 256 -c SHA256SUMS.txt
cd landing
firebase deploy --only hosting --project ripot-landing
''')
for name in ('Deploy-Template-Services.command', 'Deploy-Landing.command'):
    (stage / name).chmod(0o755)
checks = []
for path in sorted(stage.rglob('*')):
    if path.is_file():
        checks.append(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(stage)}')
(stage / 'SHA256SUMS.txt').write_text('\n'.join(checks) + '\n')
archive = shutil.make_archive(str(stage), 'zip', stage.parent, stage.name)
shutil.rmtree(stage)
print(archive)
