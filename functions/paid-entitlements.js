'use strict';

// Server-only reconciliation. Expiring one store must not revoke a verified
// purchase from the other store, or restart/erase the account's original trial.
const FRESH_MS = 72 * 60 * 60 * 1000;
const AUTHORITIES = { google_play: 'google_play_verified', microsoft_store: 'microsoft_store_verified' };
const millis = value => Date.parse(value || '') || 0;

function reconcilePaid(current, provider, entry, now = new Date()) {
  if (!AUTHORITIES[provider]) throw new Error('Unknown billing provider');
  const providers = { ...(current.verifiedPaidEntitlements || {}) };
  // Migrate an existing Play entitlement on its first reconciled write.
  if (!providers.google_play && current.entitlementAuthority === AUTHORITIES.google_play) {
    providers.google_play = {
      entitled: current.plan === 'premium', expiresAtIso: current.playEntitlementExpiresAtIso || null,
      verifiedAtIso: current.billingLastVerifiedAtIso || null,
      productId: current.billingProductId || null,
    };
  }
  providers[provider] = entry;
  const time = now.getTime();
  const active = Object.entries(providers).filter(([name, item]) =>
    AUTHORITIES[name] && item.entitled === true && millis(item.expiresAtIso) > time &&
    millis(item.verifiedAtIso) > time - FRESH_MS && millis(item.verifiedAtIso) <= time + 300000)
    .sort((a, b) => millis(b[1].expiresAtIso) - millis(a[1].expiresAtIso));
  const [selected, paid] = active[0] || [];
  const trial = millis(current.trialEndsAtIso) > time;
  return {
    verifiedPaidEntitlements: providers,
    plan: paid ? 'premium' : trial ? 'trial' : 'free',
    premiumEntitlementExpiresAtIso: paid?.expiresAtIso || null,
    entitlementAuthority: paid ? AUTHORITIES[selected] : 'billing_verified',
    billingProvider: selected || provider,
    billingProductId: paid?.productId || null,
    billingLastVerifiedAtIso: paid?.verifiedAtIso || null,
    ...(paid ? { premiumStartedAtIso: current.premiumStartedAtIso || now.toISOString() } : {}),
    updatedAtIso: now.toISOString(), lastSyncedAtIso: now.toISOString(),
  };
}

async function writeVerifiedPaid(db, uid, provider, entry, extra = {}, now = new Date()) {
  const ref = db.collection('ripot_user_access').doc(uid);
  return db.runTransaction(async tx => {
    const current = (await tx.get(ref)).data() || {};
    const prior = current.verifiedPaidEntitlements?.[provider];
    // A slow, older verification cannot overwrite a newer refund/renewal result.
    if (millis(prior?.startedAtIso) > millis(entry.startedAtIso)) return;
    tx.set(ref, { ownerType: 'user', ownerId: uid, authUid: uid, ...extra,
      ...reconcilePaid(current, provider, entry, now) }, { merge: true });
  });
}

module.exports = { reconcilePaid, writeVerifiedPaid, FRESH_MS, AUTHORITIES };
