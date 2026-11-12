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
(stage / 'firebase.json').write_text(json.dumps({'hosting': config, 'functions': {'source': 'functions', 'runtime': 'nodejs22'}, 'firestore': {'rules': 'firestore.rules'}}, indent=2) + '\n')
(stage / '.firebaserc').write_text(json.dumps(aliases, indent=2) + '\n')
(stage / 'Deploy-Web.command').write_text(f'''#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
shasum -a 256 -c SHA256SUMS.txt
firebase deploy --only hosting:webapp --project ripot-4edf7
echo "Deployment completed. Open https://ripot-web.web.app and verify version {version} ({build})."
''')
(stage / 'Deploy-Web.command').chmod(0o755)
(stage / 'README.txt').write_text(f'''Ripot Web {version} ({build}) — payment path and guided OGD update
Source: {source}

This is a compiled deployment candidate. Deployment and merchant setup are separate.
The landing page links directly to Ripot Premium. Web users sign in, select their
billing country and review the server-approved offer before Paystack checkout.
Nigeria retains NGN 2,500 monthly / 25,000 yearly. No overseas prices are enabled
by this package. Add country-specific NGN offers only after their approval.
International rates must be higher than the corresponding Nigerian rates.

On your Mac with Node 22, Firebase CLI and Firebase owner access:
1. Read docs/PAYSTACK_SETUP.md. Save the Paystack test secrets securely using
   bash tools/deploy/Setup-Paystack-Secrets.command test
2. Deploy the backend, then web app, then landing page with:
   bash tools/deploy/Update-Payment-Web.command
3. Configure the test catalogue and webhook using docs/PAYSTACK_SETUP.md.
4. Complete test checkout before enabling any approved live pilot.
No command in this package charges a customer or enables new sales automatically.

The same package retains the guided OGD changes dated 8 November 2026:
Los Angeles, Prague C/M, Forrest, Sarin, Baveno, EREFS components and Paris.
Contributor: Dr Nduaguba Tobechukwu Stanley. Existing findings, medications,
biopsy summary, images, report layout and saved reports are preserved.
There is no automatic EREFS total or treatment/surveillance recommendation.
Android and Windows binaries need a separate release for their new guide controls.

Reports and registry data remain local. Sign in with the same account to check
verified Premium on supported devices; this does not transfer clinical data.
Reload the web app after deployment. Do not clear browser storage containing reports.
Check https://ripot-web.web.app/release.json for the exact deployed source commit.

Deploy-Web.command and Deploy-Landing.command are available for hosting-only updates.
Update-Ripot.command retains the separate contributor/email update workflow.
''')
shutil.copyfile(root / 'functions/TEMPLATE_LIBRARY.md', stage / 'TEMPLATE_LIBRARY.md')
shutil.copyfile(root / 'tools/web/TEMPLATE_GROWTH_CHECKS.md', stage / 'TEMPLATE_GROWTH_CHECKS.md')
# Package only tracked deployment sources, never credentials, dotenv files or node_modules.
(stage / 'functions/scripts').mkdir(parents=True, exist_ok=True)
for source_file in sorted((root / 'functions').glob('*.js')):
    shutil.copyfile(source_file, stage / 'functions' / source_file.name)
for name in ('package.json', 'package-lock.json', 'TEMPLATE_LIBRARY.md', 'billing-countries.json'):
    shutil.copyfile(root / 'functions' / name, stage / 'functions' / name)
for script in ('template-reviewer.js', 'check-template-services.js', 'paystack-setup.js'):
    shutil.copyfile(root / 'functions/scripts' / script, stage / 'functions/scripts' / script)
shutil.copyfile(root / 'firestore.rules', stage / 'firestore.rules')
shutil.copytree(root / 'landing/y', stage / 'landing/y', dirs_exist_ok=True)
for name in ('firebase.json', '.firebaserc'):
    shutil.copyfile(root / 'landing' / name, stage / 'landing' / name)
for name in ('Deploy-Template-Services.command', 'Setup-Template-Reviewer.command', 'Setup-Template-Notifications.command', 'Update-Ripot.command'):
    shutil.copyfile(root / 'tools/deploy' / name, stage / name)
    (stage / name).chmod(0o755)
(stage / 'Deploy-Landing.command').write_text('''#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
shasum -a 256 -c SHA256SUMS.txt
cd landing
firebase deploy --only hosting --project ripot-landing
''')
for name in ('Deploy-Template-Services.command', 'Deploy-Landing.command'):
    (stage / name).chmod(0o755)
(stage / 'tools/deploy').mkdir(parents=True, exist_ok=True)
(stage / 'docs').mkdir(exist_ok=True)
for name in ('Update-Payment-Web.command', 'Setup-Paystack-Secrets.command', 'Deploy-Paystack-Backend.command'):
    shutil.copyfile(root / 'tools/deploy' / name, stage / 'tools/deploy' / name)
    (stage / 'tools/deploy' / name).chmod(0o755)
shutil.copyfile(root / 'docs/PAYSTACK_SETUP.md', stage / 'docs/PAYSTACK_SETUP.md')
shutil.copyfile(root / 'docs/GUIDED_OGD_GRADINGS_20261108.md', stage / 'docs/GUIDED_OGD_GRADINGS_20261108.md')
checks = []
for path in sorted(stage.rglob('*')):
    if path.is_file():
        checks.append(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(stage)}')
(stage / 'SHA256SUMS.txt').write_text('\n'.join(checks) + '\n')
archive = shutil.make_archive(str(stage), 'zip', stage.parent, stage.name)
shutil.rmtree(stage)
print(archive)
