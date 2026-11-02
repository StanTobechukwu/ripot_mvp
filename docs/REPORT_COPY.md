# Copy report

Version 1.0.25+60 uses the same Flutter implementation on Windows, Android and
web. Preview includes Copy report; copying does not finalize or modify a draft.
The text includes the draft marker, title, report date, enabled subject fields,
all visible paragraphs, units, nested findings, notes and typed clinician details.
Guided OGD reports use the same presentation and anatomical ordering as the PDF.
Record-only values and inactive conditional fields are excluded. Images,
signature images and letterhead layout require PDF export.

## Allowance

- A registered Free account gets 50 distinct text versions in total, not monthly.
- Re-copying identical text is free, including after reinstall, restoring a
  backup, switching devices or duplicating a draft. Changing report text uses
  another allowance; the draft ID and save timestamps do not define identity.
- The remaining count is visible in Preview. Notifications at 10, 5, 1 and 0
  remaining link to the existing Premium/trial flow. Previously authorized free
  versions remain copyable at zero.
- Active Premium/trials include unlimited copying. Copying does not activate,
  extend or restart a trial. Versions copied only during Premium are not added
  to the Free ledger; copying them after expiry uses the remaining Free allowance.
- New Free authorizations require internet. Verified Premium retains the
  existing bounded offline entitlement (at most 72 hours, also bounded by plan
  expiry); it does not acquire an unlimited permanent local flag.
- The transaction authorizes a version before clipboard access. If the clipboard
  fails, retrying unchanged text costs no extra credit. A 60-second in-memory
  authorization allows retry with a fresh browser gesture. A failed authorization
  never writes report text to the clipboard. Double taps are serialized.

## Backend and release order

`getReportCopyAllowance` and `authorizeReportCopy` use registered Firebase Auth
identities, including the existing Windows REST callable adapter. Only an
account-scoped SHA-256 fingerprint is sent; never send report text, patient data,
report IDs, client counts or client entitlements. Transactions enforce the cap
and deduplicate concurrent requests across devices. `ripot_copy_allowances/{uid}`
is server-only and excluded from device backups. Invalid ledgers fail closed.

Before distributing this client, deploy the two functions to `ripot-4edf7` and
publish the updated privacy page on the landing site. The rules change explicitly
denies access; the existing catch-all already denies this new collection. Review
and deploy the full rules file only as part of the normal rules release process.
Function deployment command from the repository root:

```sh
firebase deploy --project ripot-4edf7 --only functions:getReportCopyAllowance,functions:authorizeReportCopy
```

The functions runtime and emulator CI now use Node.js 22. Google lists Node.js 20
as decommissioned on 30 October 2026 in its [runtime support schedule](https://docs.cloud.google.com/functions/docs/runtime-support).
Changing source configuration does not migrate already-deployed functions;
review their runtime and redeploy the existing endpoints as a separate release
operation using the tested source.

Use a test account to verify the deployed functions from Windows and web before
Store submission. A missing backend produces a retry message and does not grant
free copying. CI tests the emulator, not production deployment. Include the copy
ledger in the existing support-managed account deletion procedure.

Windows and web currently recognise verified Premium accounts but do not offer
subscription checkout. The copy upgrade action opens the existing Premium screen;
it does not create a payment integration. Complete and test that purchase path
before relying on the Free copy limit to convert users on those platforms.

## Limits of enforcement

This is an account allowance for the official app, not DRM. It does not prevent
new-account abuse, modified clients, screenshots, manual copying or text extraction
from exported PDFs. Existing Free editing/PDF access and saved-report capacity
are unchanged; deleting a saved PDF still frees a storage slot. A lifetime cap on
report creation/export would be a separate product decision, not an implicit
change to this feature.

Automated checks cover complete text, excluded fields, no truncation, fingerprints,
guest/forged requests, account changes, clipboard failures, concurrent requests,
the cap, expired trials and paid verification, and private Firestore rules.
