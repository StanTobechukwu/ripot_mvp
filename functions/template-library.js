'use strict';
const { HttpsError } = require('firebase-functions/v2/https');
const { createHash } = require('node:crypto');
const C = {
  submissions: 'ripot_template_submissions', reviewers: 'ripot_template_reviewers',
  published: 'ripot_public_templates', mail: 'ripot_template_mail', limits: 'ripot_template_limits',
};
function fail(code, message) { throw new HttpsError(code, message); }
function string(value, max, required = false) {
  if (value == null && !required) return '';
  if (typeof value !== 'string' || value.trim().length > max || (required && !value.trim())) {
    fail('invalid-argument', 'Check the required fields and their lengths.');
  }
  return value.trim();
}
function identifier(value) {
  if (typeof value !== 'string' || !/^[a-zA-Z0-9_-]{1,100}$/.test(value)) fail('invalid-argument', 'Invalid identifier.');
  return value;
}
function user(request) {
  if (!request.auth || request.auth.token?.firebase?.sign_in_provider === 'anonymous') fail('unauthenticated', 'Sign in to contribute.');
  return request.auth.uid;
}
// Allowlist the structure. Report values, notes, images, signatures, registry flags,
// custom subject information and unknown fields never enter the public payload.
function sanitizeTemplate(raw, name, metadata = {}) {
  if (!raw || !Array.isArray(raw.roots) || !raw.roots.length || Buffer.byteLength(JSON.stringify(raw)) > 250000) fail('invalid-argument', 'Choose a non-empty template below 250 KB.');
  let count = 0;
  const ids = new Set();
  function node(n, depth) {
    if (!n || depth > 8 || ++count > 200 || !['section', 'content'].includes(n.type)) fail('invalid-argument', 'Invalid template structure.');
    const id = identifier(n.id);
    if (ids.has(id)) fail('invalid-argument', 'Duplicate field identifiers.');
    ids.add(id);
    const indent = Number.isInteger(n.indent) ? Math.max(0, Math.min(6, n.indent)) : 0;
    if (n.type === 'content') return { type: 'content', id, text: '', indent };
    const options = n.options ?? [];
    if (!Array.isArray(options) || options.length > 50) fail('invalid-argument', 'Too many field options.');
    if (n.children != null && !Array.isArray(n.children)) fail('invalid-argument', 'Invalid children.');
    const style = n.style ?? {};
    return {
      type: 'section', id, title: string(n.title, 250), indent, collapsed: false,
      inputType: ['freeText', 'yesNo', 'singleSelect', 'multiSelect', 'numeric'].includes(n.inputType) ? n.inputType : 'freeText',
      options: options.map(o => string(o, 150, true)), unit: string(n.unit, 40),
      style: { level: ['h1','h2','h3','h4'].includes(style.level) ? style.level : 'h2', bold: style.bold !== false, align: ['left','center','right'].includes(style.align) ? style.align : 'left' },
      showInPdf: n.showInPdf !== false, addToRecords: false, addToLog: false,
      allowOptionalNote: n.allowOptionalNote === true,
      conditionalParentSectionId: string(n.conditionalParentSectionId, 100), conditionalEquals: string(n.conditionalEquals, 150),
      children: (n.children ?? []).map(child => node(child, depth + 1)),
    };
  }
  if (raw.roots.some(n => n.type !== 'section')) fail('invalid-argument', 'Top-level fields must be sections.');
  const template = { name, contributor: metadata.contributor ?? '', templateId: 'community', updatedAtIso: '2026-01-01T00:00:00.000Z', groupName: '', recordsConfigured: false, roots: raw.roots.map(n => node(n, 0)), signature: {} };
  const payload = JSON.stringify({ app: 'Ripot', ripotFileType: 'template', ripotExportVersion: 1, template, catalog: metadata });
  const sha256 = createHash('sha256').update(payload).digest('hex');
  return { template, payload, sha256, version: sha256.slice(0, 16) };
}
function createTemplateLibrary(db, clock = () => Date.now()) {
  async function isReviewer(uid) { return (await db.collection(C.reviewers).doc(uid).get()).data()?.enabled === true; }
  async function requireReviewer(request) {
    const uid = user(request);
    if (!await isReviewer(uid)) fail('permission-denied', 'Reviewer access is required.');
    return uid;
  }
  async function submit(request) {
    const uid = user(request), data = request.data ?? {};
    if (data.patientFree !== true || data.permissionToPublish !== true) fail('invalid-argument', 'Confirm that the template is patient-free and you have permission to publish it.');
    const name = string(data.name, 120, true), specialty = string(data.specialty, 80, true);
    const description = string(data.description, 1500, true), contributor = string(data.contributor, 120, true);
    const clean = sanitizeTemplate(data.template, name, { specialty, description, contributor });
    // Client-generated request id makes submission retries safe after lost responses.
    const requestId = identifier(data.requestId);
    const ref = data.id ? db.collection(C.submissions).doc(identifier(data.id)) : db.collection(C.submissions).doc(`s-${createHash('sha256').update(uid + ':' + requestId).digest('hex').slice(0, 32)}`);
    const limitRef = db.collection(C.limits).doc(uid);
    return db.runTransaction(async tx => {
      const existing = (await tx.get(ref)).data();
      if (existing && existing.ownerUid !== uid) fail('permission-denied', 'This submission belongs to another contributor.');
      if (existing?.requestId === requestId) return { id: ref.id, revision: existing.revision, status: existing.status };
      if (existing && (data.revision !== existing.revision || !['changes_requested','rejected','approved','withdrawn'].includes(existing.status))) fail('failed-precondition', 'Reload this submission before resubmitting.');
      const now = clock(), rate = (await tx.get(limitRef)).data();
      const recent = (rate?.times ?? []).filter(t => t > now - 86400000);
      if (recent.length >= 10) fail('resource-exhausted', 'You can submit up to ten templates or revisions per day.');
      const revision = (existing?.revision ?? 0) + 1;
      const record = { ownerUid: uid, name, specialty, description, contributor, ...clean, status: 'pending', revision, requestId, createdAt: existing?.createdAt ?? now, updatedAt: now, reviewerNote: '', patientFree: true, permissionToPublish: true };
      tx.set(ref, record);
      tx.set(limitRef, { times: [...recent, now] });
      tx.create(db.collection(C.mail).doc(`${ref.id}-${revision}`), { submissionId: ref.id, revision, createdAt: now, status: 'queued' });
      return { id: ref.id, revision, status: 'pending' };
    });
  }
  async function list(request) {
    const uid = user(request), review = request.data?.review === true;
    const reviewer = await isReviewer(uid);
    if (review && !reviewer) fail('permission-denied', 'Reviewer access is required.');
    // Single-field filtering + document-id pagination needs no composite index.
    let query = db.collection(C.submissions).where(review ? 'status' : 'ownerUid', '==', review ? 'pending' : uid).orderBy('__name__').limit(30);
    if (request.data?.cursor) query = query.startAfter(identifier(request.data.cursor));
    const [snap, pending] = await Promise.all([query.get(), reviewer ? db.collection(C.submissions).where('status','==','pending').count().get() : null]);
    const entries = snap.docs.map(doc => {
      const { payload, ownerUid, requestId, ...record } = doc.data();
      return { id: doc.id, ...record, isOwn: ownerUid === uid };
    });
    return { entries, reviewer, pendingCount: pending?.data().count ?? 0, cursor: snap.size === 30 ? snap.docs.at(-1).id : null };
  }
  async function review(request) {
    const uid = await requireReviewer(request), data = request.data ?? {};
    const ref = db.collection(C.submissions).doc(identifier(data.id));
    if (!['approved','changes_requested','rejected'].includes(data.decision)) fail('invalid-argument', 'Invalid review decision.');
    const note = string(data.note, 1500, data.decision !== 'approved');
    return db.runTransaction(async tx => {
      // Recheck permission within the transaction to protect concurrent revocation.
      const role = (await tx.get(db.collection(C.reviewers).doc(uid))).data();
      if (role?.enabled !== true) fail('permission-denied', 'Reviewer access is required.');
      const row = (await tx.get(ref)).data();
      if (!row) fail('not-found', 'Submission not found.');
      if (row.status !== 'pending' || row.revision !== data.revision) fail('failed-precondition', 'This submission has changed. Refresh before reviewing.');
      if (row.ownerUid === uid) fail('permission-denied', 'Another reviewer must review your own contribution.');
      if (data.decision === 'approved' && data.patientFreeReviewed !== true) fail('invalid-argument', 'Confirm the patient-free publication review before approval.');
      const now = clock(), slug = `community-${ref.id}`;
      const publicRef = db.collection(C.published).doc(slug);
      const versionRef = publicRef.collection('versions').doc(row.version);
      const previousVersion = data.decision === 'approved' ? await tx.get(versionRef) : null;
      tx.update(ref, { status: data.decision, reviewerNote: note, reviewedBy: uid, reviewedAt: now, updatedAt: now });
      tx.create(ref.collection('reviews').doc(String(row.revision)), { decision: data.decision, patientFreeReviewed: data.decision === 'approved', note, reviewerUid: uid, reviewedAt: now });
      // Queue the exact decision and feedback atomically; later revisions must
      // not change an email waiting for delivery. Recipient is resolved by Auth.
      tx.create(db.collection(C.mail).doc(`${ref.id}-${row.revision}-decision`), {
        kind: 'decision', ownerUid: row.ownerUid, submissionId: ref.id,
        revision: row.revision, name: row.name, decision: data.decision,
        note, createdAt: now, status: 'queued',
      });
      if (data.decision === 'approved') {
        const metadata = { slug, version: row.version, sha256: row.sha256, name: row.name, specialty: row.specialty, description: row.description, contributor: row.contributor, status: 'approved', publishedAt: now };
        tx.set(publicRef, metadata);
        if (!previousVersion.exists) tx.create(versionRef, { ...metadata, payload: row.payload });
      }
      return { status: data.decision, slug };
    });
  }
  async function withdraw(request) {
    const uid = user(request), data = request.data ?? {};
    const ref = db.collection(C.submissions).doc(identifier(data.id));
    return db.runTransaction(async tx => {
      const row = (await tx.get(ref)).data();
      if (!row) fail('not-found', 'Submission not found.');
      if (row.ownerUid !== uid) fail('permission-denied', 'Only the contributor can withdraw this submission.');
      if (row.revision !== data.revision) fail('failed-precondition', 'This submission has changed. Refresh before withdrawing.');
      // Safe to retry after a lost response, but never withdraw a newer revision.
      if (row.status === 'withdrawn') return { status: 'withdrawn' };
      if (row.status !== 'pending') fail('failed-precondition', 'Only pending submissions can be withdrawn.');
      const now = clock();
      tx.update(ref, { status: 'withdrawn', withdrawnAt: now, updatedAt: now });
      tx.create(ref.collection('withdrawals').doc(String(row.revision)), {
        revision: row.revision, withdrawnAt: now, ownerUid: uid,
      });
      // A pending update may have an older published version. Leave it intact.
      return { status: 'withdrawn' };
    });
  }
  async function publicList(cursor) {
    let query = db.collection(C.published).where('status','==','approved').orderBy('__name__').limit(100);
    if (cursor) query = query.startAfter(identifier(cursor));
    const snap = await query.get();
    return { schemaVersion: 1, templates: snap.docs.map(d => d.data()), cursor: snap.size === 100 ? snap.docs.at(-1).id : null };
  }
  async function publicDetail(slug, version) {
    identifier(slug);
    if (version && !/^[a-f0-9]{16}$/.test(version)) fail('invalid-argument', 'Invalid version.');
    const ref = db.collection(C.published).doc(slug), row = (await ref.get()).data();
    if (!row || row.status !== 'approved') fail('not-found', 'Template not found.');
    const published = (await ref.collection('versions').doc(version || row.version).get()).data();
    if (!published) fail('not-found', 'Version not found.');
    return { ...published, latestVersion: row.version };
  }
  return { submit, list, review, withdraw, publicList, publicDetail };
}
module.exports = { C, sanitizeTemplate, createTemplateLibrary };
