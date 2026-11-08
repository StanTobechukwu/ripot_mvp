const { onCall } = require('firebase-functions/v2/https');
const { defineBoolean, defineString, defineSecret } = require('firebase-functions/params');
const { getFirestore } = require('firebase-admin/firestore');
const { createMicrosoftService } = require('./microsoft-store');

const enabled = defineBoolean('MICROSOFT_BILLING_ENABLED', { default: false });
const tenantId = defineString('MICROSOFT_TENANT_ID', { default: '' });
const clientId = defineString('MICROSOFT_CLIENT_ID', { default: '' });
const monthlyId = defineString('MICROSOFT_MONTHLY_STORE_ID', { default: '' });
const annualId = defineString('MICROSOFT_ANNUAL_STORE_ID', { default: '' });
const clientSecret = defineSecret('MICROSOFT_CLIENT_SECRET');
const service = createMicrosoftService(getFirestore(), { config: () => ({ enabled: enabled.value(),
  tenantId: tenantId.value(), clientId: clientId.value(), monthlyId: monthlyId.value(),
  annualId: annualId.value(), clientSecret: enabled.value() ? clientSecret.value() : '' }) });
const options = { region: 'us-central1', maxInstances: 4, concurrency: 20, timeoutSeconds: 60,
  memory: '256MiB', secrets: [clientSecret] };
exports.getMicrosoftBillingConfig = onCall(options, service.config);
exports.getMicrosoftPurchaseTicket = onCall(options, service.ticket);
exports.verifyMicrosoftSubscription = onCall(options, service.verify);
exports.refreshMicrosoftEntitlement = onCall(options, service.refresh);
