# Microsoft Store Premium setup

Updated 8 November 2026 for Ripot: Clinical Reports & PDF (`9P91S5JQ1FK0`).

## Status

The existing published app has no Microsoft checkout. This branch adds a draft
Windows Store bridge, monthly/annual purchase UI, authenticated verification,
purchase ownership checks, restoration, and shared entitlement reconciliation.
Checkout is disabled by default. No Store add-ons or prices have been published,
no credentials have been configured, and no production backend has been deployed.
Partner Center returned a connection error before sign-in from this session.

The landing-page changes are separately prepared in PR #10. Do not change the
landing page to advertise live Windows purchases until the rollout below passes.

## Existing Windows users before checkout launches

Verified against the current release source on 8 November 2026:

- Installing the app starts with Free; downloading does not grant permanent
  Premium or start a paid subscription.
- Registered users can explicitly activate an eligible account trial. The first
  100 eligible activations receive 84 days; later eligible activations receive
  21 days. The server preserves the original trial dates and previous-use record.
- Trial expiry returns the account to Free limits even while Windows checkout
  is unavailable. Existing reports and drafts remain available. New final PDF
  saves and Premium features are subject to the Free limits after expiry.
- An existing verified Premium entitlement is recognized when signing in with
  the same Ripot account. Clinical data remains local to each device.
- Microsoft checkout requires a future Store app update plus backend verification.
  Keep the existing MSIX identity, preserve the local data store and account trial
  history, and test an upgrade from the current Store version before release.
- Users must choose to buy Premium. Existing installations are not automatically
  charged. Users who remain on the old version will not see the new checkout;
  their original trial expiry and Free limits still apply.

The landing-page FAQ explains this without promising a checkout launch date.
This source review is not a Windows runtime purchase test.

## First Partner Center step

Open **Apps and games → Ripot: Clinical Reports & PDF → Add-ons → Create a new
add-on**. Check whether **Subscription** appears in **Product type**. Microsoft's
subscription API documentation still describes account provisioning restrictions;
the actual choices in this developer account must be checked.

If Subscription is absent, ask Partner Center support about enabling it. Do not
substitute a Forever durable purchase for a recurring plan. Fixed-duration,
non-renewing access or another payment provider would be a separate decision.

## Proposed catalogue — not published

| Field | Monthly | Annual |
| --- | --- | --- |
| Product type | Subscription | Subscription |
| Developer product ID | `ripot_premium_monthly` | `ripot_premium_annual` |
| Customer title | Ripot Premium Monthly | Ripot Premium Annual |
| Subscription period | Monthly | Annually |
| Additional Store free trial | None | None |
| Price | Confirm current Android monthly price and matching market prices | Confirm current Android annual price and matching market prices |
| Microsoft-assigned Store ID | Record after creation | Record after creation |

These developer product IDs are proposed names, not Microsoft-assigned Store IDs.
Keep Ripot's existing account-based trial (84 days for eligible Founding 100
accounts; 21 days for later eligible accounts). Adding a separate Store trial
could give the same user another free period. The existing Ripot trial does not
automatically charge when it ends.

Confirm currency, prices and markets before publishing. Do not publish the
default Free price: Microsoft's subscription documentation says prices cannot
be raised after publication. The billing period also cannot be changed then.

Suggested monthly description (replace “monthly” with “annual” for annual):

> Unlock Ripot Premium with a monthly subscription. Use your own letterhead,
> remove Ripot branding, add up to 12 images per report, save up to 20 custom
> templates, use advanced report layout and Report data, schedule automatic
> backups, and copy complete reports without the Free copy allowance. Premium
> has no saved-PDF count limit, subject to available device storage. A Ripot
> account is required. The subscription renews automatically until cancelled.
> Manage renewal through your Microsoft account. Clinical reports stay on your
> device; subscription access does not sync clinical data between devices.

## Configuration and release steps

1. Confirm **Subscription** is available in Partner Center, then create the two
   add-ons above. Confirm prices, currencies, markets and renewal terms before
   publishing. Record both 12-character Microsoft Store IDs. Do not use the
   developer product ID strings in the Store ID fields.
2. Register a server application in Microsoft Entra ID and associate its client
   ID under the Ripot product's **Services → Product collections and purchases**.
   Store its secret with `firebase functions:secrets:set MICROSOFT_CLIENT_SECRET
   --project ripot-4edf7`. Use the secure local prompt, never chat or source files.
