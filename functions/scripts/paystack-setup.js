#!/usr/bin/env node
// Run on the operator's computer with explicit local Google credentials.
// Reads Paystack keys from Secret Manager; never accepts them as command arguments.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { GoogleAuth } = require('google-auth-library');
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { createPaystackApi, validateCatalog } = require('../paystack');
const PROJECT = 'ripot-4edf7';
const args = process.argv.slice(2);
const option = name => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : null; };
const mode = option('--mode');
function countryDefinitions(rows) {
  if (!Array.isArray(rows) || !rows.length) throw Error('Country prices must be a nonempty JSON array of confirmed offers.');
  const countries = new Set(require('../billing-countries.json').map(c => c.code));
  const seen = new Set();
  const minor = value => {
    // Decimal strings avoid rounding a guessed exchange rate or accepting excess precision.
    if (typeof value !== 'string' || !/^\d+(\.\d{1,2})?$/.test(value)) throw Error('Use confirmed decimal NGN price strings.');
    const parts = value.split('.');
    const amount = Number(parts[0]) * 100 + Number((parts[1] || '').padEnd(2, '0'));
    if (!Number.isSafeInteger(amount) || amount < 5000) throw Error('Invalid NGN amount.');
    return amount;
  };
  return rows.flatMap(row => {
    if (!countries.has(row?.country) || row.country === 'NG' || seen.has(row.country)) throw Error('Use unique overseas ISO country codes; Nigeria retains its approved offers.');
    seen.add(row.country);
    return [['monthly', row.monthlyNgn], ['annually', row.annualNgn]].map(([interval, value]) => ({
      id: `${row.country.toLowerCase()}_ngn_${interval === 'monthly' ? 'monthly' : 'annual'}`,
      amount: minor(value), currency: 'NGN', interval, markets: [row.country], enabled: true,
    }));
  });
}
async function resolveProviderPlan(api, definition, mode, available, requestedCode) {
  if (requestedCode && !/^PLN_[A-Za-z0-9]+$/.test(requestedCode)) throw Error('Invalid supplied plan code.');
  const region = definition.markets[0] === 'NG' || definition.markets[0] === 'international' ? '' : `${definition.markets[0]} `;
  const name = `Ripot Premium ${region}${definition.currency} ${definition.interval === 'monthly' ? 'Monthly' : 'Annual'}`;
  const matches = available.filter(p => p.name === name && p.domain === mode && p.currency === definition.currency &&
    p.amount === definition.amount && p.interval === definition.interval);
  if (!requestedCode && matches.length > 1) throw Error(`Multiple matching plans for ${name}; review the dashboard.`);
  const provider = requestedCode
    ? await api(`/plan/${encodeURIComponent(requestedCode)}`)
    : matches[0] || await api('/plan', { name, amount: definition.amount, currency: definition.currency,
      interval: definition.interval, send_invoices: true, send_sms: false });
  if (!/^PLN_[A-Za-z0-9]+$/.test(provider?.plan_code || '') ||
      (requestedCode && provider.plan_code !== requestedCode) || provider.domain !== mode ||
      provider.amount !== definition.amount || provider.currency !== definition.currency ||
      provider.interval !== definition.interval || provider.is_deleted === true ||
      (provider.invoice_limit != null && provider.invoice_limit !== 0)) {
    throw Error(`The provider plan does not match the required mode, price or recurring interval for ${definition.id}.`);
  }
  return { ...definition, code: provider.plan_code };
}
async function main() {
  if (!['test', 'live'].includes(mode)) throw Error('Use --mode test or --mode live.');
  const countryFile = option('--country-prices');
  // Validate every proposed amount before any network request or provider plan creation.
  const countryOffers = countryFile ? countryDefinitions(JSON.parse(fs.readFileSync(countryFile, 'utf8'))) : [];
  if (countryOffers.length && (!args.includes('--international-approved') || option('--international-currency') !== 'NGN')) {
    throw Error('Country pricing requires --international-approved --international-currency NGN.');
  }
  const credentialFile = process.env.GOOGLE_APPLICATION_CREDENTIALS ||
    path.join(os.homedir(), '.config/gcloud/application_default_credentials.json');
  if (!fs.existsSync(credentialFile)) throw Error('Local Google credentials are required. Run gcloud auth application-default login on your computer first.');
  // Never fall through to a cloud metadata server for credentials.
  process.env.GOOGLE_APPLICATION_CREDENTIALS = credentialFile;
  const auth = new GoogleAuth({ keyFilename: credentialFile, scopes: ['https://www.googleapis.com/auth/cloud-platform'] });
  const client = await auth.getClient();
  const secretResponse = await client.request({ url: `https://secretmanager.googleapis.com/v1/projects/${PROJECT}/secrets/PAYSTACK_SECRET_KEY/versions/latest:access` });
  const secret = Buffer.from(secretResponse.data.payload.data, 'base64').toString('utf8').trim();
  if (!secret.startsWith(`sk_${mode}_`)) throw Error('Secret Manager key does not match the selected payment mode.');
  const api = createPaystackApi(() => secret);
  initializeApp({ projectId: PROJECT, credential: applicationDefault() });
  const db = getFirestore(), configRef = db.doc('ripot_internal/paystack_config');
  const existing = (await configRef.get()).data();
  if (existing?.mode === 'live' && mode === 'test' && !(await db.collection('ripot_internal_paystack_live').limit(1).get()).empty) {
    throw Error('Live payment records exist. Use a separate project for further test-mode work.');
  }
  const testUid = option('--test-uid');
  if (mode === 'test' && !testUid) throw Error('A registered test Ripot UID is required with --test-uid.');
  const definitions = [
    { id: 'ng_monthly', amount: 250000, currency: 'NGN', interval: 'monthly', markets: ['NG'], enabled: true },
    { id: 'ng_annual', amount: 2500000, currency: 'NGN', interval: 'annually', markets: ['NG'], enabled: true },
  ];
  const international = args.includes('--international-approved');
  const internationalCurrency = option('--international-currency');
  const usdMonthly = option('--usd-monthly'), usdAnnual = option('--usd-annual');
  if (international && !['NGN', 'USD'].includes(internationalCurrency)) {
    throw Error('Choose the confirmed overseas charging currency with --international-currency NGN or USD.');
  }
  if (international && internationalCurrency === 'NGN') {
    // Do not silently give every overseas customer the Nigerian price.
    definitions.push(...countryOffers);
  }
  if (international && internationalCurrency === 'USD') {
    const minor = value => {
      if (!/^\d+(\.\d{1,2})?$/.test(value || '')) throw Error('Supply confirmed USD prices with --usd-monthly and --usd-annual.');
      return Math.round(Number(value) * 100);
    };
    definitions.push({ id: 'usd_monthly', amount: minor(usdMonthly), currency: 'USD', interval: 'monthly', markets: ['international'], enabled: true },
      { id: 'usd_annual', amount: minor(usdAnnual), currency: 'USD', interval: 'annually', markets: ['international'], enabled: true });
  }
  validateCatalog({ mode, plans: definitions.map((p, i) => ({ ...p, code: `PLN_preflight${i}` })) });
  // Get the full catalogue, preserving existing plan identities on reruns.
  const allPlans = [];
  for (let page = 1; page <= 100; page++) {
    const batch = await api(`/plan?perPage=100&page=${page}`);
    if (!Array.isArray(batch)) throw Error('Invalid plan list response.');
    allPlans.push(...batch);
    if (batch.length < 100) break;
    if (page === 100) throw Error('Too many provider plans; review manually.');
  }
  const plans = [];
  for (const definition of definitions) {
    const requestedCode = definition.id === 'ng_monthly' ? option('--ng-monthly-plan') :
      definition.id === 'ng_annual' ? option('--ng-annual-plan') : null;
    plans.push(await resolveProviderPlan(api, definition, mode, allPlans, requestedCode));
  }
  // Keep older codes for verification of existing subscribers, while disabling new sales.
  for (const old of existing?.mode === mode ? existing.plans || [] : []) {
    if (!plans.some(p => p.code === old.code)) plans.push({ ...old, id: `old_${old.code.slice(4)}`.toLowerCase(), enabled: false });
  }
  const config = { mode, enabled: mode === 'test' || args.includes('--enable-live'),
    internationalEnabled: international, testUids: testUid ? [testUid] : [], plans,
    allowedUids: option('--pilot-uid') ? [option('--pilot-uid')] : [],
    configuredAtIso: new Date().toISOString() };
  validateCatalog(config);
  await configRef.set(config);
  console.log(JSON.stringify({ mode, enabled: config.enabled, internationalEnabled: international,
    plans: plans.filter(p => p.enabled).map(({ id, amount, currency, interval, code }) => ({ id, amount, currency, interval, code })) }, null, 2));
  console.log('Webhook URL: https://us-central1-ripot-4edf7.cloudfunctions.net/paystackWebhook');
}
if (require.main === module) main().catch(error => { console.error(error.message || 'Paystack setup failed.'); process.exitCode = 1; });
module.exports = { resolveProviderPlan, countryDefinitions };
