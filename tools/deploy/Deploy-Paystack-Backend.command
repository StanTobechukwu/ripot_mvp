#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
command -v firebase >/dev/null || { echo 'Install the Firebase CLI and run firebase login first.'; exit 1; }
npm ci --prefix functions
firebase deploy --project ripot-4edf7 --only functions:getPaystackPlans,functions:startPaystackCheckout,functions:refreshPaystackEntitlement,functions:managePaystackSubscription,functions:refreshPaidEntitlements,functions:paystackWebhook,functions:verifyGooglePlaySubscription,functions:refreshPlayEntitlement,functions:getReportCopyAllowance,functions:authorizeReportCopy
printf '%s\n' 'Backend deployed. Checkout stays unavailable until its catalogue is configured.' 'Webhook: https://us-central1-ripot-4edf7.cloudfunctions.net/paystackWebhook'
