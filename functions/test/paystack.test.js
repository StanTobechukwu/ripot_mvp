const { test, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const { createHmac } = require('node:crypto');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { createPaystackApi, createPaystackService, verifySignature, validateCatalog, nextPeriod } = require('../paystack');
const { paidProjection, paidAccess } = require('../paid-access');
const { unlimitedCopy } = require('../report-copy');
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.GCLOUD_PROJECT?.startsWith('demo-')) throw Error('Use demo Firestore emulator only');
const app = initializeApp();
const db = getFirestore(app);
let now = new Date('2026-11-09T12:00:00Z');
const plans = [
  { id: 'ng_monthly', code: 'PLN_ngmonthly', amount: 250000, currency: 'NGN', interval: 'monthly', markets: ['NG'], enabled: true },
  { id: 'ng_annual', code: 'PLN_ngannual', amount: 2500000, currency: 'NGN', interval: 'annually', markets: ['NG'], enabled: true },
  { id: 'usd_monthly', code: 'PLN_usmonthly', amount: 599, currency: 'USD', interval: 'monthly', markets: ['international'], enabled: true },
];
let mode, responses, calls, service;
const req = (data = {}, uid = 'alice') => ({ auth: { uid, token: { email: `${uid}@example.test`, firebase: { sign_in_provider: 'password' } } }, data });
const aRef = uid => db.collection(`ripot_internal_paystack_${mode}`).doc(uid);
const uRef = uid => db.collection(mode === 'live' ? 'ripot_user_access' : 'ripot_test_user_access').doc(uid);
async function setup(newMode = 'live') {
  mode = newMode;
  now = new Date('2026-11-09T12:00:00Z'); responses = {}; calls = [];
  await db.doc('ripot_internal/paystack_config').set({ mode, enabled: true, internationalEnabled: true, testUids: ['alice'], plans });
  const api = async (path, body) => {
    calls.push({ path, body });
    if (responses[path] instanceof Error) throw responses[path];
    if (responses[path]) return structuredClone(responses[path]);
    if (path.startsWith('/plan/')) return { domain: mode, ...plans.find(p => p.code === path.split('/').pop()) };
    if (path.startsWith('/customer/')) return { customer_code: 'CUS_alice', email: 'alice@example.test', domain: mode };
    if (path === '/transaction/initialize') return { reference: body.reference, authorization_url: `https://checkout.paystack.com/${body.reference}` };
    throw Error(`Unmocked API path: ${path}`);
  };
  service = createPaystackService(db, { api, apiSecret: () => `sk_${mode}_fixture`, clock: () => now });
}
beforeEach(async () => {
  const response = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  assert(response.ok); await setup();
});
after(() => deleteApp(app));
async function payment(planId = 'ng_monthly') {
  const p = plans.find(p => p.id === planId);
  const started = await service.start(req({ planId, market: p.markets[0] }));
  responses[`/transaction/verify/${started.reference}`] = {
    domain: mode, id: 123, status: 'success', reference: started.reference,
    amount: p.amount, currency: p.currency, plan: { plan_code: p.code },
    customer: { customer_code: 'CUS_alice' }, metadata: { ripotUid: 'alice' },
    paid_at: now.toISOString(),
  };
  return started.reference;
}
function sub(status = 'active', p = plans[0]) {
  responses['/subscription/SUB_alice'] = { domain: mode, subscription_code: 'SUB_alice', status,
    amount: p.amount, plan: { plan_code: p.code, currency: p.currency, interval: p.interval },
    customer: { customer_code: 'CUS_alice' } };
}

