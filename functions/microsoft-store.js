'use strict';

const { createHash } = require('node:crypto');
const { HttpsError } = require('firebase-functions/v2/https');
const { requireRegisteredUid } = require('./founding-100');
const { writeVerifiedPaid } = require('./paid-entitlements');
const PURCHASE_RESOURCE = 'https://onestore.microsoft.com/b2b/keys/create/purchase';
const SERVICE_RESOURCE = 'https://onestore.microsoft.com';
const API = 'https://purchase.mp.microsoft.com';
const CLAIM = 'http://schemas.microsoft.com/marketplace/2015/08/claims/key/';
const INTERNAL = 'ripot_internal_microsoft';
const OWNERS = 'ripot_internal_microsoft_owners';
const hash = value => createHash('sha256').update(value).digest('hex');
const guid = value => String(value || '').replaceAll('-', '').toLowerCase();

function configured(c) {
  return c.enabled === true && /^[a-f0-9-]{36}$/i.test(c.tenantId || '') &&
    /^[a-f0-9-]{36}$/i.test(c.clientId || '') && Boolean(c.clientSecret) &&
    /^[A-Z0-9]{12}$/.test(c.monthlyId || '') && /^[A-Z0-9]{12}$/.test(c.annualId || '') &&
    c.monthlyId !== c.annualId;
}

// These checks do NOT authenticate a JWT. Only a successful Microsoft API call
// below validates the signature; no access is ever granted from decoded claims.
function keyClaims(key, uid, config, now) {
  try {
    if (typeof key !== 'string' || key.length < 100 || key.length > 24000) throw new Error();
    const parts = key.split('.');
    if (parts.length !== 3 || !parts[2]) throw new Error();
    const header = JSON.parse(Buffer.from(parts[0], 'base64url'));
    const body = JSON.parse(Buffer.from(parts[1], 'base64url'));
    if (header.alg !== 'RS256' || body.aud !== `${API}/v6.0/keys` || body.iss !== body.aud ||
        guid(body[`${CLAIM}clientId`]) !== guid(config.clientId) || body[`${CLAIM}userId`] !== uid ||
        !Number.isFinite(body.exp) || body.exp * 1000 <= now.getTime() ||
        !Number.isFinite(body.nbf) || body.nbf * 1000 > now.getTime() + 300000) throw new Error();
    return body;
  } catch (_) {
    throw new HttpsError('failed-precondition', 'Reconnect your Microsoft Store account using Restore purchases.');
  }
}

function subscription(items, config, now) {
  const known = items.filter(i => [config.monthlyId, config.annualId].includes(i?.productId));
  if (known.some(i => typeof i.id !== 'string' || !i.id || i.id.length > 500 ||
      typeof i.beneficiary !== 'string' || !i.beneficiary || i.beneficiary.length > 500)) {
    throw new HttpsError('unavailable', 'Microsoft returned incomplete subscription information.');
  }
  const candidates = known.map(item => {
    const expires = item.recurrenceState === 'InDunning' ? item.expirationTimeWithGrace : item.expirationTime;
    const time = Date.parse(expires || '');
    return { item, expiry: Number.isFinite(time) ? new Date(time) : null,
      entitled: ['Active', 'InDunning'].includes(item.recurrenceState) && time > now.getTime() };
  }).filter(x => x.entitled).sort((a, b) => b.expiry - a.expiry);
  return { known, selected: candidates[0] || null };
}

