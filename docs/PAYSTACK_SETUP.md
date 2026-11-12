# Paystack Premium setup

Prepared 9 November; payment path and country pricing updated 12 November 2026. This branch is a **deployment candidate, not a live payment release**. It is based on the guided OGD release at `c7d1a48`, preserving its template changes. No production credentials, plans, webhooks, deployments or charges were created during preparation.

## What the integration does

- Web and Windows open hosted Paystack card checkout for monthly or annual Premium. Android continues to use Google Play.
- The server selects the price from a private catalogue. The client sends only the plan ID and billing market, with its authenticated Ripot session.
- The account email, UID, plan and billing market identify the purchase. No reports, patient data, card numbers or clinical text are sent to the payment functions.
- Only verified provider transactions grant access. A redirect, screenshot or client-reported success cannot unlock Premium.
- Signed webhooks and a payment ledger handle renewals, duplicate deliveries, cancellations, failed renewals and full refunds. Paid time from Google Play and Paystack is reconciled without one provider removing valid time from the other.
- Current trials remain unchanged. Checkout does not charge accounts during an active trial or with active paid access.
- Test payments use separate internal records and `ripot_test_user_access`; they cannot grant production Premium.

## Prices and international payments — updated 12 November 2026

The current selected route is **country-specific prices charged in NGN**, including eligible international cards, with NGN settlement to the company's existing Access Bank account. This supersedes the earlier proposal to start with USD settlement. Customer banks handle conversion; no live foreign exchange quote is promised.

Nigeria retains its previously approved **NGN 2,500/month and NGN 25,000/year**. Overseas amounts have **not** been approved. No suggested price from a conversation or test fixture is a production offer. Both setup and server validation require every enabled international NGN monthly/yearly price to be strictly higher than the corresponding Nigerian price, as the owner reconfirmed on 12 November.

The web screen asks for the customer's billing country/region and shows only a configured offer. The server owns amounts and validates the plan against that country. This selection is customer-declared; it is not proof of residence and does not prevent customers misdeclaring their country. No IP geolocation is used.

Configure overseas NGN prices only after the owner confirms both amounts. Put the approved offers in a private JSON array, with `country` (ISO two-letter code), `monthlyNgn` and `annualNgn` (decimal strings). Then append:

```text
--international-approved --international-currency NGN --country-prices /absolute/path/to/approved-country-prices.json
```

The script validates the complete file before network access, preserves the Nigerian prices, and creates separate recurring offers for each country. Without a file, **no overseas NGN offers are created**. It no longer silently gives every country the Nigerian price. A general USD fallback is supported for an explicitly approved future USD rollout, but is not part of this launch. Country-specific offers take precedence over a fallback.

The owner reported international-payment approval. Confirm the current Paystack dashboard settings before enabling production checkout. NGN collection does not require a Zenith USD domiciliary account. Direct USD collection remains a separate merchant approval and settlement decision.