3. Set deployment parameters (non-secret values) for project `ripot-4edf7`:

   | Parameter | Value |
   | --- | --- |
   | `MICROSOFT_BILLING_ENABLED` | `false` initially |
   | `MICROSOFT_TENANT_ID` | Entra tenant GUID |
   | `MICROSOFT_CLIENT_ID` | Associated Entra application GUID |
   | `MICROSOFT_MONTHLY_STORE_ID` | Published monthly add-on Store ID |
   | `MICROSOFT_ANNUAL_STORE_ID` | Published annual add-on Store ID |

4. Deploy the four Microsoft callables plus the updated Play verification and
   report-copy functions. Preserve Firestore's existing deny-by-default rules;
   clients must never read/write `ripot_internal_microsoft*` collections.
5. Build the Windows app with the existing package identity and
   `RIPOT_MICROSOFT_STORE=true`. The candidate version is `1.0.26+61` (Store `1.0.26.0`), above the
   current `1.0.25.0`. Microsoft reserves the fourth version component.
6. Enable billing only for the Store-licensed test release after both published
   products and backend credentials are ready. Test the complete acceptance list
   below with actual Store purchases. CI compilation and mocked Microsoft API
   responses cannot prove a real charge, renewal or refund works.
7. Publish the prepared privacy-policy update with the billing launch. It names
   Microsoft Store and the subscription/ownership/verification data. For an
   account-deletion request, use the operator procedure below.
8. Submit the tested higher-version MSIX to Microsoft. After approval, users
   receive it through Store updates. Only then update landing-page purchase copy.

Only the restricted purchase-key creation ticket is sent to Windows. The broad
Store service token and Entra secret remain on the backend. A native checkout
success never grants Premium directly. The backend queries Microsoft and binds
both recurrence and beneficiary to a single Ripot UID; account switching cannot
reuse that purchase. Do not enable a second Store free trial.

The backend renews a saved Microsoft identity key when it is within seven days
of expiry during an entitlement refresh. If a user stays away until the key has
expired or Microsoft revokes it, **Restore purchases** on Windows reconnects the
Store identity. Failed verification does not extend the 72-hour allowance. No
scheduled renewal job is included in this change.

Verified entitlements from both stores are reconciled transactionally. Expiry
or refund in one store preserves a still-active, recently verified purchase in
the other, and original trial dates are preserved. Shared access uses the new
`premiumEntitlementExpiresAtIso` field, so Android/web also need this client
update to recognize Microsoft purchases. Older builds retain their existing
behavior and cannot perform Microsoft checkout.

Required account inputs remain: subscription eligibility, prices/markets, both
Microsoft-assigned Store IDs, and authorized server verification credentials.
Do not paste secrets or passwords into chat or source. If subscriptions are
unavailable for this account, leave this integration disabled and decide on an
alternative payment provider before changing the customer offer.

## Operator account deletion

After verifying the account-deletion request, explain that deleting a Ripot
account does not cancel a Microsoft Store subscription and provide the Microsoft
subscription-management link. Do not promise cancellation from a database delete.
Review the active payment status with the requester before removing its Ripot link.
Remove that UID's `ripot_internal_microsoft` document (including its key),
`ripot_internal_microsoft_limits` document, and all
`ripot_internal_microsoft_owners` documents whose `uid` equals the deleted UID,
as well as the account's existing access/copy/template records under the normal
support procedure. Do not put verification keys in support replies or logs.
This release does not add automatic account deletion or cancel subscriptions.

## Acceptance checks

- Signed-out users sign in before checkout. Active trials/subscriptions do not
  trigger accidental duplicate purchases.
- Plans display the Store price, currency and renewal period.
- Failed/cancelled purchases grant nothing. Purchase and restore unlock Premium
  only after backend verification.
- One Microsoft subscription cannot be claimed by two Ripot accounts.
- Premium and unlimited copying work on supported platforms for the same account.
- Renewal, expiry, refund, sign-out and account switching respect server access
  and bounded offline verification. Existing reports survive expiry.
- Existing Android billing, account trials and Free copy limits still work.

## Official references

- [Create an add-on](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/add-on/what-are-add-ons)
- [Subscription add-ons](https://learn.microsoft.com/en-us/windows/uwp/monetize/enable-subscription-add-ons-for-your-app)
- [Subscription verification and provisioning](https://learn.microsoft.com/en-us/windows/uwp/monetize/get-subscriptions-for-a-user)
- [Manage entitlements from a service](https://learn.microsoft.com/en-us/windows/uwp/monetize/view-and-grant-products-from-a-service)
- [Desktop StoreContext](https://learn.microsoft.com/en-us/uwp/api/windows.services.store.storecontext)
