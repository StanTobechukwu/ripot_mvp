# Trial prompts, finalized-report limits and Windows access

Prepared against the latest account-welcome branch, preserving the updated
registry and Windows account implementation. This is a review build, not a
Google Play or public Windows release.

## User-facing behaviour

- Free: up to 10 stored final PDFs per device. Premium/trial: up to 100.
- Editable drafts do not count. Saving a draft before finalizing cannot bypass
  the final-PDF limit. Finalization is serialized and rechecks the current limit.
- Expiry removes no reports or drafts. Existing PDFs remain readable/exportable,
  and a saved PDF can be replaced without consuming another slot. Creating a
  new final PDF requires available capacity. Restoring a backup is not blocked.
- Eligible, signed-in accounts get an explicit free-trial activation action.
  Guests sign in to check eligibility; login alone does not consume a trial.
  Used trials get subscription options. Verification failures offer reconnection.
- Records, Registry and letterhead continue the requested action after a
  successful activation. Adding a finalized PDF to Records remains optional.
- Custom letterhead remains Premium pending a separate product decision.
- Google Play remains the payment channel for the initial Windows pilot. The
  same Ripot account carries verified access to Windows. Windows-only checkout
  is deferred; a Windows-only customer cannot purchase directly in this build.

## Verification and offline access

- Account loading checks access on startup. A lifecycle wrapper rechecks on
  foreground/resume and every 15 minutes during active use, with one-minute
  coalescing and no duplicate in-flight refresh. Explicit refresh stays available.
- Offline access lasts at most 72 hours since verification and never outlasts
  the actual trial/subscription expiry. Offline cache writes do not extend it.
- Paid access also requires a Google Play verification timestamp within that
  window. Reading a stale Firestore document cannot renew the allowance when
  Play verification is failing.
- Windows stores its account-scoped access cache in encrypted storage and does
  not accept entitlement values from ordinary preferences. Old Windows caches
  require a new online check. Secure-storage failure permits online work but
  cannot grant access from an unprotected fallback cache.
- Missing expiry for ordinary paid access, wrong-account cache, substantial
  clock rollback, expired verification and server revocation fail closed for
  Premium features. Signed-out users cannot inherit another account's plan.
- Existing local work is unaffected by access checks. UI expiry timers update
  feature availability even during a long-running session. A still-running
  trial blocks new subscription purchases even when its offline lease expires.

## Verification and release gates

CI covers repository finalization/quota/concurrency, preservation after expiry,
trial-first prompts and explicit consent, rejected activation, foreground
refresh/coalescing, UID isolation, stale paid verification, encrypted-cache
selection, clock rollback and existing Windows account/billing regressions.

Before release, test on an actual Windows installation using a real paid Ripot
account: cold start, minimize/restore, offline restart within the allowance,
renewal/expiry, sign-out/account switch, and secure-storage persistence. Confirm
that the deployed `refreshPlayEntitlement` endpoint updates
`billingLastVerifiedAtIso` and that the Firestore entitlement is readable by its
owner. No live account was charged, refunded, cancelled or modified by this work.

This bounds normal offline use and protects cached values from ordinary
preferences editing. It is not a claim of tamper-proof DRM on a user-controlled
computer. No Windows checkout, payment-provider webhook or new deployment is
included.
