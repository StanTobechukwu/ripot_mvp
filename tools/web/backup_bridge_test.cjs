const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');

function fixture() {
  const settings=new Map(), files=new Map();
  let corrupt=false, failWrite=false, permission='granted', held=false;
  const missing=()=>Object.assign(new Error('Missing'),{name:'NotFoundError'});
  const folder={name:'Ripot Backups',isSameEntry:async h=>h===folder,
    queryPermission:async()=>permission,
    async getFileHandle(name, options={}) {
      if(!files.has(name) && !options.create) throw missing();
      if(!files.has(name)) files.set(name,new Uint8Array());
      return {
        async createWritable() { return {
          async write(bytes) {if(failWrite) throw new Error('Disk full');files.set(name,Uint8Array.from(bytes));},
          async close() {},async abort() {},
        };},
        async getFile() {return {arrayBuffer:async()=>corrupt?new Uint8Array([0]).buffer:files.get(name).buffer};},
      };
    },
    async removeEntry(name) {if(!files.delete(name)) throw missing();},
  };
  const indexedDB={open() {
    const request={result:{
      createObjectStore(){},close(){},
      transaction() {
        const tx={objectStore:()=>({
          get(key){const r={result:settings.get(key)};queueMicrotask(()=>tx.oncomplete());return r;},
          put(value,key){settings.set(key,value);const r={result:key};queueMicrotask(()=>tx.oncomplete());return r;},
        })};return tx;
      },
    }};queueMicrotask(()=>request.onsuccess());return request;
  }};
  const window={showDirectoryPicker:async()=>folder};
  const navigator={locks:{async request(name,options,action){
    if(held) return action(null);held=true;
    try {return await action({name});}finally{held=false;}
  }}};
  vm.runInNewContext(fs.readFileSync('web/ripot-backup.js','utf8'),{window,navigator,indexedDB,Uint8Array});
  return {bridge:window.ripotBackup,files,settings,folder,
    corrupt:()=>{corrupt=true;},failWrite:()=>{failWrite=true;},revoke:()=>{permission='denied';}};
}
const bytes=new Uint8Array([4,2,7]);
const name=n=>`Ripot-all-20261026-${n}.ripotbackup`;

test('verified rotation keeps separate scopes and unrelated files',async()=>{
  const f=fixture();await f.bridge.choose();await f.bridge.acquire();
  f.files.set(name('unowned'),bytes);
  for(let n=0;n<6;n++) await f.bridge.write(bytes,'all',3,name(n));
  await f.bridge.write(bytes,'reports',3,'Ripot-reports-20261026-1.ripotbackup');
  assert.deepEqual([...f.files.keys()].sort(),[name(3),name(4),name(5),name('unowned'),'Ripot-reports-20261026-1.ripotbackup'].sort());
  await f.bridge.release();
});
for(const failure of ['corrupt','failWrite','revoke']) test(`${failure} preserves earlier backups`,async()=>{
  const f=fixture();await f.bridge.choose();await f.bridge.acquire();
  for(let n=0;n<3;n++) await f.bridge.write(bytes,'all',3,name(n));
  f[failure]();await assert.rejects(f.bridge.write(bytes,'all',3,name(3)));
  assert.deepEqual([...f.files.keys()],[name(0),name(1),name(2)]);
  await f.bridge.release();
});
test('collision and unsafe names cannot replace or delete files',async()=>{
  const f=fixture();await f.bridge.choose();await f.bridge.acquire();
  await f.bridge.write(bytes,'all',3,name(1));
  await assert.rejects(f.bridge.write(new Uint8Array([8]),'all',3,name(1)));
  await assert.rejects(f.bridge.write(bytes,'all',3,'../outside.ripotbackup'));
  assert.deepEqual(f.files.get(name(1)),bytes);
  await f.bridge.release();
});
test('a second operation cannot acquire the lock or change folders',async()=>{
  const f=fixture();await f.bridge.choose();assert.equal(await f.bridge.acquire(),true);
  assert.equal(await f.bridge.acquire(),false);await assert.rejects(f.bridge.choose());
  await f.bridge.release();await new Promise(resolve=>setImmediate(resolve));
  assert.equal(await f.bridge.acquire(),true);await f.bridge.release();
});
test('write without lock is rejected',async()=>{
  const f=fixture();await f.bridge.choose();
  await assert.rejects(f.bridge.write(bytes,'all',3,name(1)));
  assert.equal(f.files.size,0);
});
