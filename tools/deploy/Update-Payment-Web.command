#!/bin/bash
# Publish the verified app, payment backend and landing page. Does not enable sales.
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -d functions ] && [ -d ../../functions ]; then cd ../..; fi
if [ -f SHA256SUMS.txt ]; then shasum -a 256 -c SHA256SUMS.txt; fi
node - <<'JS'
const fs = require('node:fs');
if(Number(process.versions.node.split('.')[0]) < 22) throw Error('Node 22 or newer is required.');
const config = JSON.parse(fs.readFileSync('firebase.json'));
const aliases = JSON.parse(fs.readFileSync('.firebaserc'));
if(config.hosting.target !== 'webapp' || aliases.targets['ripot-4edf7'].hosting.webapp[0] !== 'ripot-web') throw Error('Unexpected web target.');
if(!fs.existsSync(config.hosting.public+'/main.dart.js')) throw Error('Use the compiled release package or build the web app first.');
JS
command -v firebase >/dev/null || { echo 'Install the Firebase CLI and run firebase login first.'; exit 1; }
echo '1/3 Deploying payment functions with your configured secrets...'
bash tools/deploy/Deploy-Paystack-Backend.command
echo '2/3 Deploying Ripot Web...'
firebase deploy --project ripot-4edf7 --only hosting:webapp
echo '3/3 Deploying the landing page and template library...'
(cd landing && firebase deploy --project ripot-landing --only hosting)
echo 'Published. Follow docs/PAYSTACK_SETUP.md for test checkout and approved live configuration.'
echo 'Reload Ripot without clearing browser storage. Existing clinical data stays on your device.'
