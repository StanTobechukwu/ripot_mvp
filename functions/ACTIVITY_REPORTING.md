# Installation activity and data clarity

## What is live and what this release changes

The Firestore rules were published on 2026-09-27 and verified against the tested
file. Existing access, template, app-config and internal rules are unchanged.
The new collection has an explicit recursive client deny. The previous default
deny already prevented direct access; this makes the reporting contract explicit.
It does **not** make old app versions send telemetry or restore missing history.

The backend endpoint and Flutter sender in this commit still require deployment
and a normal app release. Reporting is disabled in builds unless
`RIPOT_ACTIVITY_ENABLED=true` is supplied. Do not label the rollout complete
until a Play-installed release produces a verified observation.

The earlier data gap began when the May 10 rules required Firebase Auth, while
the guest writer still used an unauthenticated local installation ID. Guest
write failures were swallowed. The current access writer deliberately skips
guests. Reopening entitlement writes would undo established protections.

## Reporting contract

`recordInstallationActivity` requires App Check and the registered Ripot Android
app ID. It accepts exactly five fields: schema version, a persistent random
installation secret, platform, app version and build number. It rejects extra
fields, including account IDs, timestamps, entitlements and patient content.

The server hashes the random secret for the document ID. It stores first/last
observation times from its own clock, a commit timestamp, observed UTC days,
app version/build, and verified sign-in state. When Firebase Auth is present,
the account link comes from the verified token. Signing out preserves the fact
that this installation was previously linked. Anonymous Auth is not enabled or
created. No report, template, patient, email, location or purchase content is
included. The raw secret is not stored or logged by the handler.

Guests and accounts cannot read or write the collection directly. Only the
Admin SDK handler writes it. The handler never touches access records, trials,
Founder membership, templates or billing. App Check is enforced **only** on
this new callable, not project-wide or on existing clients' services.

Foreground/start/resume/auth-change reporting uses a six-hour heartbeat, plus
new UTC days and identity/version changes. Retries are idempotent. Failures
back off and preserve a local diagnostic code/time in SharedPreferences; they
never interrupt offline work. The Account sheet includes an activity-sharing
switch. Turning it off stops future requests but does not delete past records
or cancel an already in-flight request. The persistent ID remains stable across
sign-in/out, app updates and temporary opt-out; reinstall/data reset or backups
can affect installation identity.

## Counts that can be trusted

The read-only audit prints aggregate numbers without UIDs, emails or receipts:

```sh
cd functions
npm ci
npm run activity:audit -- --project ripot-4edf7
```

Run it from an administrator environment with Application Default Credentials.
It reports Firebase accounts with a linked sign-in provider separately from
providerless entries (which can be anonymous or custom-auth accounts),
and counts Founders only from a consistent permanent register. A missing or
inconsistent register is **unknown**, not zero confirmed Founders.

For activity, it separates installations never observed signed in, previously
signed-in installations now seen as guests, and installations last seen signed
in. It reports totals since rollout, last 24 hours, 7 days and 30 days, active
app versions and the last observation timestamp. No samples and no samples in
48 hours are explicit statuses. A stale status is a reason to investigate,
not proof of either a system fault or inactivity.

These are observed installations, **not unique people or all-time Google Play
installs**. An unlinked installation does not prove its user has never created
an account elsewhere. Old versions, opt-out, offline use, unsupported platforms
and failed attestation are absent. Historical `usr_` records stay separate;
never add them to registrations or new activity as a total user count. Missing
May-to-rollout guest events cannot be reconstructed.

## Rollout

1. Review and register the Android app with Firebase App Check / Play Integrity
   using the Play app-signing SHA-256 certificate. Verify the Firebase project
   linked in Play Console. Keep Firestore/Auth/other existing service enforcement
   unchanged. The current Ripot Android app is not registered; its form requires
   the SHA-256 fingerprint and acceptance of Google's displayed API terms. No
   attestation provider or service enforcement was enabled during this work.
   Do not use debug-provider tokens in a public release.
2. Deploy **only** the activity callable from the repository root:

   ```sh
   firebase deploy --project ripot-4edf7 --only functions:recordInstallationActivity
   ```

   Do not deploy all functions as part of this step: the separate Founding 100
   change requires the reviewed ledger migration in `FOUNDING_100.md` first.
3. In the normal Flutter build environment, run `flutter pub get` and commit the
   generated lockfile; run analysis, existing access tests, and Android build
   validation. New dependencies are pinned to match the existing Firebase SDK.
   No dependency resolution, Flutter test, or release build is claimed here.
4. Update the app's privacy disclosure and Play Data safety answers for basic
   activity and account linkage. Publish an internal test build with a new
   version/build number and `--dart-define=RIPOT_ACTIVITY_ENABLED=true`.
5. On a Play-installed build verify guest launch, repeat launch, sign-in,
   sign-out, opt-out, offline use and reconnection. Expect one installation
   through auth transitions; verify first-seen stability, server time, existing
   report creation, sync and paid access. Test with an existing account; do not
   consume a new Founder slot just to test reporting.
6. Run the audit. Confirm the first live observation and expected version before
   promoting the build. Check callable errors and App Check rejected requests;
   watch the audit's freshness timestamp after rollout. A quiet report alone
   cannot distinguish opt-out/inactivity from collection failure.

Rollback: turn off reporting in the next release by omitting the build flag, or
disable only this new callable. Existing app features continue working when the
reporting endpoint fails. Retain the private collection and prior rule history;
no data migration or entitlement rollback is needed.

## Validation

22 backend/emulator checks passed on 2026-09-27, including six activity checks,
five Firestore permissions regressions, and all eleven existing Founder checks:

```sh
cd functions
npm run test:emulator
```

Tests refuse production projects. They cover unauthenticated and cross-account
denial, sensitive-field rejection, repeated/concurrent guest observations,
verified account linkage, unchanged paid/Founder records, existing template
operations, and empty/stale report semantics.

Deployment limitations in this workspace: GitHub writes returned HTTP 403 and
Firebase Cloud Shell showed Site Unavailable. Flutter setup was blocked by
automatic approval review after the bootstrap attempted an instance-metadata
connection; it was not retried or bypassed. The live rules update succeeded,
but no new function or app build has been deployed here.
