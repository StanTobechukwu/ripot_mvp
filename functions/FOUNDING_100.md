# Founding 100

The first 100 registered accounts to activate a Premium trial receive **84 days
total**, measured from their original trial start. Later accounts receive 21
days. A permanent Founder number does not grant lifetime Premium. A reinstall,
second device, or repeat request cannot restart the account's trial. Anonymous
Firebase sessions do not qualify.

The free trial is independent of Google Play's `founding-100-annual-25` offer.
New purchases of that discount remain disabled in the backend. Existing verified
purchases can still refresh or restore; one purchase token cannot move between
accounts. Normal monthly and annual subscriptions are unaffected.

## Server ownership

`ripot_internal/founding_100` contains `schemaVersion: 1`, `assignedCount`, and
`maxFounders: 100`. Its `members/{authUid}` subcollection retains each number and
the original trial dates. Do not delete members or recycle numbers when accounts
are removed. The access document is an account-readable projection; client rules
prohibit writing entitlement fields or accessing the internal register.

Allocation reads the register and membership records inside one transaction.
Missing initialization, duplicate numbers, or a counter mismatch stop new grants
until an administrator reconciles the records. An existing trial never consumes
a fresh slot automatically. The old `isEarlyUser` flag alone grants nothing.

## Audit and initialize before deploying

Use a trusted administrator environment with Application Default Credentials for
the intended Firebase project. Never commit credentials, audit JSON, account UIDs,
email addresses, or purchase receipts. The script does not read Play receipts.

From `functions/`:

```sh
npm ci
node scripts/founders.js --project YOUR_PROJECT --include-legacy-84-day-trials
```

This is a read-only dry run. Review the proposed accounts and original dates.
Legacy candidates must be registered, have matching account ownership, and have
an actual 84-day trial interval. Registration, a device record, or an early-user
flag alone is insufficient. Eligible legacy accounts are ordered by trial start;
ties use UID order. Existing valid Founder numbers are preserved.

After reviewing the output, apply the exact plan using its `reviewHash`:

```sh
node scripts/founders.js --project YOUR_PROJECT --include-legacy-84-day-trials \
  --apply --expected-hash REVIEWED_HASH
```

The transaction rechecks the plan before writing. It adds membership fields and
the registry only: paid status, trial dates, purchase verification, and existing
Premium expiry remain unchanged. Subsequent dry runs should show zero new legacy
candidates. Applying a freshly reviewed repeat run does not consume more slots.
If the account set or relevant trial records change, generate a new dry run.

Initialize the registry **before** deploying these functions. Keep the interval
between migration and deployment short. If the old backend grants a trial in
between, run and review the migration again before deployment; inconsistent
registers fail closed. Do not reset a mismatched counter to zero.

### Private console job when local Admin credentials are unavailable

The same `migrateFounders` transaction can run inside the Firebase project
without downloading a service-account key. Deploy the tested private operator
trigger and its explicit client-deny rule first:

```sh
firebase deploy --project ripot-4edf7 --only firestore:rules,functions:founderMigrationJob
```

In the Firebase console's Firestore **Data** tab, create a document in the root
collection `ripot_internal_founder_jobs` with an automatic document ID and one
string field, `action: preview`. Wait for `status: complete`; review `result`
including the existing count, eligible registered accounts, original trial
dates, proposed numbers, and `reviewHash`. The job is read-only. If its status
is `failed`, stop and investigate; do not guess a counter or a Founder number.

Create a second document in that collection with two string fields:
`action: apply` and `expectedHash: <the exact reviewed reviewHash>`.
The backend lists registered Authentication accounts afresh and rechecks the
plan in one Firestore transaction. If records changed, the job fails and you
must create another preview. If it completes, create a fresh `preview` document
and confirm `legacyCandidatesToAdd: 0`, a consistent Founder register, and
the preserved trial and paid fields before deploying the remaining functions.
The Firestore client rules deny all reads and writes to these jobs, including
signed-in app users. Keep the job results within the project console because
they include private account UIDs.

```sh
firebase deploy --project YOUR_PROJECT --only functions
```

After deployment, verify the existing founders' numbers and unchanged trial end
dates, the registry count, and `getBillingEligibility` returning
`founderDiscountEligible: false`. Do not activate a production trial merely as a
test: it permanently consumes a real slot. Release the Flutter update through
the app's normal release process to show the new trial wording and Founder badge.

Rollback: retain the membership ledger and account fields. Reverting code must
never reset the counter or delete trial history. An older backend does not keep
this ledger in sync, so suspend new activations or reconcile every old grant
before restoring the new backend.

## What the user audit means

The audit compares Firebase Authentication UIDs with account access documents
and historical `usr_` installation records. It separates linked installations,
unlinked installations, and registered accounts missing an access document.

Unlinked installations are **not unique people** and do not prove current use.
They may represent reinstalls, testing, or old versions. The current client does
not sync guest activity, so both current guest users and unique unregistered
people are reported as unknown. Do not infer these from Play subscriptions or
historical installation counts. The Founder change adds no guest tracking.
The separate optional reporting rollout is documented in `ACTIVITY_REPORTING.md`;
its observed-installation counts must not be treated as unique people.

## Tests

With Node 20, a compatible Firebase CLI, and Java installed:

```sh
npm run test:emulator
```

The tests use a `demo-` project and refuse to run against production. They cover
concurrent final-slot claims, repeated requests, trial duration, counter
corruption, legacy migration, preservation of paid access, purchase ownership,
and the disabled annual discount. Run Flutter access tests in the normal app
development environment:

```sh
flutter test test/features/access
```
