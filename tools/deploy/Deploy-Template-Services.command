#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# Works from a release folder or from tools/deploy in the source repository.
if [ ! -d functions ] && [ -d ../../functions ]; then cd ../..; fi
if [ -f SHA256SUMS.txt ]; then shasum -a 256 -c SHA256SUMS.txt; fi
command -v firebase >/dev/null || { echo "Install the Firebase CLI, run firebase login, then retry."; exit 1; }
node -e 'if(Number(process.versions.node.split(".")[0])<20) { console.error("Node 20 or newer is required."); process.exit(1); }'
npm ci --prefix functions
# Email is deliberately separate: a missing SMTP secret cannot block core use.
firebase deploy --project ripot-4edf7 --only functions:submitTemplateContribution,functions:listTemplateContributions,functions:reviewTemplateContribution,functions:withdrawTemplateContribution,functions:publicTemplateLibrary,firestore:rules
node functions/scripts/check-template-services.js
echo "Core services deployed. Run Setup-Template-Reviewer.command and Setup-Template-Notifications.command to finish owner setup."