test('authentication, immutable prices and markets are enforced', async () => {
  await assert.rejects(service.start({ data: {} }), { code: 'unauthenticated' });
  await assert.rejects(service.start(req({ planId: 'ng_monthly', market: 'NG', amount: 1 })), { code: 'invalid-argument' });
  await assert.rejects(service.start(req({ planId: 'usd_monthly', market: 'NG' })), { code: 'invalid-argument' });
  assert.equal((await service.catalogue(req())).plans[2].currency, 'USD');
  const ref = await payment('usd_monthly');
  assert.equal(calls.find(c => c.path === '/transaction/initialize').body.amount, 599);
  await service.applyCharge({ mode, plans }, ref);
  assert.equal((await uRef('alice').get()).data().plan, 'premium');
});
test('international payments and unconfigured plans fail closed', async () => {
  await db.doc('ripot_internal/paystack_config').update({ internationalEnabled: false });
  await assert.rejects(service.start(req({ planId: 'usd_monthly', market: 'international' })), { code: 'invalid-argument' });
  await db.doc('ripot_internal/paystack_config').update({ enabled: false });
  assert.equal((await service.catalogue(req())).enabled, false);
  await assert.rejects(service.start(req({ planId: 'ng_monthly', market: 'NG' })), { code: 'failed-precondition' });
});
test('active trials and active Play subscriptions prevent checkout', async () => {
  await uRef('alice').set({ plan: 'trial', trialEndsAtIso: '2026-12-01T00:00:00Z' });
  await assert.rejects(payment(), { code: 'failed-precondition' });
  await uRef('alice').set({ playEntitlementExpiresAtIso: '2027-01-01T00:00:00Z', entitlementAuthority: 'google_play_verified' });
  await assert.rejects(payment(), { code: 'failed-precondition' });
  assert.equal(calls.length, 0);
});
test('pending checkout resumes the same reference and cannot change plan', async () => {
  const ref = await payment();
  const repeat = await service.start(req({ planId: 'ng_monthly', market: 'NG' }));
  assert.equal(repeat.reference, ref);
  assert.equal(calls.filter(c => c.path === '/transaction/initialize').length, 1);
  await assert.rejects(service.start(req({ planId: 'ng_annual', market: 'NG' })), { code: 'failed-precondition' });
});
test('duplicate concurrent webhook and return checks grant one fixed period', async () => {
  const ref = await payment();
  await Promise.all(Array.from({ length: 4 }, () => service.event({ event: 'charge.success', data: { reference: ref, domain: mode } })));
  const access = (await uRef('alice').get()).data();
  assert.equal(access.premiumExpiresAtIso, '2026-12-09T12:00:00.000Z');
  assert.equal((await aRef('alice').collection('payments').get()).size, 1);
  assert.equal(unlimitedCopy(access, now), true);
  assert.equal(access.playEntitlementExpiresAtIso, undefined);
});
test('wrong amount, currency, owner, reference and domain grant nothing', async () => {
  const ref = await payment(); const key = `/transaction/verify/${ref}`;
  const original = structuredClone(responses[key]);
  for (const change of [{ amount: 1 }, { currency: 'USD' }, { domain: 'test' },
    { reference: 'different_reference' }, { metadata: { ripotUid: 'bob' } }]) {
    responses[key] = { ...original, ...change };
    await assert.rejects(service.applyCharge({ mode, plans }, ref));
    assert.equal((await uRef('alice').get()).exists, false);
  }
});
test('pending and failed transactions do not grant Premium', async () => {
  const ref = await payment();
  for (const status of ['pending', 'failed', 'abandoned']) {
    responses[`/transaction/verify/${ref}`].status = status;
    await service.applyCharge({ mode, plans }, ref);
    assert.equal((await uRef('alice').get()).exists, false);
  }
});
test('subscription event after charge binds successfully; cancellation preserves paid time', async () => {
  const ref = await payment(); await service.applyCharge({ mode, plans }, ref);
  sub(); await service.event({ event: 'subscription.create', data: { subscription_code: 'SUB_alice', domain: mode } });
  assert.equal((await aRef('alice').get()).data().subscriptionCode, 'SUB_alice');
  sub('non-renewing');
  await service.event({ event: 'subscription.not_renew', data: { subscription_code: 'SUB_alice', domain: mode } });
  assert.equal((await uRef('alice').get()).data().premiumExpiresAtIso, '2026-12-09T12:00:00.000Z');
  assert.equal((await aRef('alice').get()).data().subscriptionStatus, 'non-renewing');
});
test('subscription event can arrive before the initial charge', async () => {
  const ref = await payment(); sub();
  await service.event({ event: 'subscription.create', data: { subscription_code: 'SUB_alice', domain: mode } });
  await service.applyCharge({ mode, plans }, ref);
  assert.equal((await uRef('alice').get()).data().plan, 'premium');
});
test('renewal extends to its paid period; failed renewal does not extend access', async () => {
  const ref = await payment(); await service.applyCharge({ mode, plans }, ref); sub();
  await service.event({ event: 'subscription.create', data: { subscription_code: 'SUB_alice', domain: mode } });
  now = new Date('2026-12-09T12:00:00Z');
  responses['/transaction/verify/renewal_123'] = { ...responses[`/transaction/verify/${ref}`], id: 124, reference: 'renewal_123', paid_at: now.toISOString(), metadata: {} };
  await service.event({ event: 'charge.success', data: { reference: 'renewal_123', domain: mode } });
  assert.equal((await uRef('alice').get()).data().premiumExpiresAtIso, '2027-01-09T12:00:00.000Z');
  sub('attention');
  await service.event({ event: 'invoice.payment_failed', data: { subscription: { subscription_code: 'SUB_alice' }, domain: mode, paid: false } });
  assert.equal((await uRef('alice').get()).data().premiumExpiresAtIso, '2027-01-09T12:00:00.000Z');
});
test('full refund is monotonic and does not revoke another provider', async () => {
  const ref = await payment(); await service.applyCharge({ mode, plans }, ref);
  await uRef('alice').set({ playEntitlementExpiresAtIso: '2027-02-01T00:00:00Z', playLastVerifiedAtIso: now.toISOString() }, { merge: true });
  await service.event({ event: 'refund.processed', data: { domain: mode, transaction: { id: 123 }, amount: 250000 } });
  await service.event({ event: 'charge.success', data: { domain: mode, reference: ref } });
  const state = (await uRef('alice').get()).data();
  assert.equal(state.paystackEntitlementExpiresAtIso, null);
  assert.equal(state.entitlementAuthority, 'google_play_verified');
  assert.equal(state.plan, 'premium');
});
test('test payments cannot write production account access', async () => {
  await setup('test');
  const ref = await payment(); await service.applyCharge({ mode, plans }, ref);
  assert.equal((await db.collection('ripot_user_access').doc('alice').get()).exists, false);
  assert.equal((await uRef('alice').get()).data().plan, 'premium');
  await assert.rejects(service.catalogue(req({}, 'bob')), { code: 'failed-precondition' });
});
test('customer already bound to another UID cannot be reassigned', async () => {
  await db.collection('ripot_internal_paystack_customers_live').doc('CUS_alice').set({ uid: 'bob' });
  await assert.rejects(payment(), { code: 'failed-precondition' });
  assert(!calls.some(c => c.path === '/transaction/initialize'));
});
test('expiry, provider freshness and calendar boundaries', () => {
  assert.equal(nextPeriod('2026-01-31T12:00:00Z', 'monthly'), '2026-02-28T12:00:00.000Z');
  assert.equal(nextPeriod('2028-02-29T12:00:00Z', 'annually'), '2029-02-28T12:00:00.000Z');
  const state = { paystackEntitlementExpiresAtIso: '2026-12-01T00:00:00Z', paystackLastVerifiedAtIso: now.toISOString(),
    playEntitlementExpiresAtIso: '2027-01-01T00:00:00Z', playLastVerifiedAtIso: '2026-11-01T00:00:00Z' };
  assert.equal(paidAccess(state, now).provider, 'paystack');
  assert.equal(paidProjection(state, new Date('2028-01-01')).plan, 'free');
  assert.equal(unlimitedCopy({ ...state, plan: 'premium' }, new Date('2026-11-13')), false);
});
test('webhook signatures verify exact bytes, timestamps, rotation and no downgrade', () => {
  const raw = Buffer.from('{"event":"charge.success", "data":{}}');
  const secret = 'sk_test_fixture', signing = 'whsec_fixture';
  const legacy = createHmac('sha512', secret).update(raw).digest('hex');
  assert(verifySignature(raw, { 'x-paystack-signature': legacy }, secret, 'legacy', now.getTime()));
  assert(!verifySignature(Buffer.from('{}'), { 'x-paystack-signature': legacy }, secret, 'legacy', now.getTime()));
  const t = Math.floor(now.getTime() / 1000);
  const hash = createHmac('sha512', signing).update(`${t}.`).update(raw).digest('hex');
  const header = `t=${t},v1=whk_old:${'0'.repeat(128)},v1=whk_new:${hash}`;
  assert(verifySignature(raw, { 'paystack-signature': header }, secret, signing, now.getTime()));
  assert(!verifySignature(raw, { 'paystack-signature': header }, secret, signing, now.getTime() + 301000));
  assert(!verifySignature(raw, { 'x-paystack-signature': legacy }, secret, signing, now.getTime()));
  assert(!verifySignature(raw, { 'paystack-signature': 'bad', 'x-paystack-signature': legacy }, secret, signing));
});
test('catalogue rejects unsupported currencies and duplicate codes', () => {
  assert.throws(() => validateCatalog({ mode: 'live', plans: [{ ...plans[0], currency: 'GBP' }] }));
  assert.throws(() => validateCatalog({ mode: 'live', plans: [plans[0], { ...plans[0], id: 'duplicate' }] }));
});

