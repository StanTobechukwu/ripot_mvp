// Exercise the compiled landing-to-Premium link without accounts, payments or deployment.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const {chromium} = require('playwright');
const root = path.resolve('build/web'), out = path.resolve('build/browser-smoke');
fs.mkdirSync(out,{recursive:true});
const mime = {'.html':'text/html','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.ttf':'font/ttf','.png':'image/png'};
const server = http.createServer((req,res)=>{
  const pathname = new URL(req.url,'http://localhost').pathname;
  const file = path.resolve(root,'.'+(pathname==='/'?'/index.html':pathname));
  if(!file.startsWith(root+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404);res.end();return;}
  res.writeHead(200,{'Content-Type':mime[path.extname(file)]||'application/octet-stream'});
  fs.createReadStream(file).pipe(res);
});
(async()=>{
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const browser = await chromium.launch({channel:'chrome',headless:true,args:['--no-sandbox','--enable-unsafe-swiftshader']});
  let page;
  try{
    for(const width of [390,1365]){
      const context = await browser.newContext({viewport:{width,height:1000},serviceWorkers:'block'});
      await context.addInitScript(()=>{
        localStorage.setItem('flutter.account.welcomeCompleted.v1','true');
        localStorage.setItem('ripot.qa.local-data','preserve-me');
      });
      await context.route(/https:\/\/[^/]*(?:googleapis\.com|cloudfunctions\.net)\//,route=>route.abort());
      await context.route('https://www.gstatic.com/flutter-canvaskit/**', async route=>{
        const parts = new URL(route.request().url()).pathname.split('/');
        const file = path.join(root,'canvaskit',...parts.slice(3));
        if(fs.existsSync(file))await route.fulfill({path:file,contentType:mime[path.extname(file)]||'application/octet-stream'});
        else await route.continue();
      });
      page = await context.newPage();
      for(const entry of ['plans','return']){
        await page.goto(`http://127.0.0.1:${server.address().port}/?premium=${entry}&status=success`,{waitUntil:'domcontentloaded'});
        await page.locator('flt-semantics-placeholder').waitFor({state:'attached',timeout:60000});
        await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());
        await page.getByText('Ripot Premium',{exact:true}).waitFor({timeout:60000});
        const signIn = page.getByRole('button',{name:'Sign in to check your free trial',exact:true});
        await signIn.waitFor({state:'visible'});
        const bounds = await signIn.boundingBox();
        assert(bounds && bounds.y >= 0 && bounds.y + bounds.height <= 1000,'Sign-in must be reachable without scrolling past the feature comparison');
        assert.equal(await page.getByText('Premium active',{exact:true}).count(),0);
        assert.equal(await page.getByText('Subscribe monthly',{exact:true}).count(),0);
        assert.equal(await page.evaluate(()=>localStorage.getItem('ripot.qa.local-data')),'preserve-me');
        await page.screenshot({path:path.join(out,`premium-${entry}-${width}.png`)});
      }
      await context.close();
    }
    console.log('PASS: plans and payment-return links reach Premium on mobile/desktop; URL cannot unlock access; local data remains.');
  }catch(e){if(page&&!page.isClosed())await page.screenshot({path:path.join(out,'premium-entry-failure.png')});throw e;}
  finally{await browser.close();server.close();}
})().catch(e=>{console.error(e);server.close();process.exitCode=1;});
