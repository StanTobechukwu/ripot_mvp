# Windows and web payment readiness — not a payment launch

Public availability and checkout remain disabled pending Microsoft approval,
company banking and a selected payment provider. Do not advertise an unapproved
Store listing or accept unverified manual-payment screenshots as entitlement.

## Country price reconciliation

Status: monthly and annual plans were inspected in Google Play Console on
31 October 2026. The saved report “Ripot-Country-Prices-2026-10-31.html” records
the displayed country prices, tax labels and remaining limitations. Both plans
are active. The Console overview lists 175 regions, while 174 named country rows
were visible per plan; the discrepancy remains unresolved. Existing legacy
cohort amounts were not inspected. No prices or offer states were changed.

Use that verified price inventory for provider setup. Compare like-for-like
checkout totals, not currency conversions. Windows/web price changes remain a
separate decision; no provider checkout or new prices are activated here.

## Integration contract to implement after provider selection

- Product: Premium monthly; account-owned access shared across supported apps.
- Account sign-in required before checkout. Server creates checkout session and
  binds it to the authenticated UID and a server-side regional price identifier.
- Entitlement is granted only from a verified provider event / server API, never
  from a return-page URL or a client-supplied amount or plan.
- Signed webhook verification, duplicate-event handling, renewal, cancellation,
  failed-payment/grace-period, refund and expiry cases must be tested in sandbox.
- Preserve existing paid time; prevent accidental overlapping subscriptions and
  explain which provider manages each subscription. Offer that provider's manage
  subscription route. Never cancel an existing subscription automatically.
- Continue bounded offline access using the existing account access cache. Manual
  backup, restore and access to existing reports remain available on Free.
- Before launch: approved Store identity/listing, verified settlement account,
  tax/currency treatment, receipts, refund policy, privacy update, real-device
  checkout/restore test and small monitored rollout.

No live provider keys, bank details, guessed Store product IDs or unverified
country prices are committed in this change.
