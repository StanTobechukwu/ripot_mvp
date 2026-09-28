// Private operator job. Only someone with project-level Firestore console access
// can create a job; Firestore client rules deny this collection to every app.
const { FieldValue } = require('firebase-admin/firestore');
const { migrateFounders } = require('./founder-migration');

const HEX_SHA256 = /^[a-f0-9]{64}$/;

function validJob(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) return false;
  const keys = Object.keys(data).sort();
  if (data.action === 'preview') return keys.length === 1 && keys[0] === 'action';
  return data.action === 'apply' && keys.length === 2 &&
    keys[0] === 'action' && keys[1] === 'expectedHash' &&
    typeof data.expectedHash === 'string' && HEX_SHA256.test(data.expectedHash);
}

async function runFounderAdminJob(ref, db, auth) {
  // Firestore events are at least once. A job can be claimed only once, and an
  // interrupted job is reviewed with a new preview rather than replayed blind.
  const job = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.get('status')) return null;
    tx.update(ref, { status: 'running', startedAt: FieldValue.serverTimestamp() });
    return snap.data();
  });
  if (!job) return;
  if (!validJob(job)) {
    await ref.update({ status: 'failed', reason: 'invalid_job' });
    return;
  }
  try {
    const registeredUids = [];
    let pageToken;
    do {
      const page = await auth.listUsers(1000, pageToken);
      for (const user of page.users) {
        if (user.providerData?.length) registeredUids.push(user.uid);
      }
      pageToken = page.pageToken;
    } while (pageToken);
    const result = await migrateFounders(db, {
      registeredUids, includeLegacy: true,
      apply: job.action === 'apply', expectedHash: job.expectedHash,
    });
    await ref.update({ status: 'complete', result, finishedAt: FieldValue.serverTimestamp() });
  } catch (error) {
    // Never persist Auth credentials, account IDs, purchase data, or raw errors.
    await ref.update({ status: 'failed', reason: 'review_required', finishedAt: FieldValue.serverTimestamp() });
  }
}

module.exports = { runFounderAdminJob };
