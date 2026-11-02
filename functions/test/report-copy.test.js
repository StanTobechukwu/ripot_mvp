const { test, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.GCLOUD_PROJECT?.startsWith('demo-')) {
  throw new Error('Use the Firestore emulator and a demo- project. Tests erase emulator data.');
}
const endpoints = require('../index');
const { getFirestore } = require('firebase-admin/firestore');
const { getApp, deleteApp } = require('firebase-admin/app');
const { createReportCopyService, COPY_ALLOWANCES } = require('../report-copy');
const db = getFirestore();
let now = new Date('2026-11-02T12:00:00Z');
const service = createReportCopyService(db, () => now);
const fp = value => createHash('sha256').update(String(value)).digest('hex');
const request = (value, uid = 'alice') => ({ auth: { uid, token: { firebase: { sign_in_provider: 'password' } } },
  data: value === undefined ? {} : { fingerprint: fp(value) } });
beforeEach(async () => {
  now = new Date('2026-11-02T12:00:00Z');
  const result = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  assert.equal(result.ok, true);
});
after(() => deleteApp(getApp()));

test('both callables are exported and reject guests, client plans and report text', async () => {
  assert.equal(typeof endpoints.getReportCopyAllowance, 'function');
  assert.equal(typeof endpoints.authorizeReportCopy, 'function');
  await assert.rejects(service.authorize({data:{fingerprint:fp(1)}}), {code:'unauthenticated'});
  await assert.rejects(service.authorize({ ...request(1), auth:{uid:'guest',token:{firebase:{sign_in_provider:'anonymous'}}} }), {code:'failed-precondition'});
  for (const data of [{fingerprint:fp(1),uid:'bob'}, {fingerprint:fp(1),plan:'premium'},
    {text:'PATIENT TEXT'}, {fingerprint:'bad'}, {fingerprint:fp(1),remaining:50}, []]) {
    await assert.rejects(service.authorize({...request(1),data}), {code:'invalid-argument'});
  }
  await assert.rejects(service.status(request(1)), {code:'invalid-argument'});
  assert.equal((await db.collection(COPY_ALLOWANCES).get()).size, 0);
});

test('unchanged versions and concurrent retries count once across sessions; changed text counts again', async () => {
  const results = await Promise.all(Array.from({length:6}, () => service.authorize(request('same text'))));
  assert.equal(results.filter(r => r.charged).length, 1);
  assert(results.every(r => r.remaining === 49));
  const newSession = createReportCopyService(db, () => now);
  assert.equal((await newSession.authorize(request('same text'))).remaining, 49);
  assert.equal((await newSession.authorize(request('rewritten draft'))).remaining, 48);
  assert.equal((await service.authorize(request('same text', 'bob'))).remaining, 49);
  const saved = (await db.collection(COPY_ALLOWANCES).doc('alice').get()).data();
  assert.deepEqual(Object.keys(saved).sort(), ['fingerprints','schemaVersion','updatedAt']);
  assert.equal(JSON.stringify(saved).includes('same text'), false);
});

test('the 50-version cap is atomic, does not reset with time, and still permits repeats at zero', async () => {
  await db.collection(COPY_ALLOWANCES).doc('alice').set({schemaVersion:1, fingerprints:Array.from({length:49}, (_,i)=>fp(i))});
  const results = await Promise.allSettled(Array.from({length:6}, (_,i)=>service.authorize(request(100+i))));
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert(results.filter(r=>r.status==='rejected').every(r=>r.reason.code==='resource-exhausted'));
  now = new Date('2028-01-01');
  assert.equal((await service.status(request())).remaining, 0);
  assert.equal((await service.authorize(request(0))).repeated, true);
  await assert.rejects(service.authorize(request('new')), {code:'resource-exhausted'});
});

test('trials and paid access preserve the free ledger and stop at expiry or revocation', async () => {
  const access = db.collection('ripot_user_access').doc('alice');
  await service.authorize(request('free first'));
  await access.set({plan:'trial',trialEndsAtIso:'2026-11-03T12:00:00Z'});
  assert.equal((await service.authorize(request('trial report'))).unlimited, true);
  assert.equal((await service.status(request())).remaining, 49);
  now = new Date('2026-11-03T12:00:00Z');
  assert.equal((await service.authorize(request('trial report'))).remaining, 48);
  await access.set({plan:'premium',entitlementAuthority:'google_play_verified',
    playEntitlementExpiresAtIso:'2026-12-01',billingLastVerifiedAtIso:now.toISOString()});
  assert.equal((await service.authorize(request('paid'))).unlimited, true);
  now = new Date('2026-11-06T12:00:00Z'); // freshness ends exactly at 72 hours
  assert.equal((await service.authorize(request('paid'))).unlimited, false);
  await access.set({adminPlanOverride:'premium'}, {merge:true});
  assert.equal((await service.status(request())).unlimited, true);
  await access.set({adminPlanOverride:'free'}, {merge:true});
  assert.equal((await service.status(request())).unlimited, false);
  // Removing the entitlement document cannot reset the independent ledger.
  await access.delete();
  assert.equal((await service.status(request())).remaining, 47);
});

test('legacy premium flags and malformed quota records fail closed', async () => {
  const access = db.collection('ripot_user_access').doc('alice');
  await access.set({plan:'premium'});
  assert.equal((await service.status(request())).unlimited, false);
  const quota = db.collection(COPY_ALLOWANCES).doc('alice');
  for (const data of [{schemaVersion:1,fingerprints:[fp(1),fp(1)]},
    {schemaVersion:0,fingerprints:[]}, {schemaVersion:1,fingerprints:['bad']}]) {
    await quota.set(data);
    await assert.rejects(service.authorize(request('new')), {code:'failed-precondition'});
  }
});
