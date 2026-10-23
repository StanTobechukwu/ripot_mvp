// Run against the compiled app with a catalogue-only template. No deployment.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const crypto = require('node:crypto');
const { chromium } = require('playwright');

const root = path.resolve('build/web');
const out = path.resolve('build/browser-smoke');
fs.mkdirSync(out, { recursive: true });
const slug = 'qa-remote-only-template';
const payload = Buffer.from(JSON.stringify({
  app: 'Ripot', ripotFileType: 'template', ripotExportVersion: 1,
  template: {
    name: 'Fictional remote-only QA template',
    roots: [
      { type: 'section', id: 'remote-observation', title: 'Remote-only observation',
        inputType: 'freeText', children: [] },
      { type: 'section', id: 'remote-measurement', title: 'Remote-only measurement',
        inputType: 'numeric', unit: 'mm', children: [] },
    ],
    subjectInfo: { enabled: false, columns: 1, schemaVersion: 1, fields: [] },
  },
}));
const sha = crypto.createHash('sha256').update(payload).digest('hex');
const version = sha.slice(0, 16);
const payloadPath = `/templates/catalog/${slug}/${version}.ripottemplate.json`;
const manifest = { schemaVersion: 1, templates: [
  { slug, version, sha256: sha, status: 'approved', url: payloadPath, name: 'Fictional remote-only QA template', specialty: 'Test specialty', contributor: 'QA Author' },
] };
const mime = { '.html': 'text/html', '.js': 'application/javascript',
  '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png',
  '.ttf': 'font/ttf', '.woff2': 'font/woff2' };
