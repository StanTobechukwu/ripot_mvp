#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -d functions ] && [ -d ../../functions ]; then cd ../..; fi
if [ -f SHA256SUMS.txt ]; then shasum -a 256 -c SHA256SUMS.txt; fi
if [ ! -d functions/node_modules ]; then npm ci --prefix functions; fi
echo "The next Firebase prompt securely stores your support@ripot.app mailbox/app password. Do not paste it into chat."
firebase functions:secrets:set TEMPLATE_SMTP_PASSWORD --project ripot-4edf7
firebase deploy --project ripot-4edf7 --only functions:notifyTemplateContribution
echo "Notification worker deployed. Submit a patient-free test template and check support@ripot.app, including spam."
echo "Review it using a different account, then check the contributor inbox for the decision and feedback."
echo "Deployment alone does not prove delivery. See TEMPLATE_LIBRARY.md for queued messages created before deployment."
