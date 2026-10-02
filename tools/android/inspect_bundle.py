"""Check the compiled Play bundle and package an explicitly unsigned artifact."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import xml.etree.ElementTree as ET
import zipfile

root = Path(__file__).resolve().parents[2]
output = root / "build/android-distribution"
bundle = root / "build/app/outputs/bundle/release/app-release.aab"
match = re.search(r"^version:\s*(\S+)\+(\d+)\s*$", (root / "pubspec.yaml").read_text(), re.M)
assert match, "Missing app version"
version, code = match.group(1), int(match.group(2))
manifest = ET.parse(output / "AndroidManifest.xml").getroot()
android = "{http://schemas.android.com/apk/res/android}"
assert manifest.get("package") == "com.nduaguba.report", "Wrong package"
assert manifest.get(android + "versionName") == version, "Wrong version name"
assert int(manifest.get(android + "versionCode")) == code, "Wrong version code"
target = int(manifest.find("uses-sdk").get(android + "targetSdkVersion"))
assert target >= 36, "Google Play target SDK must be at least 36"
permissions = {p.get(android + "name") for p in manifest.findall("uses-permission")}
assert "android.permission.INTERNET" in permissions, "Release has no network permission"
billing = manifest.find(f".//meta-data[@{android}name='com.google.android.play.billingclient.version']")
assert billing is not None, "Missing Play Billing version metadata"
billing_version = billing.get(android + "value")
assert int(billing_version.split('.')[0]) >= 8, "Play Billing 8 or later required"
assert "PAGE_ALIGNMENT_16K" in (output / "bundle-config.json").read_text(), "Missing 16 KB packaging alignment"
native_checks = []
with zipfile.ZipFile(bundle) as archive:
    assert not any(re.match(r"META-INF/[^/]+\.(RSA|DSA|EC|SF)$", n, re.I) for n in archive.namelist()), "Expected an unsigned bundle"
    for name in archive.namelist():
        if not re.match(r"base/lib/(arm64-v8a|x86_64)/.*\.so$", name):
            continue
        data = archive.read(name)
        assert data[:5] == b"\x7fELF\x02", f"Expected ELF64: {name}"
        endian = "<" if data[5] == 1 else ">"
        phoff = struct.unpack_from(endian + "Q", data, 32)[0]
        phentsize, phnum = struct.unpack_from(endian + "HH", data, 54)
        alignments = []
        for i in range(phnum):
            entry = struct.unpack_from(endian + "IIQQQQQQ", data, phoff + i * phentsize)
            if entry[0] == 1:
                alignments.append(entry[-1])
                assert entry[-1] >= 16384, f"Native library is not 16 KB aligned: {name}"
        assert alignments, f"No loadable segments: {name}"
        native_checks.append({"file": name, "loadAlignments": alignments})
assert native_checks, "No 64-bit native libraries checked"
name = f"Ripot-{version}-{code}-android-UNSIGNED.aab"
shutil.copy2(bundle, output / name)
sha = hashlib.sha256(bundle.read_bytes()).hexdigest()
report = {
    "package": "com.nduaguba.report", "versionName": version, "versionCode": code,
    "targetSdk": target, "billingLibrary": billing_version,
    "sourceCommit": os.environ.get("GITHUB_SHA"),
    "signatureStatus": "UNSIGNED - existing upload key required before Google Play upload",
    "sha256": sha, "bytes": bundle.stat().st_size, "nativeAlignmentChecks": native_checks,
}
(output / "android-release.json").write_text(json.dumps(report, indent=2) + "\n")
(output / "SHA256SUMS.txt").write_text(f"{sha}  {name}\n")
print(json.dumps({k: v for k, v in report.items() if k != "nativeAlignmentChecks"}, indent=2))
print(f"Checked {len(native_checks)} native libraries for 16 KB compatibility.")
