const { test, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { createTemplateLibrary, C, sanitizeTemplate } = require('../template-library');
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.GCLOUD_PROJECT?.startsWith('demo-')) throw Error('Use a demo Firestore emulator: these tests erase data.');
const app = initializeApp(), db = getFirestore(app), service = createTemplateLibrary(db);
const structure = { roots: [{type:'section',id:'root',title:'Findings',addToRecords:true,addToLog:true, options:['Option'], children:[{type:'content',id:'value',text:'PRIVATE PATIENT VALUE'}]}], signature:{name:'PRIVATE SIGNATURE'}, subjectInfo:{heading:'PRIVATE SUBJECT'}, patientName:'PRIVATE PATIENT' };
const req = (uid = 'author', data = {}) => ({auth:{uid,token:{firebase:{sign_in_provider:'password'}}},data});
const submission = (overrides={}) => req('author', {requestId:'one', name:'Test template',specialty:'Endoscopy',description:'A reporting structure',contributor:'Public author',patientFree:true,permissionToPublish:true,template:structure,...overrides});
const approve = (id, revision=1, overrides={}) => service.review(req('reviewer',{id,revision,decision:'approved',patientFreeReviewed:true,...overrides}));
beforeEach(async () => {
  const r = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`,{method:'DELETE'}); assert.equal(r.ok,true);
  await db.collection(C.reviewers).doc('reviewer').set({enabled:true});
});
after(() => deleteApp(app));
test('structure allowlist strips sensitive data and rejects oversized, duplicate and deeply nested fields', () => {
  const clean = sanitizeTemplate(structure,'Test');
  assert.equal(clean.payload.includes('PRIVATE'),false);
  assert.equal(clean.template.roots[0].addToRecords,false);
  assert.equal(clean.template.roots[0].children[0].text,'');
  assert.throws(()=>sanitizeTemplate({roots:[structure.roots[0], structure.roots[0]]},'Test'), {code:'invalid-argument'});
  assert.throws(()=>sanitizeTemplate({roots:[{...structure.roots[0],options:Array(51).fill('x')}]},'Test'), {code:'invalid-argument'});
  let n={type:'section',id:'n0',title:'X'}; for(let i=1;i<11;i++) n={type:'section',id:`n${i}`,children:[n]};
  assert.throws(()=>sanitizeTemplate({roots:[n]},'Test'),{code:'invalid-argument'});
});
test('authentication, owner privacy and reviewer authorization cannot be forged by payload',async()=>{
  await assert.rejects(service.submit({data:submission().data}),{code:'unauthenticated'});
  await assert.rejects(service.submit({...submission(),auth:{uid:'anon',token:{firebase:{sign_in_provider:'anonymous'}}}}),{code:'unauthenticated'});
  const {id}=await service.submit(submission());
  assert.deepEqual((await service.list(req('other'))).entries,[]);
  await assert.rejects(service.list(req('author',{review:true,reviewer:true})),{code:'permission-denied'});
  await assert.rejects(service.review(req('author',{id,revision:1,decision:'approved',reviewer:true})),{code:'permission-denied'});
  await db.collection(C.reviewers).doc('author').set({enabled:true});
  await assert.rejects(service.review(req('author',{id,revision:1,decision:'approved'})),{code:'permission-denied'});
  await assert.rejects(service.submit(req('other',{...submission().data,id,revision:1,requestId:'steal'})),{code:'permission-denied'});
});
test('pending stays private, concurrent retries create one notification, approval publishes immutable verified bytes',async()=>{
  const results=await Promise.all([service.submit(submission()),service.submit(submission())]);
  assert.equal(results[0].id,results[1].id); const id=results[0].id;
  assert.equal((await db.collection(C.mail).get()).size,1);
  assert.deepEqual((await service.publicList()).templates,[]);
  await assert.rejects(service.publicDetail(`community-${id}`),{code:'not-found'});
  assert.equal((await service.list(req('reviewer',{review:true}))).pendingCount,1);
  await approve(id);
  const rows=(await service.publicList()).templates;
  assert.equal(rows.length,1); assert.equal(rows[0].ownerUid,undefined); assert.equal(rows[0].reviewerNote,undefined);
  const detail=await service.publicDetail(`community-${id}`,rows[0].version);
  assert.equal(require('node:crypto').createHash('sha256').update(detail.payload).digest('hex'),detail.sha256);
  await assert.rejects(approve(id),{code:'failed-precondition'});
  const revision=await service.submit(submission({id,revision:1,requestId:'two',template:{roots:[{type:'section',id:'new',title:'Updated'}]}}));
  assert.equal(revision.revision,2);
  assert.equal((await service.publicDetail(`community-${id}`)).version,detail.version);
  await assert.rejects(approve(id,1),{code:'failed-precondition'});
  await approve(id,2);
  assert.notEqual((await service.publicDetail(`community-${id}`)).version,detail.version);
  assert.equal((await service.publicDetail(`community-${id}`,detail.version)).payload,detail.payload);
  assert.equal((await db.collection(C.mail).get()).size,2);
});
test('review feedback, revision concurrency and daily limits',async()=>{
  const {id}=await service.submit(submission());
  await assert.rejects(approve(id,1,{decision:'changes_requested'}),{code:'invalid-argument'});
  await approve(id,1,{decision:'changes_requested',note:'Clarify the units'});
  assert.equal((await service.list(req('author'))).entries[0].reviewerNote,'Clarify the units');
  await assert.rejects(service.submit(submission({id,revision:0,requestId:'bad'})),{code:'failed-precondition'});
  await service.submit(submission({id,revision:1,requestId:'fixed'}));
  for(let i=0;i<8;i++) await service.submit(submission({requestId:`new-${i}`}));
  await assert.rejects(service.submit(submission({requestId:'over-limit'})),{code:'resource-exhausted'});
});
test('revoked reviewers lose access and withdrawn publications are unavailable including old versions',async()=>{
  const {id}=await service.submit(submission()); await approve(id);
  const row=(await service.publicList()).templates[0];
  await db.collection(C.published).doc(row.slug).update({status:'withdrawn'});
  assert.equal((await service.publicList()).templates.length,0);
  await assert.rejects(service.publicDetail(row.slug,row.version),{code:'not-found'});
  await db.collection(C.reviewers).doc('reviewer').update({enabled:false});
  await assert.rejects(service.list(req('reviewer',{review:true})),{code:'permission-denied'});
});

test('metadata-only attribution edits produce a distinct immutable published version',async()=>{
  const {id}=await service.submit(submission()); await approve(id);
  const first=(await service.publicList()).templates[0];
  await service.submit(submission({id,revision:1,requestId:'credit-correction',contributor:'Corrected public credit'}));
  await approve(id,2);
  const latest=await service.publicDetail(first.slug);
  assert.notEqual(latest.version,first.version);
  assert.equal(latest.contributor,'Corrected public credit');
  assert.equal((await service.publicDetail(first.slug,first.version)).contributor,'Public author');
});

test('approval requires an explicit patient-free reviewer attestation',async()=>{const {id}=await service.submit(submission());await assert.rejects(approve(id,1,{patientFreeReviewed:false}),{code:'invalid-argument'});assert.deepEqual((await service.publicList()).templates,[]);});

test('rejection leaves pending queue, preserves author feedback and publishes nothing', async () => {
  const {id} = await service.submit(submission());
  await service.review(req('reviewer', {id, revision: 1, decision: 'rejected', note: 'Please clarify the labels.'}));
  const queue = await service.list(req('reviewer', {review: true}));
  assert.equal(queue.pendingCount, 0);
  assert.deepEqual(queue.entries, []);
  const mine = (await service.list(req('author'))).entries[0];
  assert.equal(mine.status, 'rejected');
  assert.equal(mine.reviewerNote, 'Please clarify the labels.');
  assert.deepEqual((await service.publicList()).templates, []);
  await assert.rejects(service.review(req('reviewer', {id, revision: 1, decision: 'rejected', note: 'Again'})), {code: 'failed-precondition'});
});
