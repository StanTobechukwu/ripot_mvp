const { test, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.GCLOUD_PROJECT?.startsWith('demo-')) {
  throw new Error('Use the Firestore emulator and a demo- project. Tests erase emulator data.');
}
require('../index');
const { getFirestore } = require('firebase-admin/firestore');
const { getApp, deleteApp } = require('firebase-admin/app');
const { createMicrosoftService, configured, PURCHASE_RESOURCE, SERVICE_RESOURCE } = require('../microsoft-store');
const { reconcilePaid, writeVerifiedPaid } = require('../paid-entitlements');
const { unlimitedCopy } = require('../report-copy');
const db = getFirestore();
const now = new Date('2026-11-08T12:00:00Z');
const config = { enabled: true, tenantId: '11111111-1111-1111-1111-111111111111',
  clientId: '22222222-2222-2222-2222-222222222222', clientSecret: 'test-only-secret',
  monthlyId: '9TESTMONTHLY', annualId: '9TESTANNUAL1' };
const request = (data = {}, uid = 'alice') => ({ data, auth: { uid,
  token: { firebase: { sign_in_provider: 'password' } } } });
function key(uid = 'alice', overrides = {}) {
  const c = 'http://schemas.microsoft.com/marketplace/2015/08/claims/key/';
  return [ { alg: 'RS256' }, { aud: 'https://purchase.mp.microsoft.com/v6.0/keys',
    iss: 'https://purchase.mp.microsoft.com/v6.0/keys', exp: now.getTime() / 1000 + 864000,
    nbf: now.getTime() / 1000 - 5, [`${c}clientId`]: config.clientId, [`${c}userId`]: uid, ...overrides },
  ].map(v => Buffer.from(JSON.stringify(v)).toString('base64url')).join('.') + '.test-signature';
}
const item = (overrides = {}) => ({ id: 'subscription-one', beneficiary: 'store-customer-one',
  productId: config.monthlyId, recurrenceState: 'Active', expirationTime: '2026-12-08T12:00:00Z',
  autoRenew: true, ...overrides });
let items, calls, service, fail, continuation;
beforeEach(async () => {
  const r = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  assert.equal(r.ok, true);
  items = [item()]; calls = []; fail = false; continuation = null;
  service = createMicrosoftService(db, { config: () => config, clock: () => now, http: async (url, options) => {
    calls.push({ url, options });
    if (url.includes('oauth2/token')) {
      const resource = new URLSearchParams(options.body).get('resource');
      assert([PURCHASE_RESOURCE, SERVICE_RESOURCE].includes(resource));
      return { ok: true, json: async () => ({ access_token: resource === PURCHASE_RESOURCE ? 'restricted' : 'server-only', expires_in: 3600 }) };
    }
    if (url.endsWith('/keys/renew')) return { ok: true, json: async () => ({ key: key() }) };
    assert(url.endsWith('/recurrences/query'));
    assert.equal(options.headers.Authorization, 'Bearer server-only');
    return { ok: !fail, json: async () => ({ items, continuationToken: continuation }) };
  } });
});
after(() => deleteApp(getApp()));

test('checkout is disabled without every setting; rejects guests and client entitlement fields', async () => {
  assert(configured(config));
  for (const patch of [{ enabled: false }, { clientSecret: '' }, { annualId: config.monthlyId }, { monthlyId: 'bad' }]) {
    assert.equal(configured({ ...config, ...patch }), false);
  }
  const disabled = createMicrosoftService(db, { config: () => ({ enabled: false }) });
  assert.deepEqual(await disabled.config(request()), { enabled: false });
  await assert.rejects(disabled.ticket(request()), { code: 'failed-precondition' });
  await assert.rejects(service.ticket({ data: {} }), { code: 'unauthenticated' });
  await assert.rejects(service.verify(request({ key: key(), plan: 'premium' })), { code: 'invalid-argument' });
  assert.equal(calls.length, 0);
});

test('only restricted creation ticket is sent to the client; tokens never appear in access documents', async () => {
  assert.deepEqual(await service.ticket(request()), { serviceTicket: 'restricted', publisherUserId: 'alice' });
  const result = await service.verify(request({ key: key() }));
  assert.equal(result.entitled, true);
  const access = (await db.collection('ripot_user_access').doc('alice').get()).data();
  assert.equal(access.entitlementAuthority, 'microsoft_store_verified');
  assert.equal(unlimitedCopy(access, now), true);
  assert.equal(JSON.stringify(access).includes(key()), false);
  assert.equal(JSON.stringify(result).includes('server-only'), false);
});

test('a successful Microsoft API call is required, and forged bindings are rejected before HTTP', async () => {
  for (const badKey of [key('bob'), key('alice', { aud: 'other' }), key('alice', { exp: 1 }), 'invalid']) {
    await assert.rejects(service.verify(request({ key: badKey })), { code: 'failed-precondition' });
  }
  assert.equal(calls.length, 0);
  fail = true;
  await assert.rejects(service.verify(request({ key: key() })), { code: 'unavailable' });
  assert.equal((await db.collection('ripot_user_access').doc('alice').get()).exists, false);
  assert.equal((await db.collection('ripot_internal_microsoft_owners').get()).size, 0);
});

test('ownership cannot be reused by a second Ripot account, including a renewed recurrence', async () => {
  await service.verify(request({ key: key() }));
  await assert.rejects(service.verify(request({ key: key('bob') }, 'bob')), { code: 'permission-denied' });
  items = [item({ id: 'renewed-new-id' })];
  await assert.rejects(service.verify(request({ key: key('bob') }, 'bob')), { code: 'permission-denied' });
  assert.equal((await db.collection('ripot_user_access').doc('bob').get()).exists, false);
});

