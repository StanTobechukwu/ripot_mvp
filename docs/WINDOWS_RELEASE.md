# Ripot Windows preparation

This branch starts from **1.0.11+46 with the updated registry**, including direct
table editing, field creation from either registry or patient, patient history,
and the compact Add/Update menus. It does not replace that registry with the
older `main` branch.

## Status

The native Windows source, installer definition and CI build workflow are
prepared. This is an **internal test build**, not a finished public release.
The Windows executable has not been compiled or run in the Linux workspace.

The Windows account integration now uses Firebase's documented Auth and
Firestore REST APIs and authenticated callable HTTP protocol. Windows startup
does not initialize the development-only native Firebase Auth/Firestore SDKs.
Android and web continue to use their existing SDK implementations.

Email/password sign-in, account creation, password reset, token renewal,
account-owned Premium checks and structure-only template sync are implemented.
The refresh credential is encrypted with flutter_secure_storage on Windows;
passwords and ID tokens are never persisted by this new implementation. ID
tokens are refreshed before remote operations. Signing out clears local account
access immediately and removes the saved credential. Credentials are scoped to
the Windows user and Firebase project. Existing local reports and registries
are unchanged.

Firebase ID tokens are used for Firestore requests, so existing Security Rules
remain authoritative. No service-account key, client entitlement grant, backend
deployment or Security Rules change is included. Verified Premium with a fixed
future expiry may be used offline for the same signed-in account. An expired
cache, another account's cache or a non-expiring administrative override cannot
unlock offline Premium. A revoked refresh credential signs the account out when
the server reports it; an offline app cannot discover revocation immediately.

The implementation is tested locally, including Firebase Auth/Firestore
emulators. Live production sign-in, native encrypted storage and the compiled
Windows app still require a Windows PC. The build remains internal-test until
those checks pass. Native Firebase plugin binaries may still be bundled as
transitive Flutter dependencies; the Windows account path does not use them.

References:
- https://firebase.google.com/docs/reference/rest/auth
- https://firebase.google.com/docs/firestore/use-rest-api
- https://firebase.google.com/docs/functions/callable-reference
- https://firebase.google.com/docs/flutter/setup#available-plugins

The installer is unsigned unless a real signing process is added. Windows may
display an unknown-publisher/SmartScreen warning. Code signing and a successful
Windows smoke test are separate from passing Dart widget/unit tests.

## What is included

- Safe Windows startup: Google Play billing is never initialized there.
- Premium access can be refreshed using the same signed-in Ripot account;
  the server still decides subscription and trial access. Google Play purchases
  remain in the Android app. Signing in does not synchronize patient data.
- Windows image selection uses a file chooser; no camera capture is advertised.
- Ripot window title, executable metadata and the existing Ripot launcher icon.
- Per-user Windows 10/11 x64 installer, Start menu shortcut and optional desktop
  shortcut. All Flutter/plugin DLLs, assets and MSVC runtime DLLs are included.
- Portable ZIP, SHA-256 checksums and a manifest identifying the exact commit,
  app version and any uncommitted source changes.
- Landing-page preparation that checks the real installer before adding links.

ARM64 and 32-bit Windows are not targets of this first package. There is no
automatic desktop updater. Later versions use the same installer AppId and
install location; users download and run the new installer.

## Build using GitHub from a Mac

Commit the latest app code and this patch to the branch
`codex/windows-download`, then push that branch. Its Windows workflow starts on
push. The existing `main` branch may be older; do not build from it or reset your
project to it.

In GitHub, open **Actions → Build Windows installer → the run for your branch**.
After it passes, download the `ripot-windows-<run number>` artifact and unzip it.
You will find the installer, portable ZIP, `windows-release.json` and
`SHA256SUMS.txt`. These are build artifacts, not public download links.

The same workflow can be run manually with `workflow_dispatch` once available
in the repository's Actions UI. This work does not merge a branch, create a
public GitHub release, deploy Firebase, or publish a Play update.

## Build on a Windows computer

Install Flutter 3.38.5, Visual Studio 2022 with **Desktop development with C++**,
and Inno Setup 6. From a PowerShell terminal at the app project root:

```powershell
./tools/windows/build_windows.ps1
```

The script runs all Flutter tests, builds Release, includes the MSVC runtime,
then compiles the installer. Output is in
`build/windows-distribution/<version>-<build>/`.

