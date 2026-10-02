# Google Play update: Ripot 1.0.12 (47)

On 2 October 2026, Play Console showed production version 1.0.10 (45),
fully rolled out. Version 45 was also the highest uploaded app bundle;
there were no unpublished changes. Version 47 is the prepared update.

The source includes the Logbook, Registry editing improvements, welcome
screen, contextual trial/Premium prompts and final-PDF storage limits
(10 Free; 100 during an active trial or Premium). Existing saved reports
remain available after trial/Premium expiry. Drafts do not consume PDF slots.

The [Android build](https://github.com/StanTobechukwu/ripot_mvp/actions/runs/37006881181)
passed on 2 October 2026 for source `26f576bf5bdc076822ae77a41f919c3c7e9775d3`.
The unsigned AAB is 56,497,958 bytes, SHA-256
`9111a6d3f2cd15c7e51aca5c8f1da62b7c129710b75dc8da71b98225fa712307`.
It targets API 36, includes Billing Library 8.0.0, and all eight bundled
64-bit native libraries passed the 16 KB alignment check. Bundletool
validation, package/version checks and the internet-permission check passed.

## Build and sign

The Android workflow compiles the release with Flutter 3.38.5 and Java 17,
then checks the package, version, target API 36+, Billing 8+, internet
permission and 16 KB alignment. It uses the Firebase client identifiers
already committed in `lib/firebase_options.dart`, for `ripot-4edf7` and
`com.nduaguba.report`. No upload key is used or stored in GitHub.

The CI artifact is explicitly UNSIGNED and cannot be submitted to Play yet.
Copy `tools/android/Sign-Ripot.command` alongside the bundle and
`SHA256SUMS.txt`. On the Mac used for previous Android releases, run:

```bash
bash Sign-Ripot.command
```

The helper defaults to the existing `~/upload-keystore.jks`, alias `upload`.
If it moved, pass the existing key path and alias as arguments. Java prompts
for the existing password locally. The helper verifies the signed bundle's
certificate against the current Play upload certificate (SHA-256
`5C:62:65:87:C5:D7:70:EA:82:09:B5:85:4B:4F:F1:0C:14:B1:E1:9A:3C:E3:07:3A:A3:37:AD:4B:7A:1D:A1:66`).
No new signing key is needed.

Return the `Ripot-1.0.12-47-android-SIGNED.aab` file for Play submission.
Compilation and static bundle checks do not replace a real-device check of
Android's folder picker, backup/restore, sign-in and purchases. The previous
77 targeted Flutter tests passed; Android device checks are still outstanding.

## Suggested release notes

```text
<en-US>
New Logbook with signed entries and encrypted backup and restore.
Improved Registry editing and navigation.
Clearer sign-in, free trial and Premium access prompts.
Updated saved-report limits: 10 final PDFs on Free, 100 during a trial or Premium.
Improvements to report saving and account access.
</en-US>
```

## Publication status

The bundle must be signed with the existing upload key before upload. No
Google Play release has been uploaded, submitted for review or published by
this preparation step. Do not describe a GitHub push or successful build as
a live Play update.
