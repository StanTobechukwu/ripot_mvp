const { HttpsError } = require('firebase-functions/v2/https');
const { FieldValue } = require('firebase-admin/firestore');
const { dateFromAny, requireRegisteredUid } = require('./founding-100');

const COPY_ALLOWANCES = 'ripot_copy_allowances';
const FREE_COPY_LIMIT = 50;
const FRESH_MS = 72 * 60 * 60 * 1000;
const FINGERPRINT = /^[a-f0-9]{64}$/;

function unlimitedCopy(data, now) {
  const override = String(data.adminPlanOverride || '').toLowerCase();
  if (override === 'free') return false;
  if (override === 'premium') return true;
  const future = (value) => (dateFromAny(value)?.getTime() || 0) > now.getTime();
  const adminEnd = data.adminTrialEndsAtIso || data.adminTrialEndsAt;
  if (override === 'trial') return future(adminEnd);
  if (future(adminEnd)) return true;
  if (data.plan === 'trial') return future(data.trialEndsAtIso || data.trialEndsAt);
  const verified = dateFromAny(data.billingLastVerifiedAtIso)?.getTime();
  return data.plan === 'premium' &&
    data.entitlementAuthority === 'google_play_verified' &&
    future(data.playEntitlementExpiresAtIso) &&
    Number.isFinite(verified) && verified <= now.getTime() + 300000 &&
    now.getTime() - verified < FRESH_MS;
}

function fingerprints(snapshot) {
  if (!snapshot.exists) return [];
  const data = snapshot.data();
  const values = data.fingerprints;
  if (data.schemaVersion !== 1 || !Array.isArray(values) ||
      values.length > FREE_COPY_LIMIT || values.some(v => typeof v !== 'string' || !FINGERPRINT.test(v)) ||
      new Set(values).size !== values.length) {
    throw new HttpsError('failed-precondition', 'Your copy allowance needs checking. Contact Ripot support.');
  }
  return values;
}

function createReportCopyService(db, clock = () => new Date()) {
  async function handle(request, authorize) {
    const uid = requireRegisteredUid(request);
    const data = request.data ?? {};
    if (typeof data !== 'object' || Array.isArray(data) || data === null ||
        Object.keys(data).some(k => !authorize || k !== 'fingerprint') ||
        (authorize && (typeof data.fingerprint !== 'string' || !FINGERPRINT.test(data.fingerprint)))) {
      throw new HttpsError('invalid-argument', 'Only a report fingerprint is accepted.');
    }
    // Never accept report text, patient details, a client UID, plan, count or date.
    const allowance = db.collection(COPY_ALLOWANCES).doc(uid);
    const access = db.collection('ripot_user_access').doc(uid);
    return db.runTransaction(async tx => {
      const [quotaSnapshot, accessSnapshot] = await tx.getAll(allowance, access);
      const values = fingerprints(quotaSnapshot);
      const unlimited = unlimitedCopy(accessSnapshot.data() || {}, clock());
      const repeated = authorize && values.includes(data.fingerprint);
      if (authorize && !unlimited && !repeated && values.length >= FREE_COPY_LIMIT) {
        throw new HttpsError('resource-exhausted', 'Your 50 free report versions have been used. Unchanged versions can still be copied.',
          { limit: FREE_COPY_LIMIT, remaining: 0 });
      }
      const charged = authorize && !unlimited && !repeated;
      if (charged) {
        values.push(data.fingerprint);
        tx.set(allowance, { schemaVersion: 1, fingerprints: values,
          updatedAt: FieldValue.serverTimestamp() });
      }
      return { limit: FREE_COPY_LIMIT, remaining: FREE_COPY_LIMIT - values.length,
        unlimited, repeated: Boolean(repeated), charged: Boolean(charged) };
    });
  }
  return { status: request => handle(request, false), authorize: request => handle(request, true) };
}

module.exports = { createReportCopyService, unlimitedCopy, FREE_COPY_LIMIT, COPY_ALLOWANCES };
