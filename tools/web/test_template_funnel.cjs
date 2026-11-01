const assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const code=fs.readFileSync('web/template-funnel.js','utf8');
function check(search,referrer,slug='colonoscopy-report-template'){
 const listeners={},events=[],link={href:'https://ripot-web.web.app/?template=colonoscopy-report-template&version=123',dataset:{template:slug},addEventListener:(n,f)=>listeners.click=f};
 const context={URL,URLSearchParams,Set,Object,JSON,location:{search,pathname:'/templates/'+slug+'/'},document:{referrer,querySelectorAll:()=>[link]},CustomEvent:class{constructor(type,init){this.type=type;this.detail=init.detail}},window:{addEventListener:(n,f)=>listeners[n]=f,dispatchEvent:e=>events.push(e)}};
 vm.runInNewContext(code,context);
 listeners['ripot-template-funnel']({detail:JSON.stringify({event:'report_created',template:slug,patient:'NEVER-SEND'})});
 listeners['ripot-template-funnel']({detail:{event:'pdf_export_started',template:slug,name:'NEVER-SEND'}});
 listeners['ripot-template-funnel']({detail:{event:'report_created',template:'PATIENT-NAME'}});
 listeners.click();
 assert.equal(events.length,4);
 for(const e of events){assert.deepEqual(Object.keys(e.detail).sort(),['campaign','event','medium','source','template']);assert(!JSON.stringify(e).includes('NEVER-SEND'));}
 return {events,link};
}
let r=check('?utm_source=whatsapp&utm_medium=social&utm_campaign=template_launch&patient=NEVER-SEND','');
assert.equal(r.events[0].detail.source,'whatsapp');assert(r.link.href.includes('utm_medium=social'));
r=check('','https://www.google.com/search?q=NEVER-SEND');assert.equal(r.events[0].detail.medium,'organic');
r=check('?utm_source=NEVER-SEND&utm_campaign=NEVER-SEND','');assert.equal(r.events[0].detail.source,'direct');assert.equal(r.events[0].detail.campaign,'template_library');
console.log('PASS: funnel stages and attribution allowlists; no patient values, arbitrary query parameters, or network collector.');

for (const entry of JSON.parse(fs.readFileSync('tools/landing/additional_catalog.json'))) check('', '', entry.slug);
