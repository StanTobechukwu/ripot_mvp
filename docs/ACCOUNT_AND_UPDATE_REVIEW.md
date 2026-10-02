# Account entry, updates and access review

Prepared from the current Windows source, version 1.0.11+46, retaining the updated
registry. This branch is a reviewable change, not a published app release.

## Opening sign-in screen

An unsigned-in installation sees the existing sign-in form at startup, with
Create account and Continue without an account. After signing in, registering or
choosing to continue as a guest, the choice is remembered on this installation.
Subsequent launches go straight to reports. Restored signed-in sessions skip the
welcome screen. If account services are not configured, local reporting opens.
Existing guest installations see the introduction once after this update.

The existing account icon remains. There is no additional home-screen sign-in
button, update button or update banner. The previously proposed button/banner
implementation was removed following the user's revised direction.

No sign-in action automatically starts a trial or uploads patient reports.
Existing authentication, entitlement and data-storage behavior remains intact.

## Android update prompts

Use Play Console: Test and release → App bundle explorer → Recovery tools →
Prompt users to update. Select the OLD app bundles users should move from and
review eligibility/targeting before initiating the action. A newer compatible
release must be available on the relevant tracks. App Signing and App Bundles
are required; additional restrictions apply after signing-key upgrades and with
certain Play protections. This action has not been activated by this change.

Google's prompt appears full-screen when targeted users open the app. Users can
dismiss it, but it repeats on cold restarts. It can target already-published
versions without adding update code to those versions. If a gentler routine
prompt is desired later, Play's in-app update API needs an app implementation;
it does not require a permanent update button.

## Current saved-report behavior

Free permits 10 saved items; trial/Premium permits 100. This is a stored-item
allowance, not a monthly generation quota. PDF finalization counts all list
entries, including drafts, but rejects only an ID not already saved. Draft
save/autosave does not enforce the same check. Saving a draft first therefore
bypasses that new-report limit. This inconsistency is identified, not changed.

Trial expiry does not delete excess reports or PDFs. Existing IDs are exempt
from the PDF-save count check, although other Premium features become gated.
Records and Registry navigation are currently Premium-gated after expiry.

Recommended policy for a separate decision: count finalized PDFs, preserve
draft saving and existing excess work, and enforce the limit at first
finalization consistently. Do not delete clinical work on downgrade.

## Windows access and billing

Windows uses the same Ripot account's server-owned trial/Premium status. The
backend verifies Google Play purchases; checked-in Firestore rules allow clients
to update only harmless access-document metadata, not plan/expiry fields.
Sign-out removes local account access; account caches are UID-scoped. The
current cache expires at the recorded trial/paid-through date, with no separate
short maximum offline verification age. A bounded verification window and
tamper-resistant entitlement cache need further hardening, particularly for
annual subscriptions. Live paid-account testing on Windows is still required.

Currently a user subscribes in Android, signs into the same Ripot account in
Windows and refreshes Premium access. Windows-only checkout is not implemented.
A future web checkout must verify payment on the server and update that same
account entitlement, including renewals/refunds/expiry. Signing in does not
transfer report or registry data between devices.

Sources:
- https://support.google.com/googleplay/android-developer/answer/13812041
- https://developer.android.com/guide/playcore/in-app-updates
- https://developer.android.com/google/play/billing/security
