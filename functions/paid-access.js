// One account can retain paid time from more than one provider. Updating one
// provider must never remove valid access granted by another.
const FRESH_MS = 72 * 60 * 60 * 1000;
function time(value) {
  const result = Date.parse(value || '');
  return Number.isFinite(result) ? result : 0;
}
function paidAccess(data = {}, now = new Date()) {
  const candidates = [
    { provider: 'google_play', authority: 'google_play_verified',
      expiresAtIso: data.playEntitlementExpiresAtIso,
      verifiedAtIso: data.playLastVerifiedAtIso ||
        (data.entitlementAuthority === 'google_play_verified' ? data.billingLastVerifiedAtIso : null) },
    { provider: 'paystack', authority: 'paystack_verified',
      expiresAtIso: data.paystackEntitlementExpiresAtIso,
      verifiedAtIso: data.paystackLastVerifiedAtIso },
  ].filter(p => time(p.expiresAtIso) > now.getTime());
  for (const p of candidates) {
    const verified = time(p.verifiedAtIso);
    p.fresh = verified > 0 && verified <= now.getTime() + 300000 && now.getTime() - verified < FRESH_MS;
  }
  candidates.sort((a, b) => Number(b.fresh) - Number(a.fresh) || time(b.expiresAtIso) - time(a.expiresAtIso));
  return candidates[0] || null;
}
function paidProjection(data, now = new Date()) {
  const paid = paidAccess(data, now);
  return {
    plan: paid ? 'premium' : time(data.trialEndsAtIso) > now.getTime() ? 'trial' : 'free',
    premiumExpiresAtIso: paid?.expiresAtIso || null,
    billingProvider: paid?.provider || null,
    entitlementAuthority: paid?.authority || 'cloud_function',
    billingLastVerifiedAtIso: paid?.verifiedAtIso || null,
    updatedAtIso: now.toISOString(),
  };
}
module.exports = { time, paidAccess, paidProjection, FRESH_MS };