References: [international payments](https://support.paystack.com/en/articles/2130690), [subscriptions](https://paystack.com/docs/payments/subscriptions/), [transactions](https://paystack.com/docs/api/transaction/), [webhooks](https://paystack.com/docs/payments/webhooks/).

## Operator prerequisites

Use an authorised development computer with Node 22, the Firebase CLI and Google Cloud CLI. Sign in to project `ripot-4edf7`. Obtain the registered test account's UID from Firebase Authentication; do not use an installation ID or email as its UID.

Keep all secret keys out of source code, chat, screenshots, shell arguments and Flutter assets. The frontend does not need a Paystack secret or public key because checkout is initialized by the server.

The setup script reads explicit local Google credentials and the Paystack key from Google Secret Manager. It checks for a local credential file before authentication and never falls back to a cloud metadata server.

```bash
firebase login
gcloud auth application-default login
npm ci --prefix functions
```

Required secrets:

| Secret Manager name | Value entered securely |
| --- | --- |
| `PAYSTACK_SECRET_KEY` | Matching Paystack test or live secret key |
| `PAYSTACK_WEBHOOK_SECRET` | Dashboard endpoint signing secret beginning `whsec_`; only if the dashboard still uses legacy signatures, the literal word `legacy` |

Modern `Paystack-Signature` headers use timestamped SHA-512 verification and a five-minute tolerance. Legacy `x-paystack-signature` headers use the API secret. Configuring a modern signing secret disables legacy fallback. Keep the server clock synchronized and confirm which signature mode the merchant dashboard actually sends.

## Set up test checkout first

From the repository root:

```bash
bash tools/deploy/Setup-Paystack-Secrets.command test
bash tools/deploy/Deploy-Paystack-Backend.command
node functions/scripts/paystack-setup.js --mode test --test-uid YOUR_TEST_UID
```

The owner created the following plans manually and confirmed **Test mode** on 9 November 2026. Provider-side amounts, currency and interval still need verification when connecting them:

| Offer | Expected amount | Supplied plan code |
| --- | --- | --- |
| Monthly | NGN 2,500 | `PLN_f4dbw4c8h3wjh0c` |
| Annual | NGN 25,000 | `PLN_m01ex335fgxv4i2` |

To select those exact plans, use this configuration command after saving the test secrets and deploying the backend:

```bash
node functions/scripts/paystack-setup.js --mode test --test-uid YOUR_TEST_UID --ng-monthly-plan PLN_f4dbw4c8h3wjh0c --ng-annual-plan PLN_m01ex335fgxv4i2
```

The setup fetches and checks each supplied code before writing the catalogue. An unknown code or a mode, amount, currency or interval mismatch stops setup; it does not silently create replacement plans. These test codes must not be reused for live checkout. These codes cover the Nigerian NGN offers only. Country-specific overseas offers need their own verified plans after their NGN prices are approved.

Enter keys only in the secure Firebase prompts. Deploying the backend alone does not enable checkout: the private catalogue must also exist.

Configure the **test-mode webhook endpoint** in Paystack:

```text
https://us-central1-ripot-4edf7.cloudfunctions.net/paystackWebhook
```

Subscribe it to `charge.success`, `subscription.create`, `subscription.not_renew`, `subscription.disable`, `invoice.update`, `invoice.payment_failed`, `refund.processed` and `charge.dispute.resolve`. Confirm a signed test event is accepted.

The return URL is fixed on the server:

```text
https://ripot-web.web.app/?premium=return
```

The candidate web app must be built and deployed before that screen contains the new payment controls. Do not point a production checkout at an unrelated preview domain. Test through a separate Firebase project before public deployment when a full isolated app release is needed; the setup script's project constant must then be deliberately changed, along with the app's Firebase configuration and return URL.

For this rollout use the country-specific NGN flags described above. Do not enable USD collection or use a proposed overseas amount without a separate decision.

## Verification before real payments

Verified release checks — 12 November 2026:

- 315 Flutter app tests passed (2 skipped), including the guided OGD workflow and payment/account-switch checks.
- 84 backend/emulator tests passed, including the lower Nigerian / higher international price rule, payment lifecycle and client access restrictions. One separate release run hit an intermittent emulator transaction error in an existing template-concurrency test; the same source passed the independent backend run and the release retry also passed.
- Flutter analysis completed without errors; existing warning/info diagnostics remain. The release web app compiled successfully.
- Phone/desktop landing layouts, compiled Premium entry/return links, template previews, hashes and downloads passed.
- The backend dependency audit reports zero known vulnerabilities after updating fast-xml-parser to 5.12.0.
- These are software checks with an emulator and mocked provider responses. No actual Paystack checkout, production credential installation, live deployment or charge occurred.

The earlier local Flutter bootstrap was blocked by automatic approval review after attempting cloud-metadata access. It was not retried locally. Validation instead ran on an isolated GitHub runner with metadata access blocked and no production secrets. This supersedes the 9 November note that the app had not been compiled or tested.

Validation/source: [payment release](https://github.com/StanTobechukwu/ripot_mvp/actions/runs/43264671713), [backend and template checks](https://github.com/StanTobechukwu/ripot_mvp/actions/runs/43264684355), [app compatibility checks](https://github.com/StanTobechukwu/ripot_mvp/actions/runs/43264684356). Runtime source: `063b3395e77232fbe5dd7aea98a97becaf3ad7d1`; the tested PR merge commit `578cd3fb02122e137846b36adad12de75811be96` has the identical Git tree.

For future changes, the corresponding development checks are:

```bash
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings lib test
flutter test --no-pub
flutter build web --release --no-pub
```

Also build and open the Windows app on Windows. Verify the Premium screen on mobile web and desktop, account switching during checkout, the return URL, cancellation management, fresh sign-in on another device, and that an Android build still presents Google Play checkout.

Using Paystack test mode, check success, a declined card, interrupted checkout and retry, a delayed webhook, renewal, cancellation and full refund. Test-mode status must never unlock the production app. Record the provider references in the private operator record, not a public issue. Do not make a real charge merely to complete a software test.

## Enable a limited live pilot

Only after those checks and merchant setup are complete:

1. Save the **live** API and matching live webhook signing secrets using `Setup-Paystack-Secrets.command live`.
2. Redeploy the payment functions so they use the new secret versions.
3. Configure live plans with `node functions/scripts/paystack-setup.js --mode live --pilot-uid YOUR_PILOT_UID`, plus the explicitly chosen international flags if applicable. This keeps sales disabled.
4. Configure and test the live webhook endpoint. Check settlement settings, published billing/privacy wording and the selected prices.
5. Rerun the same configuration command with `--enable-live` and the same `--pilot-uid`. Only that account can start checkout. Any real pilot purchase needs the payer's express authorization.
6. After the authorised pilot confirms receipt, account unlock, management, cancellation and settlement behavior, deliberately remove `--pilot-uid` while retaining `--enable-live` to open public checkout.

Never switch the production configuration back to test mode after live payment records exist; the script refuses that switch. Use a separate project for subsequent test-mode work. A secret-mode mismatch fails checkout and must be corrected before accepting payments.

## Operations and known limits

- Set `enabled: false` in `ripot_internal/paystack_config` to pause new sales. This preserves subscription management, refresh and webhook processing for existing customers.
- Keep disabled old plans in the catalogue. Changing the price of an existing Paystack plan is not an implemented upgrade/downgrade workflow; create and configure a new plan instead.
- Pending checkout reuses the same reference to prevent accidental duplicate subscriptions. The UI disables the other plan while a checkout is pending. If an initialization is irrecoverable, support must verify its provider state before clearing the pending fields; never clear them simply because a customer closed the browser.
- Failed renewals do not extend access. Cancellation preserves the paid period. Full refunds/reversed payments revoke only that payment's grant; partial refunds require an explicit support decision and do not automatically shorten access.
- There is no scheduled reconciliation job in this change. Signed webhooks reconcile events, and opening/refreshing the account verifies the provider state. A missed event plus a failed provider refresh can temporarily delay access; the existing 72-hour freshness bound is retained.
- Chargebacks are reconciled when Paystack marks the transaction reversed. Review unresolved disputes in the provider dashboard; do not assume every dispute immediately revokes access.
- An ordinary client cannot read internal payment maps, write entitlements, set prices or access the test entitlement collection. The existing deny-by-default Firestore rules already cover these collections.
- Account deletion does not cancel provider renewals. Follow the existing support deletion process and explicitly check both payment providers before deleting a paying account.
- No customer announcement has been sent and no landing-page claim of live availability has been published. Publish the prepared privacy/terms updates together with the verified payment release.
