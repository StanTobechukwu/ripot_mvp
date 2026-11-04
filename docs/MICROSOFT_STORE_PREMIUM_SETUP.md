# Microsoft Store Premium setup

Prepared 4 November 2026 for Ripot: Clinical Reports & PDF (`9P91S5JQ1FK0`).

## Status

The landing page changes add the Microsoft Store download option. They do not
enable payments. Windows currently recognizes an existing Ripot account's
verified Premium access, but the billing provider purchases through Google Play
on Android only. No Microsoft add-ons, prices or credentials were created in
this change. Partner Center could not be reached from the working session.

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

## Integration still required

| Area | Required work |
| --- | --- |
| Windows runner | Add a `Windows.Services.Store` bridge with the owning window handle, product lookup, purchase and restore. Keep the existing MSIX identity. |
| Billing provider and upgrade screen | Add Windows plans with localized Store prices, Ripot sign-in, cancellation/error handling and Manage subscription. Preserve Android billing. |
| Account transport | Use the Windows REST account session for authenticated calls; the Cloud Functions Flutter plugin does not implement Windows. |
| Backend | Associate the appropriate Entra application with the Store product. Store verification credentials only in server secrets. Verify purchases with Microsoft and bind each subscription to one Ripot UID. Never grant access from a client success flag. |
| Access refresh | Support Microsoft verification/expiry alongside Play, without an expired plan revoking another active plan. Preserve the maximum 72-hour offline verification window and subscription expiry. |
| Report copying | Extend the server's paid-access check to Microsoft purchases; it currently explicitly checks Google Play entitlement. |
| Release | Build a new MSIX with a higher three-part version, test through a Store-licensed Windows installation, then submit for certification. Self-signed CI installation does not validate real checkout. |

Required inputs: both Microsoft-assigned Store IDs, confirmed prices/markets,
subscription eligibility, and authorized server verification credentials. Do not
paste client secrets or test passwords into chat or source. Do not advertise
Microsoft checkout as available until integration and deployment are complete.

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
