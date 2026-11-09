# Paystack Premium setup

Prepared 9 November 2026. This branch is a **deployment candidate, not a live payment release**. It is based on the guided OGD release at `c7d1a48`, preserving its template changes. No production credentials, plans, webhooks, deployments or charges were created during preparation.

## What the integration does

- Web and Windows open hosted Paystack card checkout for monthly or annual Premium. Android continues to use Google Play.
- The server selects the price from a private catalogue. The client sends only the plan ID and billing market, with its authenticated Ripot session.
- The account email, UID, plan and billing market identify the purchase. No reports, patient data, card numbers or clinical text are sent to the payment functions.
- Only verified provider transactions grant access. A redirect, screenshot or client-reported success cannot unlock Premium.
- Signed webhooks and a payment ledger handle renewals, duplicate deliveries, cancellations, failed renewals and full refunds. Paid time from Google Play and Paystack is reconciled without one provider removing valid time from the other.
- Current trials remain unchanged. Checkout does not charge accounts during an active trial or with active paid access.
- Test payments use separate internal records and `ripot_test_user_access`; they cannot grant production Premium.

## Prices and international payments

The saved country-pricing record dated 31 October 2026 confirms Nigeria at **NGN 2,500/month and NGN 25,000/year**. These are the setup script's local defaults, represented as 250000 and 2500000 kobo.

The record confirms **USD 5.99/month and USD 59.99/year for the United States**, but does not establish those as the agreed web price for every overseas country. No global USD price has been approved or enabled in this branch. Do not copy the older USD 4.99 new-country default into an existing US price.

For a Nigerian Paystack business:

| Option | Checkout currency | Required merchant setup |
| --- | --- | --- |
| Nigerian customers | NGN | Activated Nigerian Paystack business |
| Foreign cards paying the Nigerian price | NGN | International payments approved/enabled; customer bank converts |
| A separate overseas price | USD | International payments and USD collection approved, including the eligible Zenith USD domiciliary settlement account |

The current UI offers **Nigeria / Outside Nigeria**. The overseas offer can use NGN or a confirmed USD price. This is not a full country-by-country regional-pricing engine, and it does not charge directly in GBP, EUR, AUD or CAD. Checkout displays the actual charged currency and warns that the customer's bank may apply conversion and fees. Do not advertise a currency based only on the customer's location.

International checkout is disabled by default. Before enabling it, confirm the setting in Paystack **Settings → Preferences → Accept international payments** and, for USD, the approved USD settlement account. Card acceptance remains subject to the issuer and Paystack; recurring American Express payments are not supported by this integration.

Primary references checked during preparation:

- [Paystack international payments](https://support.paystack.com/en/articles/2130690)
- [Subscriptions and supported recurring methods](https://paystack.com/docs/payments/subscriptions/)
- [Transactions API and amount subunits](https://paystack.com/docs/api/transaction/)
- [Webhook signature verification](https://paystack.com/docs/payments/webhooks/)

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

The setup fetches and checks each supplied code before writing the catalogue. An unknown code or a mode, amount, currency or interval mismatch stops setup; it does not silently create replacement plans. These test codes must not be reused for live checkout. International approval was last shown as **Requested**; international checkout remains disabled until approval and the overseas pricing choice are confirmed.

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

For an approved foreign-card offer charged in NGN, append:

```text
--international-approved --international-currency NGN
```

For approved USD collection and **separately confirmed** overseas pricing, append:

```text
--international-approved --international-currency USD --usd-monthly CONFIRMED_PRICE --usd-annual CONFIRMED_PRICE
```

`CONFIRMED_PRICE` is a decimal dollar amount, not cents. These placeholders are intentionally not executable prices. The script validates prices before creating plans, reuses matching provider plans and retains obsolete plan codes as disabled entries for existing-payment verification.

## Verification before real payments

Automated preparation checks:

- **74 backend tests passed**, including payment ownership/amount/currency checks, duplicate events, replay safety, paid-period expiry, refunds, foreign-card NGN checkout, missing-event recovery, isolated test access, provider freshness and Firestore permissions. The landing-page link/content checker also passed.
- **3 additional setup tests passed** after the owner supplied the test plan codes: exact-code selection despite differing names, rejection of swapped or live plans and mismatched prices, and no silent replacement of unknown codes.
- Local Dart formatting parsed the new controller, widget and test source. JavaScript syntax, shell syntax and diff checks were run.
- **Flutter analysis, app tests and compilation have not run.** Automatic approval review blocked Flutter's version/bootstrap command because it tried to contact the environment's cloud metadata service, which can expose instance credentials. That rejected execution was not retried. Offline dependency resolution also could not complete because the Flutter package cache was empty. Run the app validation on an approved development environment before releasing. The preparation commit skips automatic CI to avoid indirectly rerunning the blocked Flutter execution; it must not be treated as a verified release.

On that approved development environment:

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
