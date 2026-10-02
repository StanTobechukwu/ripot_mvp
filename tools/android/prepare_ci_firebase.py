"""Recreate the Android Firebase client config from committed Flutter options.

Ripot uses email/password authentication, so no native OAuth client is required.
This file contains public app identifiers only; it never loads a signing key.
Local release builds continue using their own google-services.json unchanged.
"""
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
target = root / "android/app/google-services.json"
if target.exists():
    raise SystemExit("Refusing to overwrite an existing Firebase configuration.")
source = (root / "lib/firebase_options.dart").read_text()
block = re.search(r"static const FirebaseOptions android = FirebaseOptions\((.*?)\);", source, re.S)
if block is None:
    raise SystemExit("Android Firebase options are missing.")
options = dict(re.findall(r"(\w+):\s*'([^']+)'", block.group(1)))
required = {"projectId", "messagingSenderId", "appId", "apiKey", "storageBucket"}
if not required.issubset(options):
    raise SystemExit("Android Firebase options are incomplete.")
config = {
    "project_info": {
        "project_number": options["messagingSenderId"],
        "project_id": options["projectId"],
        "storage_bucket": options["storageBucket"],
    },
    "client": [{
        "client_info": {
            "mobilesdk_app_id": options["appId"],
            "android_client_info": {"package_name": "com.nduaguba.report"},
        },
        "oauth_client": [],
        "api_key": [{"current_key": options["apiKey"]}],
        "services": {"appinvite_service": {"other_platform_oauth_client": []}},
    }],
    "configuration_version": "1",
}
target.write_text(json.dumps(config, indent=2) + "\n")
print("Prepared existing Firebase client for com.nduaguba.report.")
