const { test } = require('node:test');
const assert = require('node:assert/strict');
const { resolveProviderPlan } = require('../scripts/paystack-setup');
const monthly = { id: 'ng_monthly', amount: 250000, currency: 'NGN', interval: 'monthly', markets: ['NG'], enabled: true };
const provider = { plan_code: 'PLN_selected', name: 'Manually named monthly plan', domain: 'test', amount: 250000,
  currency: 'NGN', interval: 'monthly', invoice_limit: 0 };

test('an explicit existing plan is reused even when names differ or other matching plans exist', async () => {
  const calls = [];
  const other = { ...provider, plan_code: 'PLN_other', name: 'Ripot Premium NGN Monthly' };
  const result = await resolveProviderPlan(async (path, body) => { calls.push({ path, body }); return provider; },
    monthly, 'test', [other, other], 'PLN_selected');
  assert.equal(result.code, 'PLN_selected');
  assert.deepEqual(calls, [{ path: '/plan/PLN_selected', body: undefined }]);
});

test('swapped annual plans, live plans and changed prices cannot become the test monthly offer', async () => {
  for (const change of [{ interval: 'annually', amount: 2500000 }, { domain: 'live' }, { currency: 'USD' },
    { amount: 1 }, { plan_code: 'PLN_wrong' }, { invoice_limit: 1 }, { is_deleted: true }]) {
    await assert.rejects(resolveProviderPlan(async () => ({ ...provider, ...change }), monthly, 'test', [], 'PLN_selected'),
      /does not match/);
  }
});

test('missing or invalid supplied codes do not fall back to silently creating another plan', async () => {
  const calls = [];
  const api = async (path, body) => { calls.push({ path, body }); throw Error('Provider plan was not found'); };
  await assert.rejects(resolveProviderPlan(api, monthly, 'test', [], 'PLN_missing'), /not found/);
  await assert.rejects(resolveProviderPlan(api, monthly, 'test', [], '../wrong'), /Invalid supplied/);
  assert.deepEqual(calls, [{ path: '/plan/PLN_missing', body: undefined }]);
});
