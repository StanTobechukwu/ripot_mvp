const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const crypto = require('node:crypto');
const {chromium} = require('playwright');
const root=path.resolve('landing/y'), out=path.resolve('build/browser-smoke');
fs.mkdirSync(out,{recursive:true});
const payload=JSON.stringify({app:'Ripot',ripotFileType:'template',ripotExportVersion:1,template:{name:'QA community structure',roots:[{type:'section',id:'root',title:'Finding <script>unsafe()</script>',inputType:'numeric',unit:'mm',children:[]}]}});
const hash=crypto.createHash('sha256').update(payload).digest('hex');
const row={slug:'community-s-test',version:hash.slice(0,16),sha256:hash,status:'approved',name:'QA community structure',specialty:'Endoscopy',description:'Fictional test only',contributor:'<img src=x onerror=unsafe()>'};
const server=http.createServer((req,res)=>{
  const pathname=new URL(req.url,'http://localhost').pathname;
  const file=path.resolve(root,'.'+(pathname.endsWith('/')?pathname+'index.html':pathname));
  if(!file.startsWith(root+path.sep)||!fs.existsSync(file)){res.writeHead(404).end();return;}
  res.setHeader('content-type',file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':file.endsWith('.png')?'image/png':'text/html');
  fs.createReadStream(file).pipe(res);
});
(async()=>{
  await new Promise(r=>server.listen(0,'127.0.0.1',r));
  const origin=`http://127.0.0.1:${server.address().port}`;
  const browser=await chromium.launch({channel:process.env.RIPOT_BROWSER_CHANNEL || 'chrome',headless:true,args:['--no-sandbox']});
  try{
    const page=await browser.newPage(), errors=[];page.on('pageerror',e=>errors.push(e.message));
    await page.route('https://us-central1-ripot-4edf7.cloudfunctions.net/publicTemplateLibrary**',route=>route.fulfill({status:200,contentType:'application/json',headers:{'access-control-allow-origin':'*'},body:JSON.stringify(new URL(route.request().url()).searchParams.has('template')?{...row,payload}:{schemaVersion:1,templates:[row]})}));
    for(const width of [390,1280]){
      await page.setViewportSize({width,height:900});
      await page.goto(origin+'/templates/');
      await page.getByRole('link',{name:'QA community structure',exact:true}).click();
      await page.getByRole('heading',{name:'QA community structure',exact:true}).waitFor();
      await page.getByText(row.contributor,{exact:false}).waitFor();
      assert.equal(await page.locator('#community-preview img, #community-preview script').count(),0);
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
      const link=await page.getByRole('link',{name:'Use in Ripot Web →'}).getAttribute('href');
      assert(link.includes(`version=${row.version}`));
      const [download]=await Promise.all([page.waitForEvent('download'),page.getByRole('link',{name:'Download Ripot template'}).click()]);
      assert.equal(fs.readFileSync(await download.path(),'utf8'),payload);
      await page.screenshot({path:path.join(out,`community-landing-${width}.png`),fullPage:true});
    }
    await page.route('https://us-central1-ripot-4edf7.cloudfunctions.net/publicTemplateLibrary**',route=>route.fulfill({status:503,body:'{}',headers:{'access-control-allow-origin':'*'}}));
    await page.goto(origin+'/templates/');
    await page.getByText(/Community templates are temporarily unavailable/).waitFor();
    assert.equal(await page.getByRole('link',{name:'Colonoscopy report template',exact:true}).count(),1);
    assert.deepEqual(errors,[]);
    console.log('PASS: community gallery, mobile/desktop preview, safe text rendering, versioned open link, verified download and unavailable-service fallback.');
  }finally{await browser.close();server.close();}
})().catch(e=>{console.error(e);server.close();process.exitCode=1;});
