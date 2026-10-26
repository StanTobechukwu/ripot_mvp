/* Local-only folder access. No requests, analytics or patient-data uploads. */
(() => {
  'use strict';
  let unlock = null;
  const supported = typeof window.showDirectoryPicker === 'function';
  const db = () => new Promise((resolve, reject) => {
    const r = indexedDB.open('ripot-backup-folders', 1);
    r.onupgradeneeded = () => r.result.createObjectStore('settings');
    r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error);
  });
  async function setting(key, value, write = false) {
    const d = await db();
    try { return await new Promise((resolve, reject) => {
      const tx = d.transaction('settings', write ? 'readwrite' : 'readonly');
      const r = write ? tx.objectStore('settings').put(value, key) : tx.objectStore('settings').get(key);
      tx.oncomplete = () => resolve(r.result);
      tx.onerror = tx.onabort = () => reject(tx.error || new Error('Folder settings could not be saved.'));
    }); } finally { d.close(); }
  }
  async function folder() {
    const h = await setting('folder');
    if (!h || await h.queryPermission({mode:'readwrite'}) !== 'granted') {
      throw new Error('Choose your backup folder again to grant access.');
    }
    return h;
  }
  const safeName = (name, scope) => typeof name === 'string' && name.startsWith(`Ripot-${scope}-`) && /^Ripot-[a-z]+-[A-Za-z0-9.:-]+\.ripotbackup$/.test(name);
  window.ripotBackup = {
    supported,
    async location() { const h = await setting('folder'); return h ? h.name : null; },
    async choose() {
      try {
        // Must call the picker before any await to preserve the user's gesture.
        const h = await window.showDirectoryPicker({mode:'readwrite',id:'ripot-backups'});
        if (!await window.ripotBackup.acquire()) throw new Error('Another backup or restore is running.');
        try {
          const old = await setting('folder');
          if (!old || !await h.isSameEntry(old)) await setting('owned', {}, true);
          await setting('folder', h, true); return h.name;
        } finally { await window.ripotBackup.release(); }
      } catch(e) { if(e.name === 'AbortError') return null; throw e; }
    },
    async acquire() {
      if (unlock) return false;
      // Prevent two tabs backing up or restoring the same local database.
      if (!navigator.locks) throw new Error('This browser cannot safely lock backups. Use a current browser.');
      return new Promise((resolve, reject) => {
        navigator.locks.request('ripot-backup', {ifAvailable:true}, async lock => {
          if (!lock) { resolve(false); return; }
          await new Promise(done => { unlock=done; resolve(true); });
        }).catch(reject);
      });
    },
    async release() { const done=unlock; unlock=null; if(done) done(); },
    async write(data, scope, keep, name) {
      if (!unlock || !safeName(name,scope) || !Number.isInteger(keep) || keep<3 || keep>10) throw new Error('Invalid backup request.');
      const bytes = new Uint8Array(data);
      if(!bytes.length || bytes.length>180*1024*1024) throw new Error('Invalid backup size.');
      const h = await folder();
      try { await h.getFileHandle(name); throw new Error('A backup with this name already exists.'); }
      catch(e) { if(e.name !== 'NotFoundError') throw e; }
      // The browser API has no portable atomic rename. Use a unique name,
      // close and verify every byte before registering or rotating anything.
      try {
        const file = await h.getFileHandle(name,{create:true});
        const stream = await file.createWritable();
        try { await stream.write(bytes); await stream.close(); } catch(e) { try { await stream.abort(); } catch(_) {} throw e; }
        const read = new Uint8Array(await (await file.getFile()).arrayBuffer());
        if(read.length!==bytes.length || read.some((v,i)=>v!==bytes[i])) throw new Error('Backup verification failed.');
      } catch(e) { try { await h.removeEntry(name); } catch(_) {} throw e; }
      const owned = await setting('owned') || {};
      const names = [...(owned[scope] || []), name];
      owned[scope] = names;
      await setting('owned', owned, true);
      const failed=[];
      for(const old of names.slice(0,Math.max(0,names.length-keep))) {
        if(!safeName(old,scope)) { failed.push(old); continue; }
        try { await h.removeEntry(old); } catch(e) { if(e.name!=='NotFoundError') failed.push(old); }
      }
      owned[scope]=[...failed,...names.slice(-keep)];
      await setting('owned',owned,true);
      return failed.length ? `${name} (saved; some older copies could not be removed)` : name;
    }
  };
})();
