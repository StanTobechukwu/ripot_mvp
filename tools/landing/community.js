/* Public read-only catalogue. Never render contributor-controlled HTML. */
(async () => {
  const api = 'https://us-central1-ripot-4edf7.cloudfunctions.net/publicTemplateLibrary';
  const grid = document.getElementById('community-templates');
  const preview = document.getElementById('community-preview');
  const section = document.getElementById('community-section');
  if (!grid && !preview) return;
  const status = document.getElementById('community-status');
  function el(tag, text, parent) { const node = document.createElement(tag); if (text) node.textContent = text; if (parent) parent.append(node); return node; }
  function valid(row) { return row && row.status === 'approved' && /^community-[a-z0-9-]{1,80}$/.test(row.slug) && /^[a-f0-9]{16}$/.test(row.version); }
  async function get(params) {
    const url = new URL(api); for (const [k,v] of Object.entries(params)) url.searchParams.set(k,v);
    const response = await fetch(url, { signal: AbortSignal.timeout(12000) });
    if (!response.ok) throw Error('Unavailable');
    const text = await response.text(); if (text.length > 1000000) throw Error('Too large');
    return JSON.parse(text);
  }
  try {
    if (grid) {
      let cursor, count = 0, pages = 0;
      do {
        const data = await get(cursor ? {cursor} : {});
        if (data.schemaVersion !== 1 || !Array.isArray(data.templates)) throw Error('Invalid catalogue');
        for (const row of data.templates.filter(valid)) {
          const card = el('article', '', grid); card.className = 'card';
          el('span', row.specialty, card).className = 'eyebrow';
          const heading = el('h2', '', card), link = el('a', row.name, heading);
          link.href = '/templates/community.html?template=' + encodeURIComponent(row.slug) + '&version=' + row.version;
          el('p', row.description, card); el('p', 'Contributor: ' + row.contributor + ' · Version ' + row.version, card).className = 'note';
          const open = el('a', 'Preview and use →', card); open.href = link.href;
          count++;
        }
        cursor = data.cursor; if (++pages >= 20 && cursor) throw Error('Catalogue limit');
      } while (cursor);
      if (section) section.hidden = count < 3;
      status.textContent = count ? 'Reviewed contributions, available here and in the Ripot app.' : 'No community templates have been published yet. You can contribute a structure for review.';
    } else {
      const params = new URLSearchParams(location.search), slug = params.get('template'), version = params.get('version');
      if (!/^community-[a-z0-9-]{1,80}$/.test(slug || '') || (version && !/^[a-f0-9]{16}$/.test(version))) throw Error('Invalid link');
      const row = await get({template: slug, ...(version ? {version} : {})});
      if (!valid(row) || row.slug !== slug || (version && row.version !== version) || typeof row.payload !== 'string') throw Error('Invalid template');
      const bytes = new TextEncoder().encode(row.payload);
      const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2,'0')).join('');
      if (hash !== row.sha256 || hash.slice(0,16) !== row.version) throw Error('Invalid checksum');
      const payload = JSON.parse(row.payload);
      if (payload.app !== 'Ripot' || payload.ripotFileType !== 'template' || !Array.isArray(payload.template?.roots)) throw Error('Invalid file');
      document.title = row.name + ' | Ripot';
      el('span', row.specialty + ' · Contributor: ' + row.contributor, preview).className = 'eyebrow';
      el('h1', row.name, preview); el('p', row.description, preview).className = 'lead';
      el('p', 'Approved version ' + row.version, preview).className = 'note';
      const actions = el('div','',preview); actions.className = 'actions';
      const open = el('a','Use in Ripot Web →',actions); open.className = 'button'; open.href = 'https://ripot-web.web.app/?template=' + encodeURIComponent(slug) + '&version=' + row.version;
      const download = el('a','Download Ripot import file',actions); download.className = 'button secondary'; download.download = slug + '.ripottemplate.json';
      download.href = URL.createObjectURL(new Blob([row.payload], {type:'application/json'}));
      window.addEventListener('pagehide', () => URL.revokeObjectURL(download.href), {once:true});
      el('p','In Ripot, use Templates → Browse online templates to save a personal copy, or import this downloaded file. New versions never overwrite your edited copies.', preview);
      el('h2','Included fields',preview);
      let count = 0;
      function walk(nodes, parent, depth = 0) {
        if (depth > 8 || !Array.isArray(nodes)) throw Error('Invalid structure');
        const list = el('ul','',parent);
        for (const node of nodes) {
          if (++count > 200) throw Error('Too many fields');
          if (node.type !== 'section') continue;
          const item = el('li',node.title + (node.unit ? ' (' + node.unit + ')' : ''),list);
          if (node.options?.length) el('p','Options: ' + node.options.join(', '),item);
          if (node.children?.length) walk(node.children,item,depth+1);
        }
      }
      walk(payload.template.roots,preview); status.textContent = '';
    }
  } catch (_) {
    if (preview) preview.replaceChildren();
    if (section) section.hidden = true;
    status.textContent = 'Community templates are temporarily unavailable. Please try again later; starter templates and your saved app templates remain available.';
  }
})();
