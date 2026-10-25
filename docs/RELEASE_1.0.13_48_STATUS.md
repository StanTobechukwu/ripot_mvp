# Ripot 1.0.13 (48) release status — 5 October 2026

## Source

Release source: `79c3a0173aca7c47631b03784c4454527dad2c2a`, branch `codex/release-1.0.13-48`.
Based on the saved Records/Registry work at `aeb7744d85d3f4c76726ab8b5e9c04b334b89bcd`.
The release fixes the missing in_app_update 4.2.5 lock entry and the Windows manifest preparer's local URL fallback. Existing dependency versions remain locked.
Publication and upgrade-check scripts are on `codex/release-1.0.13-48-publish`.

## Verified builds

- Web: https://github.com/StanTobechukwu/ripot_mvp/actions/runs/37279479768 — 147 tests passed, 1 emulator-only test skipped; release compiled.
- Android: https://github.com/StanTobechukwu/ripot_mvp/actions/runs/37279479836 — unsigned AAB, package com.nduaguba.report, target SDK 36, Billing 8.0.0, eight native libraries passed 16 KB alignment checks.
- Windows: https://github.com/StanTobechukwu/ripot_mvp/actions/runs/37279479747 — tests, compilation, installer, startup, and native guest report/PDF workflow passed.
- Upgrade/publication: https://github.com/StanTobechukwu/ripot_mvp/actions/runs/37280840516 — installed 48 over 47 without uninstalling; fictional saved PDF bytes remained unchanged and the report reopened from My Reports. Numeric Windows file-version fields were checked.

## Published

Windows: https://github.com/StanTobechukwu/ripot_mvp/releases/tag/windows-v1.0.13-48

Installer: `Ripot-Setup-1.0.13-48-windows-x64.exe`, 19,109,206 bytes.
SHA-256: `52d33fae1a96d5a8bf8220ceb35b4c9f325d7d138e8ec41a9515ae12ade8ac5d`.
The installer is unsigned. Live paid-account and full native Registry/image workflow testing remain outstanding; publication notes state these limits.
Build 47 requires manual download. Build 48 can prompt for a future higher Windows build using the website manifest.

## Prepared but not deployed/submitted

- `Ripot-Android-1.0.13-48-sign-on-Mac.zip`: existing upload key required on the release Mac. AAB SHA-256 `2fbf568b28be26cb720e69c7e753ba144088ac83ac7c36cc0c2defef93451345`, 56,610,057 bytes. Run `bash Sign-Ripot.command` in its android folder. Check that version code 48 is unused in Play Console, then upload only the SIGNED AAB to internal testing before production. No Play upload or submission was performed.
- `Ripot-Web-1.0.13-48.zip`: compiled web app with checked hashes, `release.json`, `version.json`, and `Deploy-Web.command`. Run `bash Deploy-Web.command` from its folder on the Firebase-authenticated Mac. Only `hosting:webapp` in project `ripot-4edf7` (site `ripot-web`) is deployed.
- `Ripot-Landing-1.0.13-48.zip`: original landing design retained, both Windows buttons updated to the verified GitHub release; `updates/windows.json` advertises build 48 and is configured for revalidation. Static checks passed. Run `bash Deploy-Landing.command` from its folder on the Firebase-authenticated Mac. Only project `ripot-landing` is deployed. No EXE is included in the hosted folder.

All four user-facing packages, including the standalone Windows installer, were saved and delivered. No Firebase credentials were present in the execution workspace, so neither Firebase deployment was performed. The Android upload key was not accessed. Do not describe these three remaining actions as already live.
