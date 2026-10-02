#!/bin/bash
# Sign the downloaded release using the existing upload key on the release Mac.
set -euo pipefail
cd "$(dirname "$0")"

RIPOT_UPLOAD_KEY="${1:-$HOME/upload-keystore.jks}"
RIPOT_UPLOAD_ALIAS="${2:-upload}"
RIPOT_EXPECTED_CERT='5C:62:65:87:C5:D7:70:EA:82:09:B5:85:4B:4F:F1:0C:14:B1:E1:9A:3C:E3:07:3A:A3:37:AD:4B:7A:1D:A1:66'

if [[ ! -f "$RIPOT_UPLOAD_KEY" ]]; then
  echo "The existing upload key was not found at: $RIPOT_UPLOAD_KEY"
  echo "Run this script again with the path to your existing keystore as its first argument."
  exit 1
fi

# Android Studio includes a JDK, even when Java is not on the Mac's PATH.
RIPOT_JAVA_BIN=''
if [[ -x '/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/jarsigner' ]]; then
  RIPOT_JAVA_BIN='/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/'
elif [[ -x '/usr/libexec/java_home' ]]; then
  RIPOT_JDK_PATH="$(/usr/libexec/java_home 2>/dev/null || true)"
  if [[ -n "$RIPOT_JDK_PATH" ]]; then RIPOT_JAVA_BIN="$RIPOT_JDK_PATH/bin/"; fi
fi
if ! command -v "${RIPOT_JAVA_BIN}jarsigner" >/dev/null; then
  echo "Java signing tools are missing. Run this on the Mac used for previous Android releases."
  exit 1
fi

shasum -a 256 -c SHA256SUMS.txt
shopt -s nullglob
RIPOT_BUNDLES=(Ripot-*-android-UNSIGNED.aab)
if [[ ${#RIPOT_BUNDLES[@]} -ne 1 ]]; then
  echo "Keep exactly one unsigned Ripot bundle beside this script."
  exit 1
fi
RIPOT_UNSIGNED="${RIPOT_BUNDLES[0]}"
RIPOT_SIGNED="${RIPOT_UNSIGNED%-UNSIGNED.aab}-SIGNED.aab"
RIPOT_PENDING=".${RIPOT_UNSIGNED%.aab}-signing-$$.aab"
if [[ -e "$RIPOT_SIGNED" ]]; then
  echo "A signed file already exists: $RIPOT_SIGNED"
  echo "Move it elsewhere before signing again."
  exit 1
fi
trap 'rm -f -- "$RIPOT_PENDING"' EXIT

echo "Enter your existing keystore password at Java's prompt. It will stay on this Mac."
"${RIPOT_JAVA_BIN}jarsigner" -keystore "$RIPOT_UPLOAD_KEY" -digestalg SHA-256 \
  -signedjar "$RIPOT_PENDING" "$RIPOT_UNSIGNED" "$RIPOT_UPLOAD_ALIAS"
RIPOT_VERIFY_OUTPUT="$("${RIPOT_JAVA_BIN}jarsigner" -J-Duser.language=en -J-Duser.country=US -verify "$RIPOT_PENDING" 2>&1)"
if [[ "$RIPOT_VERIFY_OUTPUT" != *'jar verified.'* || "$RIPOT_VERIFY_OUTPUT" == *'unsigned entries'* ]]; then
  echo "$RIPOT_VERIFY_OUTPUT"
  echo "Signature verification failed. Do not upload the resulting file."
  exit 1
fi
RIPOT_CERT_OUTPUT="$("${RIPOT_JAVA_BIN}keytool" -J-Duser.language=en -J-Duser.country=US -printcert -jarfile "$RIPOT_PENDING")"
RIPOT_ACTUAL_CERT="$(printf '%s\n' "$RIPOT_CERT_OUTPUT" | awk '/SHA256:/{print $2; exit}')"
if [[ "$RIPOT_ACTUAL_CERT" != "$RIPOT_EXPECTED_CERT" ]]; then
  echo "This key does not match Ripot's current Google Play upload certificate."
  echo "Do not upload the resulting file. Use the original upload key."
  exit 1
fi
mv "$RIPOT_PENDING" "$RIPOT_SIGNED"
echo ""
echo "Signature verified and matched to Google Play. Ready to upload:"
echo "$PWD/$RIPOT_SIGNED"
if [[ "$(uname -s)" == 'Darwin' ]]; then open -R "$RIPOT_SIGNED"; fi
