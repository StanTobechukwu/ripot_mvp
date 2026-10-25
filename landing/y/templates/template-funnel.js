/* No network collector is configured. Public template funnel hooks only. */
(() => {
  const slugs = new Set(["colonoscopy-report-template", "upper-gi-endoscopy-report-template", "abdominal-ultrasound-report-template", "echocardiogram-report-template", "flexible-sigmoidoscopy-report-template", "obstetric-ultrasound-report-template", "pelvic-transvaginal-ultrasound-report-template", "thyroid-neck-ultrasound-report-template", "renal-artery-doppler-report-template", "holter-monitor-report-template", "ambulatory-blood-pressure-report-template", "general-surgical-operation-note-template", "caesarean-section-operation-note-template", "appendectomy-operation-note-template", "wound-debridement-minor-operation-note-template"]);
  const actions = new Set(['template_view', 'editor_open', 'report_created', 'pdf_export_started']);
  const query = new URLSearchParams(location.search);
  const sources = new Set(['google', 'whatsapp', 'ripot_templates', 'direct']);
  const media = new Set(['organic', 'social', 'referral', 'direct']);
  const campaigns = new Set(['template_library', 'template_launch']);
  let source = sources.has(query.get('utm_source')) ? query.get('utm_source') : 'direct';
  let medium = media.has(query.get('utm_medium')) ? query.get('utm_medium') : 'direct';
  const campaign = campaigns.has(query.get('utm_campaign')) ? query.get('utm_campaign') : 'template_library';
  if (source === 'direct' && document.referrer) {
    try { const host = new URL(document.referrer).hostname;
      if (/^(www\.)?google\.[a-z.]+$/.test(host)) { source='google'; medium='organic'; }
      else if (host === 'ripot.app') { source='ripot_templates'; medium='referral'; }
    } catch (_) {}
  }
  function emit(event, template) {
    if (!actions.has(event) || !slugs.has(template)) return;
    const detail = Object.freeze({event, template, source, medium, campaign});
    // A future consent-aware collector may listen here. No URLs, report values,
    // names, IDs, text, files or arbitrary query parameters enter the payload.
    window.dispatchEvent(new CustomEvent('ripot-funnel-ready', {detail}));
  }
  window.addEventListener('ripot-template-funnel', e => {
    try { const detail=typeof e.detail === 'string' ? JSON.parse(e.detail) : e.detail; emit(detail?.event,detail?.template); } catch (_) {}
  });
  const slug = location.pathname.split('/')[2];
  if (slugs.has(slug)) emit('template_view', slug);
  document.querySelectorAll('[data-adoption-event="editor_open"]').forEach(link => {
    const url = new URL(link.href);
    for (const [key,value] of Object.entries({utm_source:source==='direct'?'ripot_templates':source,utm_medium:medium==='direct'?'referral':medium,utm_campaign:campaign})) url.searchParams.set(key,value);
    link.href=url.href;
    link.addEventListener('click',()=>emit('editor_open',link.dataset.template));
  });
})();
