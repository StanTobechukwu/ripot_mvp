(() => {
  document.querySelectorAll('[data-copy]').forEach(button => button.addEventListener('click', async () => {
    const kind = button.dataset.copy;
    const element = document.getElementById(kind === 'example' ? 'example' : 'outline');
    const plain = kind === 'url' ? location.href : element?.textContent;
    const status = button.closest('section')?.querySelector('[data-copy-status]');
    if (!plain) return;
    try {
      // Rich text preserves hierarchy in compatible editors; plain text remains
      // an intentional, readable fallback for SMS, notes and other plain editors.
      if (kind !== 'url' && window.ClipboardItem && navigator.clipboard?.write) {
        const html = document.getElementById(kind === 'example' ? 'example-rich' : 'outline-rich')?.innerHTML;
        if (html) {
          try {
            await navigator.clipboard.write([new ClipboardItem({
              'text/plain': new Blob([plain], {type:'text/plain'}),
              'text/html': new Blob([html], {type:'text/html'}),
            })]);
          } catch (_) { await navigator.clipboard.writeText(plain); }
        } else { await navigator.clipboard.writeText(plain); }
      } else { await navigator.clipboard.writeText(plain); }
      if (status) status.textContent = kind === 'example' ? 'Fictional example copied, including its demonstration label.' : 'Outline copied. Formatting depends on the app you paste into.';
      else { button.textContent = 'Link copied'; }
    } catch (_) {
      if (element) {
        const details = element.closest('details'); if (details) details.open = true;
        const range = document.createRange(); range.selectNodeContents(element);
        const selection = getSelection(); selection.removeAllRanges(); selection.addRange(range);
      }
      if (status) status.textContent = 'Automatic copying is unavailable. Select and copy the text below.';
    }
  }));
  const viewer = document.querySelector('[data-report-viewer]');
  if (viewer) {
    const variants = JSON.parse(document.getElementById('preview-data').textContent);
    let variant = 'blank', index = 0;
    const image = viewer.querySelector('[data-page-image]');
    const count = viewer.querySelector('[data-page-count]');
    const previous = viewer.querySelector('[data-previous]'), next = viewer.querySelector('[data-next]');
    const download = document.getElementById('download-pdf');
    const dialog = document.getElementById('report-zoom');
    const large = dialog.querySelector('img');
    const zoomBody = dialog.querySelector('.zoom-body');
    function update() {
      const item = variants[variant];
      image.src = '/templates/previews/' + item.pages[index];
      image.alt = `${viewer.dataset.title} - ${variant === 'blank' ? 'blank template' : 'fictional example'}, page ${index + 1} of ${item.pages.length}`;
      count.textContent = `Page ${index + 1} of ${item.pages.length}`;
      previous.disabled = index === 0; next.disabled = index === item.pages.length - 1;
      download.href = '/templates/previews/' + item.pdf;
      download.textContent = variant === 'blank' ? 'Download blank PDF' : 'Download fictional example PDF';
      viewer.querySelector('[data-preview-note]').textContent = variant === 'blank'
        ? 'Actual PDF preview. Tap the page to enlarge. Complete only applicable fields.'
        : 'Fictional example for layout demonstration. Not a clinical reference or patient report.';
      viewer.querySelectorAll('[data-variant]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.variant === variant)));
      large.src = image.src; large.alt = image.alt;
      dialog.querySelector('[data-zoom-title]').textContent = count.textContent + (variant === 'example' ? ' · Fictional example' : ' · Blank template');
    }
    viewer.querySelectorAll('[data-variant]').forEach(b => b.addEventListener('click', () => {variant = b.dataset.variant; index = 0; update();}));
    previous.addEventListener('click', () => {if(index > 0) {index--;update();}});
    next.addEventListener('click', () => {if(index < variants[variant].pages.length - 1) {index++;update();}});
    viewer.querySelector('[data-enlarge]').addEventListener('click', () => {zoomBody.classList.remove('is-zoomed');dialog.querySelector('[data-zoom-toggle]').textContent='Zoom in';update();dialog.showModal();});
    dialog.querySelector('[data-close]').addEventListener('click', () => dialog.close());
    dialog.querySelector('[data-zoom-toggle]').addEventListener('click', e => {const zoomed = zoomBody.classList.toggle('is-zoomed');e.currentTarget.textContent=zoomed?'Fit page':'Zoom in';});
    dialog.addEventListener('click', e => {if(e.target === dialog) dialog.close();});
    update();
  }
})();
