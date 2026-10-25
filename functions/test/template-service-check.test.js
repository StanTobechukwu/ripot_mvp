'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {checkTemplateServices}=require('../scripts/check-template-services');
test('deployment checker is unauthenticated and diagnoses missing routes',async()=>{
 let calls=0;
 const results=await checkTemplateServices(async(url,options)=>{
  calls++; assert(url.startsWith('https://us-central1-ripot-4edf7.cloudfunctions.net/'));
  assert.equal(options.headers?.Authorization,undefined);
  if(options.method==='POST')assert.equal(options.body,'{"data":{}}');
  return {status:404,json:async()=>{throw Error('HTML');}};
 });
 assert.equal(calls,5);assert(results.every(r=>!r.ok&&r.detail.includes('not found')));
});
test('healthy endpoints must enforce authentication and return expected schemas',async()=>{
 const results=await checkTemplateServices(async(url,options)=>({status:options.method==='POST'?401:200,
  json:async()=>options.method==='POST'?{error:{status:'UNAUTHENTICATED'}}:url.includes('health=1')?{schemaVersion:1,contributions:'ready'}:{schemaVersion:1,templates:[]}}));
 assert(results.every(r=>r.ok));
 const insecure=await checkTemplateServices(async()=>({status:200,json:async()=>({result:{}})}));
 assert(insecure.every(r=>!r.ok));
});
