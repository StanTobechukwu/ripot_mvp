'use strict';
// Inject sendMail for tests: no network or credentials are required to verify
// queue transitions, retry behavior and recipient/content restrictions.
async function deliverTemplateNotification(ref, mailId, sendMail, sender) {
  const row = (await ref.get()).data();
  if (!row || row.status === 'sent') return;
  try {
    await sendMail({
      from: sender, to: 'support@ripot.app',
      messageId: `<${mailId}@ripot.app>`, subject: 'Ripot: template contribution awaiting review',
      text: `A template contribution is awaiting review.\nSubmission: ${row.submissionId}\nRevision: ${row.revision}\n\nSign in to your reviewer account:\nhttps://ripot-web.web.app/?templateLibrary=review\n`,
    });
    await ref.update({ status: 'sent', sentAt: Date.now(), lastError: null });
  } catch (_) {
    await ref.update({ status: 'retrying', lastAttemptAt: Date.now(), lastError: 'SMTP delivery failed; inspect provider and configuration.' });
    throw new Error('Template review email delivery failed.');
  }
}
module.exports = { deliverTemplateNotification };
