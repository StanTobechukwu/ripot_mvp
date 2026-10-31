# Windows and web payment readiness — not a payment launch

Public availability and checkout remain disabled pending Microsoft approval,
company banking and a selected payment provider. Do not advertise an unapproved
Store listing or accept unverified manual-payment screenshots as entitlement.

## Country price reconciliation

Status: Google Play Console session is signed out; current prices not verified.
The supplied historical Nigeria order shows NGN 2,500/month. It is not evidence
of every country's current price, offers or subscriber cohorts.

Export the current `ripot_premium` monthly base-plan country prices from Play
Console. Preserve region, currency, tax inclusion, billing period, regular price,
active offers and legacy cohorts. Compare like-for-like checkout totals, not
currency conversions. Keep Windows/web at the same local customer price as the
regular Play plan initially; any increase needs a separate explicit decision.

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