To change the Windows icon later after choosing a final logo, replace the icon
source intentionally, then run:

```sh
dart run flutter_launcher_icons -f tools/windows/flutter_launcher_icons.yaml
```

## Native validation still required

Use fictional data on a clean Windows PC without Flutter or Visual Studio:

1. Install, launch, close and reopen. Verify account sign-in, sign-out, trial
   handling and already-paid account access. Test offline opening of local work.
2. Create a report using a template, numeric fields, imported images and a
   signature. Preview, save PDF, print and export it. Check E′ symbols in the PDF.
3. Add fields from both registry and patient screens. Confirm the shared field
   definition and patient-specific values. Edit a cell, add a dated update,
   correct history, and cancel an edit without changing data.
4. Export and restore a Records package and a passphrase-protected registry
   backup. Check Logbook backup/restore and folder selection. Use the in-app
   import flow; Windows backup-file associations are not implemented.
5. Test window resizing, keyboard tabbing, scrolling and Windows display scaling.
6. Install an updated build over the same version and confirm data survives.
   Uninstall/reinstall and confirm local data remains. Make a backup first.

For accounts, also check a clean installation, remembered sign-in after restart,
password reset, a revoked session, account A → sign-out → account B, and loss of
network during Premium refresh. Verify that the Windows credential store works
on a standard user account and cannot restore a signed-out session. Test a
currently paid Android account; purchases and Play restoration remain Android
operations. Email/password is the supported desktop sign-in method; this patch
does not add multi-factor or social-provider sign-in.

Use the existing Firebase project configuration. Confirm its Windows API key
can call Identity Toolkit and Secure Token APIs under the intended restrictions.
If App Check enforcement blocks these account APIs, complete a supported
attestation or relay design before release; do not disable enforcement to ship.

Data lives in the current Windows user's profile. Separate Windows accounts do
not share a registry automatically. This does not implement multi-user merging.
This first branded installer uses Ripot's app-data identity; data from any older
unbranded experimental `report.exe` needs export/import.

## Prepare the landing page

The source is a separate project: Firebase project **ripot-landing**, public
folder **y**. Do not use the Flutter app's `webapp` Hosting target for it.

For a local preview of an internal Windows build, use a copy of the landing
folder and run the following, substituting your actual paths:

```sh
python3 tools/windows/prepare_landing_download.py \
  --landing /path/to/ripot-landing-copy \
  --release-dir /path/to/unzipped-windows-artifact \
  --preview
```

This checks the executable's PE header, size and SHA-256, then copies it and adds
two download buttons. It clearly labels the page as an internal preview.
Existing page/config files are backed up outside the hosted folder. Re-running
updates the links without duplicating controls. Current mobile layouts, Android
and web links, screenshots, and product/privacy copy are preserved.

Do not deploy this internal preview as the public website. Once live account
verification and native validation are complete, the release pipeline
can generate a `releaseStage: public` manifest. Do not relabel the current test
manifest as a substitute for resolving those requirements.

For an eligible public build, omit `--preview`, then from the landing folder:

```sh
python3 verify_landing.py
firebase hosting:channel:deploy windows-preview --expires 1d --project ripot-landing
# Check the preview download and installer before the live deployment:
firebase deploy --only hosting --project ripot-landing
```

The final download is served by `ripot.app/downloads/windows/…exe`. Until a real
public build exists, the live site is unchanged. No placeholder executable or
broken Windows download link is published.

## Repeat account verification locally

The regular `flutter test` suite includes mocked REST, storage failure,
token renewal, cancellation, UID isolation and Windows startup checks. The
emulator integration test is skipped unless explicitly enabled. It uses only
fictional accounts in the local `demo-ripot-windows` project and verifies the
actual wire protocol plus the unchanged Firestore Security Rules.

With Java and Firebase CLI installed, run from the app project root:

```sh
firebase emulators:exec --only auth,firestore \
  --project demo-ripot-windows --config firebase.windows.test.json \
  "flutter test --dart-define=RIPOT_ACCOUNT_EMULATORS=true test/integration/windows_accounts_emulator_test.dart"
```

This was verified with Firebase CLI 14.22.0 / Java 17. Current Firebase CLI 15
requires Java 21 or newer. The emulator HTTP routing exists only in the test
fixture; production requests are restricted to HTTPS Firebase endpoints.
