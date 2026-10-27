#!/usr/bin/env node
'use strict';
// Read-only verification: unauthenticated callable requests cannot write data.
const origin = 'https://us-central1-ripot-4edf7.cloudfunctions.net/';
async function checkTemplateServices(fetcher = fetch) {
  const checks = [
    ['publicTemplateLibrary?health=1', 'GET', body => body.schemaVersion === 1 && body.contributions === 'ready'],
    ['publicTemplateLibrary', 'GET', body => body.schemaVersion === 1 && Array.isArray(body.templates)],
    ...['submitTemplateContribution','listTemplateContributions','reviewTemplateContribution','withdrawTemplateContribution'].map(name =>
      [name, 'POST', body => body.error?.status === 'UNAUTHENTICATED']),
  ];
  const results = [];
  for (const [name, method, validate] of checks) {
    try {
      const response = await fetcher(origin + name, {method, redirect:'error', signal:AbortSignal.timeout(20000),
        ...(method === 'POST' ? {headers:{'Content-Type':'application/json'},body:'{"data":{}}'} : {})});
      let body; try { body = await response.json(); } catch (_) { body = {}; }
      const ok = (method === 'POST' ? response.status === 401 : response.status === 200) && validate(body);
      results.push({name,ok,status:response.status,detail:ok ? (method==='POST' ? 'deployed; authentication required' : 'responding') : response.status===404 ? 'not found; deploy the template services to ripot-4edf7 / us-central1' : 'unexpected response; inspect Firebase function logs'});
    } catch (_) { results.push({name,ok:false,detail:'request failed; check connection and service availability'}); }
  }
  return results;
}
if (require.main === module) checkTemplateServices().then(results => {
  for (const r of results) console.log(`${r.ok?'PASS':'FAIL'} ${r.name}: ${r.detail}${r.status ? ` (HTTP ${r.status})` : ''}`);
  if (results.some(r=>!r.ok)) process.exitCode=1;
  else console.log('Core endpoints verified. Still test a signed-in submission, independent review, download/import and email delivery.');
});
module.exports = {checkTemplateServices};