test('replayed older payment cannot refresh verification of a newer payment', async () => {
  const ref = await payment(); await service.applyCharge({ mode, plans }, ref); sub();
  await service.event({ event: 'subscription.create', data: { subscription_code: 'SUB_alice', domain: mode } });
  now = new Date('2026-12-09T12:00:00Z');
  responses['/transaction/verify/renewal_123'] = { ...responses[`/transaction/verify/${ref}`], id: 124, reference: 'renewal_123', paid_at: now.toISOString(), metadata: {} };
  await service.applyCharge({ mode, plans }, 'renewal_123');
  now = new Date('2026-12-14T12:00:00Z');
  await service.applyCharge({ mode, plans }, ref);
  const state = (await uRef('alice').get()).data();
  assert.equal(state.paystackLastVerifiedAtIso, '2026-12-09T12:00:00.000Z');
  assert.equal(unlimitedCopy(state, now), false);
});

test('revoked payment preserves another paid Paystack period without granting extra time', async () => {
  const ref = await payment(); await service.applyCharge({ mode, plans }, ref); sub();
  await service.event({ event: 'subscription.create', data: { subscription_code: 'SUB_alice', domain: mode } });
  now = new Date('2026-12-09T12:00:00Z');
  responses['/transaction/verify/renewal_123'] = { ...responses[`/transaction/verify/${ref}`], id: 124, reference: 'renewal_123', paid_at: now.toISOString(), metadata: {} };
  await service.applyCharge({ mode, plans }, 'renewal_123');
  await service.event({ event: 'refund.processed', data: { domain: mode, transaction: 123, amount: 250000 } });
  assert.equal((await uRef('alice').get()).data().premiumExpiresAtIso, '2027-01-09T12:00:00.000Z');
});

