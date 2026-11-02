// Exercise the production renderer, button, allowance client and browser clipboard
// with a local-only fictional authorization service. Never contacts Firebase.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { chromium } = require('playwright');
const root = path.resolve('build/copy-preview');
const out = path.resolve('build/copy-browser-check');
fs.mkdirSync(out, { recursive: true });
const mime = { '.html': 'text/html', '.js': 'application/javascript', '.json': 'application/json',
  '.wasm': 'application/wasm', '.png': 'image/png', '.ttf': 'font/ttf' };
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
  try {
    const context = await browser.newContext({ viewport: { width: 1000, height: 700 },
      permissions: ['clipboard-read', 'clipboard-write'], serviceWorkers: 'block' });
    await context.route(/https:\/\/[^/]*(?:googleapis\.com|cloudfunctions\.net)\//, route => route.abort());
    await context.route('https://www.gstatic.com/flutter-canvaskit/**', async route => {
      const file = path.join(root, 'canvaskit', ...new URL(route.request().url()).pathname.split('/').slice(3));
      if (fs.existsSync(file)) await route.fulfill({ path: file, contentType: mime[path.extname(file)] || 'application/octet-stream' });
      else await route.continue();
    });
    page = await context.newPage();
    await page.goto(origin, { waitUntil: 'domcontentloaded' });
    const copy = page.getByRole('button', { name: 'Copy report', exact: true });
    await copy.waitFor({ timeout: 60000 });
    await copy.click();
    await page.getByText('49 free copies left', { exact: true }).waitFor();
    const clipboard = await page.evaluate(async () => {
      const [item] = await navigator.clipboard.read();
      return { types: item.types, text: await (await item.getType('text/plain')).text(),
        html: await (await item.getType('text/html')).text() };
    });
    assert(clipboard.types.includes('text/plain'));
    assert(clipboard.types.includes('text/html'));
    for (const value of ['Fictional Patient', 'TEST-001', 'First full paragraph.',
      'Second full paragraph.', 'Another line.', 'Measurement', '12.5 mm']) {
      assert(clipboard.text.includes(value), value);
      assert(clipboard.html.includes(value), value);
    }
    assert(!clipboard.text.includes('NOT FOR CLIPBOARD'));
    assert(!clipboard.html.includes('NOT FOR CLIPBOARD'));
    await copy.click();
    assert.equal(await page.getByText('49 free copies left', { exact: true }).count(), 1);
    await page.screenshot({ path: path.join(out, 'toolbar-desktop.png') });
    await page.getByRole('button', { name: 'About copying reports', exact: true }).click();
    await page.getByText('They do not renew.', { exact: false }).waitFor();
    await page.screenshot({ path: path.join(out, 'copy-info.png') });
    await page.getByRole('button', { name: 'Got it', exact: true }).click();
    await page.setViewportSize({ width: 360, height: 800 });
    await page.screenshot({ path: path.join(out, 'toolbar-phone.png') });
    // A separate rich editor receives the clipboard through an actual paste.
    await context.route(`${origin}/paste-target.html`, route => route.fulfill({
      contentType: 'text/html',
      body: '<html><body style="padding:24px;font-family:Arial"><h2>Paste check (fictional report)</h2><div id="editor" contenteditable="true" style="border:1px solid #bbb;padding:24px;min-height:400px"></div><textarea id="plain"></textarea></body></html>',
    }));
    const editor = await context.newPage();
    await editor.goto(`${origin}/paste-target.html`);
    await editor.locator('#editor').focus();
    await editor.keyboard.press('Control+V');
    await editor.waitForFunction(() => document.querySelector('#editor').innerText.includes('12.5 mm'));
    const pasted = await editor.locator('#editor').evaluate(el => ({
      text: el.innerText, tables: el.querySelectorAll('table').length,
      bold: [...el.querySelectorAll('span')].some(span => span.textContent === 'Findings:' && getComputedStyle(span).fontWeight === '700'),
    }));
    assert(pasted.tables >= 2, 'subject fields and aligned findings retain columns');
    assert(pasted.bold, 'heading remains bold after paste');
    assert(pasted.text.includes('Second full paragraph.\nAnother line.'));
    await editor.locator('#plain').focus();
    await editor.keyboard.press('Control+V');
    assert.equal(await editor.locator('#plain').inputValue(), clipboard.text);
    await editor.screenshot({ path: path.join(out, 'pasted-report.png') });
    fs.writeFileSync(path.join(out, 'result.json'), JSON.stringify({ result: 'passed',
      clipboardTypes: clipboard.types, richPasteTables: pasted.tables, boldHeading: pasted.bold,
      repeatedCopyRemaining: 49, plainPasteComplete: true }, null, 2));
    console.log('PASS: formatted and plain paste, complete content, private fields excluded, repeat count stable.');
  } catch (error) {
    if (page) await page.screenshot({ path: path.join(out, 'failure.png') }).catch(() => {});
    throw error;
  } finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }
})().catch(error => { console.error(error); process.exitCode = 1; });