function createMicrosoftService(db, { config, http = fetch, clock = () => new Date() }) {
  const tokens = new Map();
  const getConfig = () => {
    const c = config();
    if (!configured(c)) throw new HttpsError('failed-precondition', 'Microsoft Store checkout is not available yet.');
    return c;
  };
  async function json(url, options) {
    try {
      const response = await http(url, { ...options, redirect: 'error', signal: AbortSignal.timeout(10000) });
      // Never return Microsoft response bodies/tokens in callable errors or logs.
      if (!response.ok) throw new Error('upstream');
      return await response.json();
    } catch (_) { throw new HttpsError('unavailable', 'Microsoft could not verify the subscription. Try again shortly.'); }
  }
  async function token(c, resource) {
    const cacheKey = `${c.clientId}:${resource}:${hash(c.clientSecret)}`;
    const cached = tokens.get(cacheKey);
    if (cached && cached.until > clock().getTime()) return cached.token;
    const body = await json(`https://login.microsoftonline.com/${c.tenantId}/oauth2/token`, {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'client_credentials', client_id: c.clientId,
        client_secret: c.clientSecret, resource }).toString(),
    });
    if (typeof body.access_token !== 'string' || !body.access_token || !(Number(body.expires_in) > 300)) {
      throw new HttpsError('unavailable', 'Microsoft verification is unavailable.');
    }
    tokens.set(cacheKey, { token: body.access_token,
      until: clock().getTime() + Math.min(Number(body.expires_in) - 300, 3300) * 1000 });
    return body.access_token;
  }
  async function throttle(uid) {
    const ref = db.collection('ripot_internal_microsoft_limits').doc(uid);
    await db.runTransaction(async tx => {
      const value = (await tx.get(ref)).data() || {};
      const now = clock().getTime();
      const count = now - Number(value.windowAt || 0) < 60000 ? Number(value.count || 0) : 0;
      if (count >= 12) throw new HttpsError('resource-exhausted', 'Please wait a minute before trying again.');
      tx.set(ref, { count: count + 1, windowAt: count ? value.windowAt : now });
    });
  }
  function requestUid(request, allowed = []) {
    const uid = requireRegisteredUid(request);
    const data = request.data ?? {};
    if (!data || typeof data !== 'object' || Array.isArray(data) || Object.keys(data).some(k => !allowed.includes(k))) {
      throw new HttpsError('invalid-argument', 'Unexpected subscription information.');
    }
    return uid;
  }
  async function query(c, key) {
    const ticket = await token(c, SERVICE_RESOURCE);
    const items = [];
    let continuationToken;
    for (let page = 0; page < 10; page++) {
      const result = await json(`${API}/v8.0/b2b/recurrences/query`, { method: 'POST',
        headers: { Authorization: `Bearer ${ticket}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ b2bKey: key, pageSize: 100, ...(continuationToken ? { continuationToken } : {}) }) });
      if (!Array.isArray(result.items)) throw new HttpsError('unavailable', 'Microsoft returned incomplete subscription information.');
      items.push(...result.items);
      continuationToken = result.continuationToken;
      if (!continuationToken) return items;
      if (typeof continuationToken !== 'string' || continuationToken.length > 10000) break;
    }
    throw new HttpsError('unavailable', 'Microsoft subscription lookup did not finish. Try again.');
  }
  async function verify(uid, key, c, trustedRefresh = false) {
    const startedAtIso = clock().toISOString();
    keyClaims(key, uid, c, clock());
    const { known, selected } = subscription(await query(c, key), c, clock());
    const internal = db.collection(INTERNAL).doc(uid);
    // Link both recurrence and beneficiary, so another Ripot account cannot
    // claim a renewed subscription or a second plan from the same Store user.
    const ownerIds = [...new Set(known.flatMap(i => [`subscription:${i.id}`, `beneficiary:${i.beneficiary}`]))];
    if (ownerIds.length > 200) throw new HttpsError('unavailable', 'Too many subscription records. Contact support.');
    await db.runTransaction(async tx => {
      const saved = await tx.get(internal);
      const refs = ownerIds.map(id => db.collection(OWNERS).doc(hash(id)));
      const owners = refs.length ? await tx.getAll(...refs) : [];
      if (owners.some(s => s.exists && s.data().uid !== uid)) {
        throw new HttpsError('permission-denied', 'This Microsoft subscription is linked to another Ripot account. Sign in to that account to restore it.');
      }
      if (Date.parse(saved.data()?.startedAtIso || '') > Date.parse(startedAtIso)) return;
      refs.forEach(ref => tx.set(ref, { uid }));
      // Do not replace a working subscription identity with an empty Store account.
      if (trustedRefresh || known.length || !saved.exists || saved.data()?.beneficiary === null) {
        tx.set(internal, { key, startedAtIso, beneficiary: known[0]?.beneficiary || saved.data()?.beneficiary || null,
          lastVerifiedAtIso: clock().toISOString() });
      } else {
        throw new HttpsError('failed-precondition', 'Sign in to the Microsoft Store account used for your subscription, then restore.');
      }
    });
    const entry = { entitled: Boolean(selected), expiresAtIso: selected?.expiry.toISOString() || null,
      productId: selected?.item.productId || null, state: selected?.item.recurrenceState || 'Inactive',
      autoRenew: selected?.item.autoRenew === true, verifiedAtIso: clock().toISOString(), startedAtIso };
    await writeVerifiedPaid(db, uid, 'microsoft_store', entry, {}, clock());
    return { checked: true, entitled: entry.entitled, expiresAtIso: entry.expiresAtIso, autoRenew: entry.autoRenew };
  }
  return {
    config: async request => {
      requestUid(request);
      const c = config();
      return configured(c) ? { enabled: true, monthlyId: c.monthlyId, annualId: c.annualId } : { enabled: false };
    },
    ticket: async request => {
      const uid = requestUid(request); const c = getConfig(); await throttle(uid);
      // Only the restricted key-creation token may leave this service.
      return { serviceTicket: await token(c, PURCHASE_RESOURCE), publisherUserId: uid };
    },
    verify: async request => {
      const uid = requestUid(request, ['key']); const c = getConfig(); await throttle(uid);
      return verify(uid, request.data?.key, c);
    },
    refresh: async request => {
      const uid = requestUid(request);
      const saved = (await db.collection(INTERNAL).doc(uid).get()).data();
      if (!saved?.key || !configured(config())) return { checked: false, entitled: false };
      const c = getConfig(); await throttle(uid);
      let key = saved.key;
      const claims = keyClaims(key, uid, c, clock());
      if (claims.exp * 1000 - clock().getTime() < 7 * 86400000) {
        const renewed = await json(`${API}/v6.0/b2b/keys/renew`, { method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ serviceTicket: await token(c, SERVICE_RESOURCE), key }) });
        key = renewed.key;
        keyClaims(key, uid, c, clock());
      }
      return verify(uid, key, c, true);
    },
  };
}

module.exports = { createMicrosoftService, configured, keyClaims, subscription, PURCHASE_RESOURCE, SERVICE_RESOURCE };