test('pausing sales preserves existing access refresh and subscription management', async () => {
  const ref = await payment(); await service.applyCharge({ mode, plans }, ref); sub();
  await service.event({ event: 'subscription.create', data: { subscription_code: 'SUB_alice', domain: mode } });
  await db.doc('ripot_internal/paystack_config').update({ enabled: false });
  now = new Date('2026-11-14T12:00:00Z');
  assert.equal((await service.refresh(req())).entitled, true);
  assert.equal((await uRef('alice').get()).data().paystackLastVerifiedAtIso, now.toISOString());
  const catalog = await service.catalogue(req());
  assert.equal(catalog.enabled, false); assert.equal(catalog.canManage, true); assert.deepEqual(catalog.plans, []);
  responses['/subscription/SUB_alice/manage/link'] = { link: 'https://paystack.com/manage/fixture' };
  assert.equal((await service.manage(req())).url, 'https://paystack.com/manage/fixture');
});

test('foreign-card checkout can use NGN without silently converting the amount', async () => {
  const overseas = {...plans[0],id:'intl_ngn_monthly',code:'PLN_intlNGN',amount:1200000,markets:['international']};
  await db.doc('ripot_internal/paystack_config').update({ plans: [plans[0],plans[1],overseas] });
  responses['/plan/PLN_intlNGN'] = {...overseas,domain:mode};
  await service.start(req({ planId: overseas.id, market: 'international' }));
  const sent = calls.find(c => c.path === '/transaction/initialize').body;
  assert.equal(sent.amount, 1200000); assert.equal(sent.currency, 'NGN');
  assert.equal(sent.metadata.ripotMarket, 'international');
});

