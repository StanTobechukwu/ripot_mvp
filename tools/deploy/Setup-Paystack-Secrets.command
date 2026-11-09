#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
command -v firebase >/dev/null || { echo 'Install the Firebase CLI and run firebase login first.'; exit 1; }
PAYSTACK_SETUP_MODE="${1:-test}"
case "$PAYSTACK_SETUP_MODE" in test|live) ;; *) echo 'Use test or live as the first argument.'; exit 1 ;; esac
echo "Enter your Paystack $PAYSTACK_SETUP_MODE secret key at the Firebase prompt. It is stored in Secret Manager, not source code."
firebase functions:secrets:set PAYSTACK_SECRET_KEY --project ripot-4edf7
echo 'Enter your Paystack webhook signing secret (whsec_...). If your dashboard still uses legacy signatures, enter the literal word legacy.'
firebase functions:secrets:set PAYSTACK_WEBHOOK_SECRET --project ripot-4edf7
echo 'Secrets saved. Run Deploy-Paystack-Backend.command, then follow docs/PAYSTACK_SETUP.md.'
