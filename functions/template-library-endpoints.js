'use strict';
const { onCall, onRequest } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { defineString, defineSecret } = require('firebase-functions/params');
const { getFirestore } = require('firebase-admin/firestore');
const { createTemplateLibrary, C } = require('./template-library');
const service = createTemplateLibrary(getFirestore());
const options = { region: 'us-central1', maxInstances: 10, timeoutSeconds: 30 };
exports.submitTemplateContribution = onCall(options, service.submit);
exports.listTemplateContributions = onCall(options, service.list);
exports.reviewTemplateContribution = onCall(options, service.review);
exports.publicTemplateLibrary = onRequest({ ...options, cors: true }, async (req, res) => {
  if (req.method !== 'GET') return res.status(405).set('Allow','GET').end();
  try {
    const data = req.query.template ? await service.publicDetail(req.query.template, req.query.version) : await service.publicList(req.query.cursor);
    res.set('Cache-Control', 'public, max-age=60').json(data);
  } catch (error) {
    res.status(error.code === 'not-found' ? 404 : error.code === 'invalid-argument' ? 400 : 503).json({ error: 'Template library unavailable.' });
  }
});
// Only this worker reads the SMTP secret. Durable queue survives mail outages.
// SMTP is at-least-once: a crash after acceptance may deliver the same Message-ID twice.
const smtpHost = defineString('TEMPLATE_SMTP_HOST', { default: 'mail.privateemail.com' });
const smtpUser = defineString('TEMPLATE_SMTP_USER', { default: 'support@ripot.app' });
const smtpPassword = defineSecret('TEMPLATE_SMTP_PASSWORD');
exports.notifyTemplateContribution = onDocumentCreated({
  document: `${C.mail}/{mailId}`, region: 'us-central1', retry: true,
  secrets: [smtpPassword], maxInstances: 3, timeoutSeconds: 120,
}, async event => {
  const ref = event.data?.ref;
  if (!ref) return;
  const nodemailer = require('nodemailer');
  const transport = nodemailer.createTransport({ host: smtpHost.value(), port: 465, secure: true, auth: { user: smtpUser.value(), pass: smtpPassword.value() }, connectionTimeout: 15000, socketTimeout: 30000 });
  try {
    const { deliverTemplateNotification } = require('./template-notification');
    await deliverTemplateNotification(ref, event.params.mailId, message => transport.sendMail(message), smtpUser.value());
  } finally { transport.close(); }
});
