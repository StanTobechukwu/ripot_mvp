'use strict';
// Inject sendMail for tests: no network or credentials are required to verify
// queue transitions, retry behavior and recipient/content restrictions.
async function deliverTemplateNotification(ref, mailId, sendMail, sender, getUser) {
  const row = (await ref.get()).data();
  if (!row || ['sent', 'skipped'].includes(row.status)) return;
  try {
    let message = {
      from: sender, to: 'support@ripot.app',
      messageId: `<${mailId}@ripot.app>`, subject: 'Ripot: template contribution awaiting review',
      text: `A template contribution is awaiting review.\nSubmission: ${row.submissionId}\nRevision: ${row.revision}\n\nSign in to your reviewer account:\nhttps://ripot-web.web.app/?templateLibrary=review\n`,
    };
    if (row.kind === 'decision') {
      const labels = { approved: 'approved', rejected: 'rejected', changes_requested: 'changes requested' };
      if (!labels[row.decision] || !row.ownerUid) throw new Error('Invalid decision notification.');
      let account;
      try { account = await getUser(row.ownerUid); }
      catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
      if (!account?.email || account.disabled) {
        await ref.update({ status: 'skipped', lastError: 'Contributor account has no deliverable email.' });
        return;
      }
      // Never accept a recipient from the callable request or queue's `to` field.
      message = {
        from: sender, to: { address: account.email },
        messageId: `<${mailId}@ripot.app>`,
        subject: `Ripot: template ${labels[row.decision]}`,
        text: `Your template "${row.name}" (revision ${row.revision}) has been reviewed.\nDecision: ${labels[row.decision]}\n${row.note ? `\nReviewer feedback:\n${row.note}\n` : ''}\nSign in with your contributor account to view My submissions${row.decision === 'approved' ? '.' : ', make changes and resubmit.'}\nhttps://ripot-web.web.app/?templateLibrary=mine\n`,
      };
    }
    await sendMail(message);
    await ref.update({ status: 'sent', sentAt: Date.now(), lastError: null });
  } catch (_) {
    await ref.update({ status: 'retrying', lastAttemptAt: Date.now(), lastError: 'SMTP delivery failed; inspect provider and configuration.' });
    throw new Error('Template review email delivery failed.');
  }
}
module.exports = { deliverTemplateNotification };
