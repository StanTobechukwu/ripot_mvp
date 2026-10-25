const {test} = require('node:test');
const assert = require('node:assert/strict');
const {deliverTemplateNotification} = require('../template-notification');
function queue() {
  const row={status:'queued',submissionId:'s-example',revision:1,to:'attacker@example.invalid',payload:'PRIVATE DATA'};
  return {row,ref:{get:async()=>({data:()=>row}),update:async change=>Object.assign(row,change)}};
}
test('notification uses a fixed recipient and review link, excludes submission contents and skips completed delivery',async()=>{
  const {row,ref}=queue(), messages=[];
  const send=async m=>messages.push(m);
  await deliverTemplateNotification(ref,'s-example-1',send,'support@ripot.app');
  assert.equal(row.status,'sent');assert.equal(messages.length,1);
  assert.equal(messages[0].to,'support@ripot.app');
  assert.equal(messages[0].text.includes('PRIVATE DATA'),false);
  assert.equal(messages[0].text.includes('?templateLibrary=review'),true);
  await deliverTemplateNotification(ref,'s-example-1',send,'support@ripot.app');
  assert.equal(messages.length,1);
});
test('failed SMTP delivery remains retryable and does not leak provider secrets',async()=>{
  const {row,ref}=queue();
  await assert.rejects(deliverTemplateNotification(ref,'s-example-1',async()=>{throw Error('private SMTP password');},'support@ripot.app'),/delivery failed/);
  assert.equal(row.status,'retrying');assert.equal(row.lastError.includes('password'),false);
  await deliverTemplateNotification(ref,'s-example-1',async()=>{},'support@ripot.app');
  assert.equal(row.status,'sent');assert.equal(row.lastError,null);
});
