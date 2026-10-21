#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -f y/templates/index.html ]; then
  echo 'Use the packaged landing folder from the verified GitHub build. The template pages have not been generated in this folder.'
  exit 1
fi
firebase deploy --only hosting --project ripot-landing
