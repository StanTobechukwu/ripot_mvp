#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -d functions ] && [ -d ../../functions ]; then cd ../..; fi
if [ -f SHA256SUMS.txt ]; then shasum -a 256 -c SHA256SUMS.txt; fi
if [ ! -d functions/node_modules ]; then npm ci --prefix functions; fi
printf 'Email of the registered Ripot account to grant reviewer access: '
read -r reviewer_email
if [ -z "$reviewer_email" ]; then echo 'No email entered. Nothing changed.'; exit 1; fi
# Uses the project owner's existing Google application-default credentials.
# If absent, use gcloud auth application-default login on your own computer.
node functions/scripts/template-reviewer.js ripot-4edf7 "$reviewer_email" grant
node functions/scripts/template-reviewer.js ripot-4edf7 "$reviewer_email" check
echo "Sign in with that account at https://ripot-web.web.app/?templateLibrary=review"
echo "A different reviewer must review your own submissions."
