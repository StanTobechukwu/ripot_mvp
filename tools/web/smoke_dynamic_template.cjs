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
  { slug, version, sha256: sha, status: 'approved', url: payloadPath },
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
    await page.getByText('Remote-only observation', { exact: true }).waitFor({ timeout: 60000 });
    assert(fetched.includes(payloadPath), 'App never fetched the unknown template payload');
    await page.getByText('Remote-only measurement', { exact: true }).waitFor();
    const numeric = page.getByRole('textbox', { name: /Enter number/ });
    await numeric.fill('12.5');
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
    fs.writeFileSync(path.join(out, 'result.json'), JSON.stringify({
      passed: true, slug, version, fetched, sourceCommit: process.env.GITHUB_SHA,
    }, null, 2));
  } catch (error) {
    if (page) {
      await page.screenshot({ path: path.join(out, 'failure.png'), fullPage: true }).catch(() => {});
      fs.writeFileSync(path.join(out, 'failure-dom.html'), await page.content());
    }
    throw error;
  } finally { await browser.close(); server.close(); }
})().catch(error => { console.error(error); server.close(); process.exitCode = 1; });
