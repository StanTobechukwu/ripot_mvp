// Exercise the real generated page, images, downloads and clipboard across widths.
const assert=require('node:assert/strict');
const fs=require('node:fs'), path=require('node:path'), http=require('node:http'), crypto=require('node:crypto');
const {chromium}=require('playwright');
const root=path.resolve('landing/y'), out=path.resolve('build/browser-smoke');
const manifest=JSON.parse(fs.readFileSync(path.join(root,'templates/previews/manifest.json')));
const slugs=[...new Set(Object.keys(manifest).map(k=>k.replace(/-(blank|example)$/,'')))];
const mime={'.html':'text/html','.js':'application/javascript','.css':'text/css','.jpg':'image/jpeg','.png':'image/png','.pdf':'application/pdf','.json':'application/json'};
fs.mkdirSync(out,{recursive:true});
const server=http.createServer((req,res)=>{
  const pathname=new URL(req.url,'http://localhost').pathname;
  const file=path.resolve(root,'.'+(pathname.endsWith('/')?pathname+'index.html':pathname));
  if(!file.startsWith(root+path.sep)||!fs.existsSync(file)){res.writeHead(404).end();return;}
  res.setHeader('content-type',mime[path.extname(file)]||'text/plain');fs.createReadStream(file).pipe(res);
});
(async()=>{
  await new Promise(r=>server.listen(0,'127.0.0.1',r));
  const origin=`http://127.0.0.1:${server.address().port}`;
  const browser=await chromium.launch({channel:process.env.RIPOT_BROWSER_CHANNEL||'chrome',headless:true,args:['--no-sandbox']});
  try{
    const page=await browser.newPage(), errors=[];page.on('pageerror',e=>errors.push(e.message));
    await page.route('https://**',route=>route.abort());
    await page.addInitScript(()=>{
      window.copied={};
      Object.defineProperty(navigator,'clipboard',{configurable:true,value:{
        write:async items=>{for(const type of items[0].types)window.copied[type]=await (await items[0].getType(type)).text();},
        writeText:async text=>{window.copied={'text/plain':text};},
      }});
    });
    for(const width of [320,390,1280]){
      await page.setViewportSize({width,height:900});
      await page.goto(origin);
      assert.equal(await page.locator('.template-highlights a').count(),2);
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`Homepage overflow at ${width}`);
      for(const link of await page.locator('.template-highlights a').all()) {
        assert((await link.boundingBox()).height < 130, `Template link wraps too narrowly at ${width}`);
      }
      assert.equal(await page.locator('meta[name="twitter:card"]').getAttribute('content'),'summary_large_image');
      await page.locator('.template-highlights').scrollIntoViewIfNeeded();
      await page.screenshot({path:path.join(out,`home-templates-${width}.png`)});
      await page.locator('#backup').scrollIntoViewIfNeeded();
      await page.screenshot({path:path.join(out,`home-backup-${width}.png`)});
      await page.locator('#plans').scrollIntoViewIfNeeded();
      await page.screenshot({path:path.join(out,`home-plans-${width}.png`)});
      await page.goto(`${origin}/templates/`);
      assert.equal(await page.locator('section[id^="specialty-"] .card').count(),15);
      assert.deepEqual(await page.locator('section[id^="specialty-"] > h2').allTextContents(),['Endoscopy','Ultrasound','Cardiology','Operation notes']);
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`Library overflow at ${width}`);
      for(const slug of slugs){
        await page.goto(`${origin}/templates/${slug}/`);
        const img=page.locator('[data-page-image]');
        await img.evaluate(i=>i.decode());
        assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`${slug}: overflow at ${width}`);
        assert.equal(await page.locator('[data-variant="blank"]').getAttribute('aria-pressed'),'true');
        for(const variant of ['blank','example']){
          await page.locator(`[data-variant="${variant}"]`).click();
          const expected=manifest[`${slug}-${variant}`];
          for(let index=0;index<expected.pages.length;index++){
            await img.evaluate(i=>i.decode());
            assert((await img.getAttribute('src')).endsWith(expected.pages[index]));
            assert.equal(await page.locator('[data-page-count]').textContent(),`Page ${index+1} of ${expected.pages.length}`);
            if(index+1<expected.pages.length)await page.locator('[data-next]').click();
          }
          assert.equal(await page.locator('[data-next]').isDisabled(),true);
          if(expected.pages.length>1){await page.locator('[data-previous]').click();assert((await img.getAttribute('src')).endsWith(expected.pages[expected.pages.length-2]));}
          const [download]=await Promise.all([page.waitForEvent('download'),page.locator('#download-pdf').click()]);
          const bytes=fs.readFileSync(await download.path());
          assert.equal(bytes.subarray(0,5).toString(),'%PDF-');
          assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),expected.sha256);
        }
        await page.locator('[data-enlarge]').click();
        assert.equal(await page.locator('#report-zoom').evaluate(d=>d.open),true);
        await page.locator('[data-zoom-toggle]').click();
        assert.equal(await page.locator('.zoom-body').evaluate(d=>d.scrollWidth>d.clientWidth),true);
        await page.keyboard.press('Escape');
        assert.equal(await page.locator('#report-zoom').evaluate(d=>d.open),false);
        await page.locator('[data-copy="outline"]').click();
        await page.waitForFunction(()=>window.copied['text/html']);
        let copy=await page.evaluate(()=>window.copied);
        assert(!copy['text/plain'].includes('[enter]'));
        assert(!copy['text/plain'].includes('FICTIONAL PATIENT'));
        assert(copy['text/plain'].includes('Patient: ________________'));
        assert(copy['text/html'].includes('<strong>'));
        await page.locator('[data-copy="example"]').click();
        await page.waitForFunction(()=>window.copied['text/plain'].includes('FICTIONAL EXAMPLE'));
        await page.evaluate(()=>navigator.clipboard.write=async()=>{throw Error('Rich clipboard unsupported');});
        await page.locator('[data-copy="outline"]').click();
        await page.waitForFunction(()=>!window.copied['text/plain'].includes('FICTIONAL EXAMPLE'));
        assert.equal(await page.getByRole('link',{name:'Download Ripot import file'}).count(),0);
        await page.getByText('Import this template into Ripot',{exact:true}).click();
        const [importFile]=await Promise.all([page.waitForEvent('download'),page.getByRole('link',{name:'Download Ripot import file'}).click()]);
        assert.equal(fs.readFileSync(await importFile.path(),'utf8'),fs.readFileSync(path.join(root,'templates/downloads',`${slug}.ripottemplate.json`),'utf8'));
        await page.getByText('Import this template into Ripot',{exact:true}).click();
        await page.locator('[data-variant="blank"]').click();
        await page.evaluate(()=>scrollTo(0,0));
        if(width===390||slug.startsWith('upper-gi')||slug.startsWith('echocardiogram'))await page.screenshot({path:path.join(out,`${slug}-${width}.png`),fullPage:true});
      }
    }
    assert.deepEqual(errors,[]);
    console.log('PASS: all real report previews at 320/390/1280px; blank/example PDFs match hashes; multipage navigation, zoom, rich/plain clipboard and unchanged import downloads.');
  }finally{await browser.close();server.close();}
})().catch(e=>{console.error(e);server.close();process.exitCode=1;});