const server = http.createServer((req, res) => {
  const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  const file = path.resolve(root, '.' + (pathname === '/' ? '/index.html' : pathname));
  if (!file.startsWith(root + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
    res.writeHead(404); res.end(); return;
  }
  res.writeHead(200, { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});

(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({ channel: 'chrome', headless: true,
    args: ['--no-sandbox', '--enable-unsafe-swiftshader'] });
  let page;
  const fetched = [];
  try {
    const context = await browser.newContext({ viewport: { width: 1365, height: 1200 },
      serviceWorkers: 'block' });
    await context.addInitScript(() => {
      localStorage.setItem('flutter.account.welcomeCompleted.v1', 'true');
    });
    // Test only local reporting: do not contact account or data services.
    await context.route(/https:\/\/[^/]*(?:googleapis\.com|cloudfunctions\.net)\//,
      route => route.abort());
    await context.route('https://ripot.app/templates/catalog/**', async route => {
      const p = new URL(route.request().url()).pathname;
      fetched.push(p);
      const headers = { 'access-control-allow-origin': origin,
        'content-type': 'application/json' };
      if (p.endsWith('/manifest.json')) {
        await route.fulfill({ status: 200, headers, body: JSON.stringify(manifest) });
      } else if (p === payloadPath) {
        await route.fulfill({ status: 200, headers, body: payload });
      } else { await route.fulfill({ status: 404, headers, body: '{}' }); }
    });
    // Prefer the exact CanvasKit bundled by this Flutter build.
    await context.route('https://www.gstatic.com/flutter-canvaskit/**', async route => {
      const url = new URL(route.request().url());
      const parts = url.pathname.split('/');
      const file = path.join(root, 'canvaskit', ...parts.slice(3));
      if (fs.existsSync(file)) await route.fulfill({ path: file,
        contentType: mime[path.extname(file)] || 'application/octet-stream' });
      else await route.continue();
    });
    page = await context.newPage();
    page.on('console', msg => { if (msg.type() === 'error') console.log('Browser:', msg.text()); });
    await page.goto(`${origin}/?template=${slug}&version=${version}`, { waitUntil: 'domcontentloaded' });
    await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60000 });
    // Flutter exposes its accessible DOM only after accessibility is enabled.
    const accessibility = page.locator('flt-semantics-placeholder');
    await accessibility.waitFor({ state: 'attached', timeout: 30000 });
    await accessibility.evaluate(element => element.click());
    const form = page.getByRole('group', {
      name: 'Form\nRemote-only observation\nRemote-only measurement', exact: true,
    });
    await form.waitFor({ state: 'attached', timeout: 60000 });
    assert(fetched.includes(payloadPath), 'App never fetched the unknown template payload');
    const numeric = page.getByRole('textbox', { name: /Enter number/ });
    // Flutter activates its editing bridge on focus. Send keyboard events after
    // clicking, rather than replacing the accessibility input value directly.
    await numeric.click();
    await page.keyboard.type('12.5', { delay: 100 });
    assert.equal(await numeric.inputValue(), '12.5');
    await page.keyboard.press('Tab');
    await page.getByRole('button', { name: 'Save progress', exact: true }).click();
    await page.waitForFunction(() => Object.keys(localStorage).some(key =>
      key.startsWith('flutter.reports.doc.') && localStorage.getItem(key).includes('12.5')));
    const saved = await page.evaluate(() => Object.keys(localStorage)
      .filter(k => k.startsWith('flutter.reports.doc.'))
      .map(k => JSON.parse(JSON.parse(localStorage.getItem(k)))));
    assert.equal(saved.length, 1);
    assert.equal(saved[0].sourceTemplateId, `public_${slug}_${version}`);
    assert.equal(saved[0].roots[1].inputType, 'numeric');
    assert.equal(saved[0].roots[1].unit, 'mm');
    await page.screenshot({ path: path.join(out, 'remote-template-desktop.png'), fullPage: true });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.screenshot({ path: path.join(out, 'remote-template-mobile.png'), fullPage: true });
    console.log('PASS: compiled Ripot Web fetched a non-built-in template, rendered its fields, accepted a numeric value, and saved a local report with the remote template identity.');
    await page.getByRole('button', { name: 'Preview', exact: true }).click();
    const letterheadPrompt = page.getByRole('button', {
      name: 'Add your hospital / clinic logo & letterhead · Premium', exact: true,
    });
    await letterheadPrompt.waitFor({ state: 'visible' });
    await page.screenshot({ path: path.join(out, 'letterhead-prompt-mobile.png'), fullPage: true });
    await page.setViewportSize({ width: 1365, height: 1200 });
    await letterheadPrompt.waitFor({ state: 'visible' });
    await page.screenshot({ path: path.join(out, 'letterhead-prompt-desktop.png'), fullPage: true });
    await letterheadPrompt.click();
    await page.getByText('Use your own letterhead', { exact: true }).waitFor({ state: 'visible' });
    console.log('PASS: Free preview shows the letterhead invitation on mobile and desktop and opens the existing Premium sheet.');
    // Browse/add a reviewed community template and confirm the personal copy
    // persists while the network is offline. All service responses are fixtures.
    const communitySlug = 'community-s-browser-test';
    const community = { slug: communitySlug, version, sha256: sha, status: 'approved',
      name: 'Fictional remote-only QA template', specialty: 'Community QA',
      contributor: 'QA Contributor', description: 'Fictional browser test structure' };
    await context.route('https://us-central1-ripot-4edf7.cloudfunctions.net/publicTemplateLibrary**', async route => {
      const query = new URL(route.request().url()).searchParams;
      await route.fulfill({ status: 200, headers: { 'access-control-allow-origin': origin,
        'content-type': 'application/json' }, body: JSON.stringify(query.has('template')
          ? {...community, payload: payload.toString()} : {schemaVersion: 1, templates: [community]}) });
    });
    await page.goto(`${origin}/?templateLibrary=browse`, {waitUntil: 'domcontentloaded'});
    await page.locator('flt-semantics-placeholder').waitFor({state:'attached',timeout:30000});
    await page.locator('flt-semantics-placeholder').evaluate(element => element.click());
    await page.getByText('Community QA · By QA Contributor', {exact:false}).waitFor({timeout:60000});
    await page.getByText('Community QA · By QA Contributor', {exact:false}).click();
    await page.getByRole('button',{name:'Add to my templates',exact:true}).click();
    await page.waitForFunction(slug => Object.keys(localStorage).some(k => k.startsWith('flutter.templates.doc.') && localStorage.getItem(k).includes(slug)),communitySlug);
    await page.getByText('Community QA · By QA Contributor', {exact:false}).click();
    assert(await page.getByRole('button',{name:'Already added',exact:true}).isDisabled());
    await page.screenshot({path:path.join(out,'community-template-preview.png'),fullPage:true});
    await page.getByRole('button',{name:'Close',exact:true}).click();
    // Fulfilled Playwright routes bypass offline networking, so fail catalogue
    // requests explicitly as well as disabling the connection.
    await context.route('https://ripot.app/templates/catalog/**', route => route.abort('internetdisconnected'));
    await context.route('https://us-central1-ripot-4edf7.cloudfunctions.net/publicTemplateLibrary**', route => route.abort('internetdisconnected'));
    await context.setOffline(true);
    await page.getByRole('button',{name:'Refresh library',exact:true}).click();
    await page.getByText(/Saved templates still work offline/).waitFor({timeout:30000});
    const personal = await page.evaluate(slug => Object.keys(localStorage)
      .filter(k=>k.startsWith('flutter.templates.doc.') && localStorage.getItem(k).includes(slug))
      .map(k=>JSON.parse(JSON.parse(localStorage.getItem(k)))),communitySlug);
    assert.equal(personal.length,1);
    assert.equal(personal[0].sourceSlug,communitySlug);
    assert.equal(personal[0].sourceVersion,version);
    assert.equal(personal[0].contributor,'QA Contributor');
    console.log('PASS: online library preview, attributed personal copy, duplicate prevention and offline persistence.');
    fs.writeFileSync(path.join(out, 'result.json'), JSON.stringify({
      passed: true, letterheadPromptPassed: true, communityLibraryPassed: true, slug, version, fetched, sourceCommit: process.env.GITHUB_SHA,
    }, null, 2));
  } catch (error) {
    if (page) {
      const diagnostics = await page.evaluate(() => ({
        reports: Object.fromEntries(Object.keys(localStorage)
          .filter(key => key.includes('reports.doc.'))
          .map(key => [key, localStorage.getItem(key)])),
        fields: [...document.querySelectorAll('input[data-semantics-role="text-field"]')]
          .map(input => ({ label: input.getAttribute('aria-label'), value: input.value })),
      }));
      fs.writeFileSync(path.join(out, 'failure-state.json'), JSON.stringify(diagnostics, null, 2));
      await page.screenshot({ path: path.join(out, 'failure.png'), fullPage: true }).catch(() => {});
      fs.writeFileSync(path.join(out, 'failure-dom.html'), await page.content());
    }
    throw error;
  } finally { await browser.close(); server.close(); }
})().catch(error => { console.error(error); server.close(); process.exitCode = 1; });
