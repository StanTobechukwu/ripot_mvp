#!/usr/bin/env node
// Operator-only: application-default credentials, never shipped in the app.
const {initializeApp, applicationDefault} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {getFirestore} = require('firebase-admin/firestore');
const [project, email, action] = process.argv.slice(2);
if (project !== 'ripot-4edf7' || !email || !['grant','revoke','check'].includes(action)) {
  console.error('Usage: node functions/scripts/template-reviewer.js ripot-4edf7 <registered-email> check|grant|revoke');
  process.exit(1);
}
initializeApp({credential:applicationDefault(),projectId:project});
(async()=>{
  const account=await getAuth().getUserByEmail(email);
  if(account.disabled) throw Error('This account is disabled.');
  const ref=getFirestore().collection('ripot_template_reviewers').doc(account.uid);
  if(action!=='check') await ref.set({enabled:action==='grant',updatedAt:Date.now()});
  console.log(JSON.stringify({email:account.email,uid:account.uid,enabled:(await ref.get()).data()?.enabled===true}));
})().catch(error=>{console.error(error.message);process.exitCode=1;});
