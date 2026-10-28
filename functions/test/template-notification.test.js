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

test('decision emails resolve the contributor in Auth and include decision, reason and My submissions link', async () => {
  for (const decision of ['approved', 'rejected', 'changes_requested']) {
    const {row, ref} = queue(), messages = [], lookups = [];
    Object.assign(row, {kind: 'decision', ownerUid: 'author', name: 'Sample structure', decision, note: 'Clarify the units.'});
    const getUser = async uid => { lookups.push(uid); return {email: 'contributor@example.invalid'}; };
    await deliverTemplateNotification(ref, `example-1-${decision}`, async m => messages.push(m), 'support@ripot.app', getUser);
    assert.deepEqual(lookups, ['author']);
    assert.deepEqual(messages[0].to, {address: 'contributor@example.invalid'});
    assert.equal(messages[0].text.includes('Clarify the units.'), true);
    assert.equal(messages[0].text.includes('Sample structure'), true);
    assert.equal(messages[0].text.includes('?templateLibrary=mine'), true);
    assert.equal(messages[0].text.includes('PRIVATE DATA'), false);
    assert.equal(messages[0].subject.includes(decision.replace('_', ' ')), true);
    await deliverTemplateNotification(ref, 'same', async m => messages.push(m), 'support@ripot.app', getUser);
    assert.equal(messages.length, 1);
  }
});

test('decision retries resolve the account again and retain the feedback', async () => {
  const {row, ref} = queue();
  Object.assign(row, {kind: 'decision', ownerUid: 'author', name: 'Test', decision: 'rejected', note: 'Add units.'});
  await assert.rejects(deliverTemplateNotification(ref, 'decision', async () => {}, 'support@ripot.app', async () => { throw Error('temporary Auth outage'); }));
  assert.equal(row.status, 'retrying');
  await assert.rejects(deliverTemplateNotification(ref, 'decision', async () => { throw Error('SMTP failure'); }, 'support@ripot.app', async () => ({email: 'author@example.invalid'})));
  assert.equal(row.status, 'retrying');
  let sent;
  await deliverTemplateNotification(ref, 'decision', async m => { sent = m; }, 'support@ripot.app', async () => ({email: 'author@example.invalid'}));
  assert.equal(row.status, 'sent');
  assert.equal(sent.text.includes('Add units.'), true);
});

test('deleted, disabled and email-less contributors skip delivery without mailing support or retrying forever', async () => {
  for (const account of [null, {}, {email: 'author@example.invalid', disabled: true}]) {
    const {row, ref} = queue();
    Object.assign(row, {kind: 'decision', ownerUid: 'author', decision: 'approved'});
    const lookup = async () => {
      if (account === null) throw Object.assign(Error('gone'), {code: 'auth/user-not-found'});
      return account;
    };
    await deliverTemplateNotification(ref, 'decision', async () => assert.fail('Do not send'), 'support@ripot.app', lookup);
    assert.equal(row.status, 'skipped');
    await deliverTemplateNotification(ref, 'decision', async () => assert.fail('Do not send'), 'support@ripot.app', async () => assert.fail('Do not retry'));
  }
});