test('cancelled renewal stays active through its paid period; refund and expiry remove access', async () => {
  items = [item({ autoRenew: false })];
  assert.equal((await service.verify(request({ key: key() }))).entitled, true);
  items = [item({ recurrenceState: 'Canceled' })];
  assert.equal((await service.refresh(request())).entitled, false);
  assert.equal((await db.collection('ripot_user_access').doc('alice').get()).data().plan, 'free');
  items = [item({ expirationTime: now.toISOString() })];
  assert.equal((await service.verify(request({ key: key() }))).entitled, false);
  items = [item({ recurrenceState: 'InDunning', expirationTimeWithGrace: '2026-11-09' })];
  assert.equal((await service.verify(request({ key: key() }))).entitled, true);
});

test('an empty refresh revokes a disappeared purchase; an empty different Store account cannot replace it', async () => {
  await service.verify(request({ key: key() }));
  items = [];
  await assert.rejects(service.verify(request({ key: key() })), { code: 'failed-precondition' });
  assert.equal((await service.refresh(request())).entitled, false);
  assert.equal((await db.collection('ripot_user_access').doc('alice').get()).data().plan, 'free');
});

test('unknown products never grant Premium and partial paginated results fail closed', async () => {
  items = [item({ productId: '9OTHERAPPXXX' })];
  assert.equal((await service.verify(request({ key: key() }))).entitled, false);
  continuation = 'more'; items = [item()];
  await assert.rejects(service.verify(request({ key: key() })), { code: 'unavailable' });
  assert.equal((await db.collection('ripot_user_access').doc('alice').get()).data().plan, 'free');
});

test('one store expiring preserves the other store and never resets a trial', async () => {
  const paid = { entitled: true, productId: 'ripot_premium', expiresAtIso: '2027-01-01',
    verifiedAtIso: now.toISOString(), startedAtIso: now.toISOString() };
  await writeVerifiedPaid(db, 'alice', 'google_play', paid, { hasUsedTrial: true, trialEndsAtIso: '2026-11-01' }, now);
  items = [item({ recurrenceState: 'Canceled' })];
  await service.verify(request({ key: key() }));
  const data = (await db.collection('ripot_user_access').doc('alice').get()).data();
  assert.equal(data.plan, 'premium'); assert.equal(data.entitlementAuthority, 'google_play_verified');
  assert.equal(data.hasUsedTrial, true); assert.equal(data.trialEndsAtIso, '2026-11-01');
  const expired = reconcilePaid(data, 'google_play', { ...paid, entitled: false }, now);
  assert.equal(expired.plan, 'free');
  const trial = reconcilePaid({ trialEndsAtIso: '2026-11-15' }, 'microsoft_store', { entitled: false }, now);
  assert.equal(trial.plan, 'trial');
});

test('rate limiting blocks excessive requests and stale paid verification cannot extend access', async () => {
  for (let n = 0; n < 12; n++) await service.ticket(request());
  await assert.rejects(service.ticket(request()), { code: 'resource-exhausted' });
  const expired = reconcilePaid({}, 'microsoft_store', { entitled: true,
    expiresAtIso: '2027-01-01', verifiedAtIso: '2026-11-01' }, now);
  assert.equal(expired.plan, 'free');
});

test('concurrent account claims have exactly one owner', async () => {
  const results = await Promise.allSettled(['alice', 'bob'].map(uid =>
    service.verify(request({ key: key(uid) }, uid))));
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(results.find(r => r.status === 'rejected').reason.code, 'permission-denied');
});

test('near-expiry keys renew at the fixed Microsoft endpoint with the server-only ticket', async () => {
  const oldKey = key('alice', { exp: now.getTime() / 1000 + 86400,
    'http://schemas.microsoft.com/marketplace/2015/08/claims/key/refreshUri': 'https://untrusted.invalid' });
  await db.collection('ripot_internal_microsoft').doc('alice').set({ key: oldKey });
  assert.equal((await service.refresh(request())).entitled, true);
  const renew = calls.find(c => c.url.endsWith('/keys/renew'));
  assert.equal(renew.url, 'https://purchase.mp.microsoft.com/v6.0/b2b/keys/renew');
  assert.equal(JSON.parse(renew.options.body).serviceTicket, 'server-only');
  assert.equal((await db.collection('ripot_internal_microsoft').doc('alice').get()).data().key, key());
});

test('expired keys require restoration and network failures do not refresh the access deadline', async () => {
  await service.verify(request({ key: key() }));
  const access = db.collection('ripot_user_access').doc('alice');
  const before = (await access.get()).data();
  fail = true;
  await assert.rejects(service.refresh(request()), { code: 'unavailable' });
  assert.deepEqual((await access.get()).data(), before);
  await db.collection('ripot_internal_microsoft').doc('alice').set({ key: key('alice', { exp: 1 }) });
  await assert.rejects(service.refresh(request()), { code: 'failed-precondition' });
  assert.deepEqual((await access.get()).data(), before);
});

test('older responses cannot replace a more recent revocation', async () => {
  const recent = { entitled: false, startedAtIso: '2026-11-08T12:00:00Z', verifiedAtIso: now.toISOString() };
  await writeVerifiedPaid(db, 'alice', 'microsoft_store', recent, {}, now);
  await writeVerifiedPaid(db, 'alice', 'microsoft_store', { entitled: true,
    startedAtIso: '2026-11-08T11:59:00Z', verifiedAtIso: now.toISOString(), expiresAtIso: '2027-01-01' }, {}, now);
  assert.equal((await db.collection('ripot_user_access').doc('alice').get()).data().plan, 'free');
});
