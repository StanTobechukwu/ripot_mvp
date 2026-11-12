const { HttpsError } = require('firebase-functions/v2/https');
const { createHmac, timingSafeEqual, randomUUID } = require('node:crypto');
const { requireRegisteredUid } = require('./founding-100');
const { paidAccess, paidProjection, time } = require('./paid-access');
const billingCountries = require('./billing-countries.json');
const countryCodes = new Set(billingCountries.map(c => c.code));

const CONFIG = 'ripot_internal/paystack_config';
const RETURN_URL = 'https://ripot-web.web.app/?premium=return';
const REFERENCE = /^[A-Za-z0-9_-]{8,100}$/;
const PLAN = /^PLN_[A-Za-z0-9]+$/;
const DAY = 86400000;
const NIGERIA_PRICES = Object.freeze({ monthly: 250000, annually: 2500000 });
const fail = (message, code = 'failed-precondition') => { throw new HttpsError(code, message); };
const codeOf = value => typeof value === 'string' ? value : value?.plan_code;
const customerOf = data => data?.customer?.customer_code;
function decodeMetadata(value) {
  if (typeof value === 'string') { try { return JSON.parse(value); } catch (_) { return {}; } }
  return value && typeof value === 'object' ? value : {};
}
function nextPeriod(paidAt, interval) {
  const date = new Date(paidAt);
  if (!Number.isFinite(date.getTime())) fail('Invalid payment date.');
  const day = date.getUTCDate();
  date.setUTCDate(1);
  if (interval === 'monthly') {
    date.setUTCMonth(date.getUTCMonth() + 1);
    date.setUTCDate(Math.min(day, 28)); // Paystack uses the 28th for starts on 29–31.
  } else {
    date.setUTCFullYear(date.getUTCFullYear() + 1);
    const last = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0)).getUTCDate();
    date.setUTCDate(Math.min(day, last));
  }
  return date.toISOString();
}
function validateCatalog(config) {
  if (!['test', 'live'].includes(config?.mode)) fail('Payment setup is not complete.');
  const plans = Array.isArray(config.plans) ? config.plans : [];
  const ids = new Set();
  const codes = new Set();
  for (const p of plans) {
    if (!/^[a-z0-9_-]{2,60}$/.test(p.id || '') || ids.has(p.id) ||
        !PLAN.test(p.code || '') || codes.has(p.code) ||
        !['NGN', 'USD'].includes(p.currency) || !['monthly', 'annually'].includes(p.interval) ||
        !Number.isSafeInteger(p.amount) || p.amount < (p.currency === 'USD' ? 200 : 5000) ||
        !Array.isArray(p.markets) || p.markets.length === 0 ||
        p.markets.some(m => m !== 'international' && !countryCodes.has(m))) {
      fail('The payment catalogue needs an administrator review.');
    }
    ids.add(p.id); codes.add(p.code);
  }
  for (const interval of ['monthly', 'annually']) {
    const local = plans.filter(p => p.enabled === true && p.currency === 'NGN' && p.interval === interval && p.markets.includes('NG'));
    const floor = Math.max(NIGERIA_PRICES[interval], ...local.map(p => p.amount));
    if (plans.some(p => p.enabled === true && p.currency === 'NGN' && p.interval === interval &&
        p.markets.some(m => m !== 'NG') && p.amount <= floor)) {
      fail('International NGN prices must be higher than the Nigerian price for the same billing period.');
    }
  }
  return plans;
}
// A named country's approved offers take precedence over any general overseas offer.
// This is a customer-declared billing country, not verified residency or an IP check.
function plansForMarket(plans, market) {
  if (market !== 'international' && !countryCodes.has(market)) return [];
  const enabled = plans.filter(p => p.enabled === true);
  const exact = enabled.filter(p => p.markets.includes(market));
  return exact.length || market === 'NG' ? exact : enabled.filter(p => p.markets.includes('international'));
}
function verifySignature(raw, headers, apiSecret, webhookSecret, now = Date.now()) {
  if (!Buffer.isBuffer(raw) || raw.length > 1024 * 1024) return false;
  const modern = headers['paystack-signature'];
  const equal = (digest, hex) => typeof hex === 'string' && /^[0-9a-f]{128}$/.test(hex) &&
    timingSafeEqual(digest, Buffer.from(hex, 'hex'));
  if (modern) {
    if (typeof modern !== 'string' || !webhookSecret?.startsWith('whsec_')) return false;
    const parts = modern.split(',').map(p => p.trim());
    const ts = parts.filter(p => p.startsWith('t='));
    if (ts.length !== 1 || !/^t=\d+$/.test(ts[0])) return false;
    const timestamp = ts[0].slice(2);
    if (Math.abs(now / 1000 - Number(timestamp)) > 300) return false;
    const digest = createHmac('sha512', webhookSecret).update(`${timestamp}.`).update(raw).digest();
    return parts.some(p => /^v1=whk_[^:]+:/.test(p) && equal(digest, p.slice(p.indexOf(':') + 1)));
  }
  // Once a webhook signing secret is configured, do not downgrade to the legacy header.
  if (webhookSecret?.startsWith('whsec_')) return false;
  if (!apiSecret) return false;
  return equal(createHmac('sha512', apiSecret).update(raw).digest(), headers['x-paystack-signature']);
}
function createPaystackApi(secret, fetchImpl = fetch) {
  return async (path, body) => {
    const key = secret();
    if (!/^sk_(test|live)_/.test(key || '')) fail('Payment credentials are not configured.');
    let response;
    try {
      response = await fetchImpl(`https://api.paystack.co${path}`, {
        method: body ? 'POST' : 'GET',
        headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
        ...(body ? { body: JSON.stringify(body) } : {}),
        signal: AbortSignal.timeout(12000),
      });
    } catch (_) { fail('Paystack could not be reached. Please try again.', 'unavailable'); }
    let result;
    try { result = await response.json(); } catch (_) { fail('Paystack returned an invalid response.', 'unavailable'); }
    if (!response.ok || result.status !== true) {
      // Provider response bodies may contain payment details: never echo or log them.
      const absent = response.status === 404 || (!body && response.status === 400 &&
        /^(customer( specified)? not found|a customer with the specified email or code was not found|transaction reference not found)\.?$/i.test(result.message || ''));
      fail('Paystack could not complete this request.', absent ? 'not-found' : 'unavailable');
    }
    return result.data;
  };
}
function createPaystackService(db, { api, apiSecret = () => '', clock = () => new Date(), refreshPlay = async () => {} } = {}) {
  const configRef = db.doc(CONFIG);
  async function configFor(uid, checkout = false) {
    const config = (await configRef.get()).data();
    if (!config) return { enabled: false, mode: 'live', plans: [] };
    validateCatalog(config);
    if (checkout && config.enabled !== true) fail('Checkout is not available yet.');
    if (config.mode === 'test' && !(config.testUids || []).includes(uid)) fail('Test checkout is restricted.');
    if (checkout && config.allowedUids?.length && !config.allowedUids.includes(uid)) fail('Checkout is not available for this account yet.');
    if (checkout && !apiSecret().startsWith(`sk_${config.mode}_`)) fail('Payment mode does not match its credentials.');
    return config;
  }
  const accounts = mode => db.collection(`ripot_internal_paystack_${mode}`);
  const references = mode => db.collection(`ripot_internal_paystack_refs_${mode}`);
  const customers = mode => db.collection(`ripot_internal_paystack_customers_${mode}`);
  const subscriptions = mode => db.collection(`ripot_internal_paystack_subscriptions_${mode}`);
  // Test-mode payments can NEVER grant production Premium, even with live Firebase.
  const access = (mode, uid) => db.collection(mode === 'live' ? 'ripot_user_access' : 'ripot_test_user_access').doc(uid);
  function assertDomain(data, config) {
    if (data?.domain !== config.mode) fail('Payment environment mismatch.');
  }
  async function catalogue(request) {
    const uid = requireRegisteredUid(request);
    const c = await configFor(uid);
    const state = (await access(c.mode, uid).get()).data() || {};
    const account = (await accounts(c.mode).doc(uid).get()).data() || {};
    const paid = paidAccess(state, clock());
    const trial = Math.max(time(state.trialEndsAtIso), time(state.adminTrialEndsAtIso)) > clock().getTime();
    const locked = paid || state.adminPlanOverride === 'premium' ? 'paid' : trial ? 'trial' : null;
    const enabled = c.enabled === true && (!c.allowedUids?.length || c.allowedUids.includes(uid));
    return { enabled, mode: c.mode,
      internationalEnabled: c.internationalEnabled === true,
      billingCountries,
      plans: validateCatalog(c).filter(p => enabled && p.enabled === true && (c.internationalEnabled === true || p.markets.includes('NG'))).map(({ id, amount, currency, interval, markets }) =>
        ({ id, amount, currency, interval, markets })),
      locked, provider: paid?.provider || null, expiresAtIso: paid?.expiresAtIso || null,
      subscriptionStatus: account.subscriptionStatus || null,
      canManage: Boolean(account.subscriptionCode), pendingPlanId: account.pendingPlanId || null,
      pendingMarket: account.pendingMarket || null,
      paymentConfirmed: Boolean(account.lastReference),
    };
  }
  async function start(request) {
    const uid = requireRegisteredUid(request);
    const data = request.data || {};
    if (Object.keys(data).some(k => !['planId', 'market'].includes(k))) fail('Only a plan and billing market are accepted.', 'invalid-argument');
    const c = await configFor(uid, true);
    const p = plansForMarket(validateCatalog(c), data.market).find(p => p.id === data.planId);
    if (!p || (data.market !== 'NG' && c.internationalEnabled !== true)) fail('This payment option is not available.', 'invalid-argument');
    const email = request.auth.token?.email;
    if (typeof email !== 'string' || !email.includes('@')) fail('A Ripot account email is required.');
    if (c.mode === 'live') await refreshPlay(uid); // Fail closed when an existing Play purchase cannot be checked.
    const aRef = accounts(c.mode).doc(uid);
    const prior = (await aRef.get()).data();
    if (prior?.lastReference || prior?.subscriptionCode) await refreshUid(uid);
    const reference = await db.runTransaction(async tx => {
      const a = (await tx.get(aRef)).data() || {};
      const state = (await tx.get(access(c.mode, uid))).data() || {};
      if (paidAccess(state, clock()) || state.adminPlanOverride === 'premium') fail('Premium is already active. Manage your existing subscription.');
      if (time(state.trialEndsAtIso) > clock().getTime() || time(state.adminTrialEndsAtIso) > clock().getTime()) fail('Your free Premium trial is still active.');
      if (a.subscriptionCode && !['cancelled', 'completed', 'complete'].includes(a.subscriptionStatus)) fail('Manage your existing Paystack subscription before starting another.');
      if (a.pendingReference) {
        if (a.pendingPlanId !== p.id) fail('Resume your existing checkout before choosing a different plan.');
        if (a.pendingMarket && a.pendingMarket !== data.market) fail('Resume your existing checkout for its original billing country.');
        return a.pendingReference;
      }
      const ref = `ripot_${randomUUID().replaceAll('-', '')}`;
      tx.set(aRef, { pendingReference: ref, pendingPlanId: p.id, pendingMarket: data.market, latestCheckoutPlanCode: p.code, latestCheckoutAmount: p.amount }, { merge: true });
      tx.create(references(c.mode).doc(ref), { uid, planId: p.id, planCode: p.code,
        amount: p.amount, currency: p.currency, interval: p.interval, market: data.market,
        email, createdAtIso: clock().toISOString(), status: 'initializing' });
      return ref;
    });
    const ref = references(c.mode).doc(reference);
    const order = (await ref.get()).data();
    if (order.authorizationUrl) return { authorizationUrl: order.authorizationUrl, reference, mode: c.mode };
    // Concurrent initializations share the SAME reference; Paystack rejects duplicates.
    const providerPlan = await api(`/plan/${encodeURIComponent(p.code)}`);
    assertDomain(providerPlan, c);
    if (providerPlan.amount !== p.amount || providerPlan.currency !== p.currency || providerPlan.interval !== p.interval) fail('The provider plan does not match the displayed price.');
    let customer;
    try { customer = await api(`/customer/${encodeURIComponent(email)}`); }
    catch (error) { if (error.code !== 'not-found') throw error; customer = await api('/customer', { email }); }
    if (!/^CUS_[A-Za-z0-9]+$/.test(customer.customer_code || '')) fail('Invalid payment customer.');
    await db.runTransaction(async tx => {
      const owner = customers(c.mode).doc(customer.customer_code);
      const old = (await tx.get(owner)).data();
      if (old?.uid && old.uid !== uid) fail('This payment email belongs to another Ripot account.');
      tx.set(owner, { uid });
      tx.set(aRef, { customerCode: customer.customer_code }, { merge: true });
      tx.set(ref, { customerCode: customer.customer_code }, { merge: true });
    });
    const result = await api('/transaction/initialize', {
      email, amount: p.amount, currency: p.currency, plan: p.code, reference,
      callback_url: RETURN_URL, channels: ['card'],
      metadata: { ripotUid: uid, ripotPlanId: p.id, ripotMarket: data.market, cancel_action: RETURN_URL },
    });
    const url = new URL(result.authorization_url || '');
    if (url.origin !== 'https://checkout.paystack.com' || result.reference !== reference) fail('Invalid checkout response.');
    await ref.set({ authorizationUrl: url.href, status: 'pending' }, { merge: true });
    return { authorizationUrl: url.href, reference, mode: c.mode };
  }
  async function commitPayment(c, uid, payment, { revoke = false } = {}) {
    const aRef = accounts(c.mode).doc(uid), uRef = access(c.mode, uid);
    await db.runTransaction(async tx => {
      const u = (await tx.get(uRef)).data() || {};
      const a = (await tx.get(aRef)).data() || {};
      const ledger = await tx.get(aRef.collection('payments'));
      const old = ledger.docs.find(d => d.id === payment.reference)?.data();
      const claimRef = db.collection(`ripot_internal_paystack_ids_${c.mode}`).doc(String(payment.transactionId));
      const claim = (await tx.get(claimRef)).data();
      if (claim && (claim.uid !== uid || claim.reference !== payment.reference)) fail('Payment was already assigned.');
      if (old && (old.transactionId !== payment.transactionId || old.amount !== payment.amount || old.currency !== payment.currency)) fail('Payment details changed.');
      const record = { ...payment, expiresAtIso: old?.expiresAtIso || payment.expiresAtIso,
        verifiedAtIso: clock().toISOString(), revoked: revoke || old?.revoked === true };
      const records = ledger.docs.filter(d => d.id !== payment.reference).map(d => d.data()).concat(record);
      const active = records.filter(p => !p.revoked && time(p.expiresAtIso) > clock().getTime())
        .sort((a, b) => time(b.expiresAtIso) - time(a.expiresAtIso));
      const fields = { paystackEntitlementExpiresAtIso: active[0]?.expiresAtIso || null,
        paystackLastVerifiedAtIso: active[0]?.verifiedAtIso || clock().toISOString() };
      tx.set(claimRef, { uid, reference: payment.reference });
      tx.set(aRef.collection('payments').doc(payment.reference), record);
      tx.set(references(c.mode).doc(payment.reference), { uid, status: record.revoked ? 'reversed' : 'success',
        transactionId: payment.transactionId }, { merge: true });
      tx.set(aRef, { lastReference: active[0]?.reference || payment.reference,
        ...(!a.subscriptionCode ? { planCode: payment.planCode, amount: payment.amount, currency: payment.currency, interval: payment.interval } : {}),
        ...(a.pendingReference === payment.reference ? { pendingReference: null, pendingPlanId: null, pendingMarket: null } : {}) }, { merge: true });
      tx.set(uRef, { ownerType: 'user', ownerId: uid, authUid: uid, ...fields,
        premiumStartedAtIso: u.premiumStartedAtIso || payment.paidAtIso,
        ...paidProjection({ ...u, ...fields }, clock()) }, { merge: true });
    });
  }
  async function applyCharge(c, reference, invoice = null) {
    if (!REFERENCE.test(reference || '')) fail('Invalid payment reference.', 'invalid-argument');
    const transaction = await api(`/transaction/verify/${encodeURIComponent(reference)}`);
    assertDomain(transaction, c);
    if (transaction.reference !== reference || !Number.isSafeInteger(transaction.id)) fail('Invalid verified payment.');
    const order = (await references(c.mode).doc(reference).get()).data();
    const owner = customerOf(transaction) && (await customers(c.mode).doc(customerOf(transaction)).get()).data();
    if (!owner?.uid) return { ignored: true }; // Payments created outside Ripot do not grant access.
    const uid = owner.uid;
    if (order?.uid && order.uid !== uid) fail('Payment account mismatch.');
    const aRef = accounts(c.mode).doc(uid);
    const a = (await aRef.get()).data() || {};
    const existing = (await aRef.collection('payments').doc(reference).get()).data();
    if (transaction.status !== 'success') {
      if (existing && transaction.status === 'reversed') await commitPayment(c, uid, existing, { revoke: true });
      return { status: transaction.status };
    }
    const planCode = codeOf(transaction.plan_object) || codeOf(transaction.plan);
    const expected = order?.planCode || existing?.planCode || a.planCode;
    if (!expected || (planCode && planCode !== expected)) fail('Payment plan mismatch.');
    // Unknown references are renewals only when tied to the stored subscription.
    if (!order && (!a.subscriptionCode || (!planCode && invoice?.subscription?.subscription_code !== a.subscriptionCode))) fail('Unrecognised renewal.');
    const p = validateCatalog(c).find(p => p.code === expected);
    // Stored checkout and subscription prices preserve existing subscribers when the catalogue changes.
    const amount = order?.amount ?? existing?.amount ?? a.amount ?? p?.amount;
    const currency = order?.currency ?? existing?.currency ?? a.currency ?? p?.currency;
    const interval = order?.interval ?? existing?.interval ?? a.interval ?? p?.interval;
    if (transaction.amount !== amount || transaction.currency !== currency || !['monthly', 'annually'].includes(interval)) fail('Payment amount or currency mismatch.');
    if (order?.planCode && decodeMetadata(transaction.metadata).ripotUid !== uid) fail('Payment identity mismatch.');
    const paid = time(transaction.paid_at || transaction.paidAt);
    if (!paid || paid > clock().getTime() + 300000) fail('Invalid payment timestamp.');
    let expiry = nextPeriod(paid, interval);
    if (invoice) {
      if (invoice.subscription?.subscription_code !== a.subscriptionCode || invoice.transaction?.reference !== reference ||
          invoice.paid !== true || invoice.status !== 'success') fail('Invoice does not confirm this payment.');
      const end = time(invoice.period_end);
      if (end > paid && end <= time(expiry) + DAY) expiry = new Date(end).toISOString();
    }
    await commitPayment(c, uid, { reference, transactionId: transaction.id, amount, currency,
      planCode: expected, interval, paidAtIso: new Date(paid).toISOString(), expiresAtIso: expiry });
    return { status: 'success', mode: c.mode };
  }
  async function updateSubscription(c, code) {
    if (!/^SUB_[A-Za-z0-9]+$/.test(code || '')) fail('Invalid subscription.');
    const sub = await api(`/subscription/${encodeURIComponent(code)}`);
    assertDomain(sub, c);
    if (sub.subscription_code !== code) fail('Subscription mismatch.');
    const owner = customerOf(sub) && (await customers(c.mode).doc(customerOf(sub)).get()).data();
    if (!owner?.uid) return null;
    const uid = owner.uid, aRef = accounts(c.mode).doc(uid), mapRef = subscriptions(c.mode).doc(code);
    await db.runTransaction(async tx => {
      const a = (await tx.get(aRef)).data() || {};
      const mapping = (await tx.get(mapRef)).data();
      const pending = a.pendingReference ? (await tx.get(references(c.mode).doc(a.pendingReference))).data() : null;
      const p = validateCatalog(c).find(p => p.code === codeOf(sub.plan));
      if (!p || (mapping?.uid && mapping.uid !== uid) ||
          (a.subscriptionCode && a.subscriptionCode !== code && !['cancelled', 'completed', 'complete'].includes(a.subscriptionStatus)) ||
          (!mapping && a.planCode !== p.code && pending?.planCode !== p.code && a.latestCheckoutPlanCode !== p.code)) fail('Subscription is not linked to this checkout.');
      if (sub.plan.currency !== p.currency || sub.plan.interval !== p.interval || sub.amount !== (a.subscriptionCode === code ? a.amount : pending?.amount ?? a.latestCheckoutAmount ?? p.amount)) fail('Subscription price mismatch.');
      tx.set(mapRef, { uid });
      tx.set(aRef, { subscriptionCode: code, subscriptionStatus: sub.status,
        planCode: p.code, amount: sub.amount, currency: sub.plan.currency, interval: sub.plan.interval }, { merge: true });
    });
    return { uid, sub };
  }
  async function refreshUid(uid) {
    const c = await configFor(uid);
    // Disabling NEW sales must not strand existing subscribers or hide refunds.
    const aRef = accounts(c.mode).doc(uid);
    let a = (await aRef.get()).data();
    if (!a) return { checked: false, mode: c.mode };
    if (a.pendingReference) {
      try { await applyCharge(c, a.pendingReference); }
      catch (error) { if (error.code !== 'not-found') throw error; }
    }
    a = (await aRef.get()).data() || {};
    if (!a.subscriptionCode && a.customerCode && a.planCode) {
      // Repair a delayed/missing subscription.create event from Paystack itself.
      const customer = await api(`/customer/${encodeURIComponent(a.customerCode)}`);
      const matching = (customer.subscriptions || []).filter(s =>
        codeOf(s.plan) === a.planCode && !['cancelled', 'completed', 'complete'].includes(s.status));
      if (matching.length === 1) await updateSubscription(c, matching[0].subscription_code);
      a = (await aRef.get()).data() || {};
    }
    if (a.subscriptionCode) {
      const info = await updateSubscription(c, a.subscriptionCode);
      const latest = info?.sub?.most_recent_invoice;
      if (latest?.transaction && ['success', 'paid'].includes(latest.status)) {
        const id = typeof latest.transaction === 'object' ? latest.transaction.id : latest.transaction;
        if (Number.isSafeInteger(Number(id))) {
          const tx = await api(`/transaction/${Number(id)}`);
          if (tx.reference) await applyCharge(c, tx.reference, { ...latest, paid: true, status: 'success',
            subscription: { subscription_code: a.subscriptionCode }, transaction: { id: Number(id), reference: tx.reference } });
        }
      }
    }
    a = (await aRef.get()).data() || {};
    if (a.lastReference) await applyCharge(c, a.lastReference);
    const state = (await access(c.mode, uid).get()).data() || {};
    return { checked: true, mode: c.mode, entitled: Boolean(paidAccess(state, clock())),
      expiresAtIso: state.paystackEntitlementExpiresAtIso || null };
  }
  async function manage(request) {
    const uid = requireRegisteredUid(request), c = await configFor(uid);
    const a = (await accounts(c.mode).doc(uid).get()).data();
    if (!a?.subscriptionCode) fail('No Paystack subscription is linked to this account.');
    const result = await api(`/subscription/${encodeURIComponent(a.subscriptionCode)}/manage/link`);
    const url = new URL(result.link || '');
    if (url.protocol !== 'https:' || !(url.hostname === 'paystack.com' || url.hostname.endsWith('.paystack.com'))) fail('Invalid subscription management link.');
    return { url: url.href };
  }
  async function event(body) {
    const c = (await configRef.get()).data();
    if (!c) return;
    validateCatalog(c);
    const data = body?.data || {};
    if (data.domain && data.domain !== c.mode) return;
    if (body.event === 'charge.success') return applyCharge(c, data.reference);
    if (['subscription.create', 'subscription.disable', 'subscription.not_renew'].includes(body.event)) return updateSubscription(c, data.subscription_code);
    if (['invoice.update', 'invoice.payment_failed'].includes(body.event)) {
      await updateSubscription(c, data.subscription?.subscription_code);
      if (data.paid === true && data.status === 'success' && data.transaction?.reference) return applyCharge(c, data.transaction.reference, data);
      return; // Failed renewals never extend previously paid time.
    }
    if (['refund.processed', 'charge.dispute.resolve'].includes(body.event)) {
      const id = typeof data.transaction === 'object' ? data.transaction.id : data.transaction;
      if (!Number.isSafeInteger(Number(id))) return;
      const claim = (await db.collection(`ripot_internal_paystack_ids_${c.mode}`).doc(String(id)).get()).data();
      if (!claim) return;
      const record = (await accounts(c.mode).doc(claim.uid).collection('payments').doc(claim.reference).get()).data();
      if (body.event === 'refund.processed' && record && data.amount >= record.amount) {
        return commitPayment(c, claim.uid, record, { revoke: true });
      }
      return applyCharge(c, claim.reference); // Provider-reported reversal revokes only this payment.
    }
  }
  return { catalogue, start, manage, refreshUid, event, applyCharge,
    refresh: request => refreshUid(requireRegisteredUid(request)) };
}
module.exports = { CONFIG, RETURN_URL, NIGERIA_PRICES, validateCatalog, plansForMarket, nextPeriod, verifySignature, createPaystackApi, createPaystackService };