test('refresh repairs a missed subscription event and a renewal without a plan object', async () => {
  const ref = await payment(); await service.applyCharge({ mode, plans }, ref); sub();
  responses['/customer/CUS_alice'] = { subscriptions: [{ status: 'active', subscription_code: 'SUB_alice', plan: { plan_code: plans[0].code } }] };
  await service.refresh(req());
  assert.equal((await aRef('alice').get()).data().subscriptionCode, 'SUB_alice');
  now = new Date('2026-12-09T12:00:00Z');
  responses['/subscription/SUB_alice'].most_recent_invoice = { status: 'success', paid: 1, transaction: 124, period_end: '2027-01-09T12:00:00Z' };
  responses['/transaction/124'] = { reference: 'renewal_123' };
  responses['/transaction/verify/renewal_123'] = { ...responses[`/transaction/verify/${ref}`], id: 124, reference: 'renewal_123', paid_at: now.toISOString(), plan: null, metadata: {} };
  assert.equal((await service.refresh(req())).expiresAtIso, '2027-01-09T12:00:00.000Z');
});

test('pilot accounts are checked on both the catalogue and server checkout', async () => {
  await db.doc('ripot_internal/paystack_config').update({ allowedUids: ['bob'] });
  assert.equal((await service.catalogue(req())).enabled, false);
  await assert.rejects(payment(), { code: 'failed-precondition' });
  assert.equal(calls.length, 0);
});

test('starting again reconciles an old account before allowing another subscription', async () => {
  const ref = await payment(); await service.applyCharge({ mode, plans }, ref); sub();
  await service.event({ event: 'subscription.create', data: { subscription_code: 'SUB_alice', domain: mode } });
  now = new Date('2026-12-10T12:00:00Z');
  responses['/subscription/SUB_alice'].most_recent_invoice = { status: 'success', paid: 1, transaction: 124 };
  responses['/transaction/124'] = { reference: 'renewal_123' };
  responses['/transaction/verify/renewal_123'] = { ...responses[`/transaction/verify/${ref}`], id: 124,
    reference: 'renewal_123', paid_at: '2026-12-09T12:00:00Z', metadata: {} };
  await assert.rejects(service.start(req({ planId: 'ng_monthly', market: 'NG' })), { code: 'failed-precondition' });
  assert.equal((await uRef('alice').get()).data().premiumExpiresAtIso, '2027-01-09T12:00:00.000Z');
  assert.equal(calls.filter(c => c.path === '/transaction/initialize').length, 1);
});

test('API errors identify missing records without leaking provider details', async () => {
  const missing = createPaystackApi(() => 'sk_test_fixture', async () => ({ ok: false, status: 400,
    json: async () => ({ status: false, message: 'Customer specified not found' }) }));
  await assert.rejects(missing('/customer/alice%40example.test'), { code: 'not-found' });
  const unavailable = createPaystackApi(() => 'sk_test_fixture', async () => ({ ok: false, status: 500,
    json: async () => ({ status: false, message: 'SENSITIVE PROVIDER DETAILS' }) }));
  await assert.rejects(unavailable('/customer/alice'), e => e.code === 'unavailable' && !e.message.includes('SENSITIVE'));
});

test('country-specific NGN checkout uses server price and rejects a different country offer', async () => {
  const us = {...plans[0],id:'us_ngn_monthly',code:'PLN_countryUS',amount:1200000,markets:['US']};
  const gb = {...plans[0],id:'gb_ngn_monthly',code:'PLN_countryGB',amount:1100000,markets:['GB']};
  await db.doc('ripot_internal/paystack_config').update({plans:[...plans,us,gb]});
  responses['/plan/PLN_countryUS'] = {...us,domain:mode};
  await assert.rejects(service.start(req({planId:gb.id,market:'US'})),{code:'invalid-argument'});
  await assert.rejects(service.start(req({planId:'usd_monthly',market:'US'})),{code:'invalid-argument'});
  await service.start(req({planId:us.id,market:'US'}));
  const sent = calls.find(c=>c.path==='/transaction/initialize').body;
  assert.equal(sent.amount,1200000);
  assert.equal(sent.currency,'NGN');
  assert.equal(sent.metadata.ripotMarket,'US');
  const catalog = await service.catalogue(req());
  assert.equal(catalog.pendingMarket,'US');
  assert(catalog.billingCountries.some(c=>c.code==='GB'));
});
test('pending checkout cannot change country even if both use the same overseas offer', async () => {
  await service.start(req({planId:'usd_monthly',market:'US'}));
  await assert.rejects(service.start(req({planId:'usd_monthly',market:'GB'})), /original billing country/);
});
