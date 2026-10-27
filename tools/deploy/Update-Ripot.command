#!/bin/bash
# Update an existing installation with SMTP already configured. Never resets secrets.
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -d functions ] && [ -d ../../functions ]; then cd ../..; fi
if [ -f SHA256SUMS.txt ]; then shasum -a 256 -c SHA256SUMS.txt; fi
command -v firebase >/dev/null || { echo "Install the Firebase CLI and run firebase login, then retry."; exit 1; }
node -e 'if(Number(process.versions.node.split(".")[0])<20) { console.error("Node 20 or newer is required."); process.exit(1); }'
node - <<'JS'
const fs = require('node:fs');
const config = JSON.parse(fs.readFileSync('firebase.json', 'utf8'));
const aliases = JSON.parse(fs.readFileSync('.firebaserc', 'utf8'));
if (config.hosting?.target !== 'webapp' || aliases.targets?.['ripot-4edf7']?.hosting?.webapp?.[0] !== 'ripot-web') {
  throw Error('Unexpected web app deployment target.');
}
if (!fs.existsSync(config.hosting.public + '/main.dart.js') || !fs.existsSync('landing/y/index.html')) {
  throw Error('Missing built app or landing page. Use the complete compiled release folder, or build the source checkout first.');
}
JS
npm ci --prefix functions
# Old workers treat every queue record as a reviewer alert, so update the worker first.
echo "1/4 Updating contributor email delivery with the existing mailbox secret..."
firebase deploy --project ripot-4edf7 --only functions:notifyTemplateContribution
echo "2/4 Updating template contributions, review and withdrawal..."
firebase deploy --project ripot-4edf7 --only functions:submitTemplateContribution,functions:listTemplateContributions,functions:reviewTemplateContribution,functions:withdrawTemplateContribution,functions:publicTemplateLibrary,firestore:rules
node functions/scripts/check-template-services.js
echo "3/4 Updating Ripot Web..."
firebase deploy --project ripot-4edf7 --only hosting:webapp
echo "4/4 Updating the public landing page..."
cd landing
firebase deploy --project ripot-landing --only hosting
echo "Web and landing deployments completed. Reload Ripot without clearing site data."
echo "Test a new contribution and independent review; check the contributor email inbox and spam."
echo "Android and Windows installers are separate releases."
