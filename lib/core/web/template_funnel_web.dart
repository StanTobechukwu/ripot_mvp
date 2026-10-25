// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';

// Only catalogue identifiers cross the browser boundary. Never pass a ReportDoc.
void templateFunnelEvent(String event, String templateId) {
  if (!const {'report_created', 'pdf_export_started'}.contains(event)) return;
  const slugs = <String>{'colonoscopy-report-template', 'upper-gi-endoscopy-report-template', 'abdominal-ultrasound-report-template', 'echocardiogram-report-template', 'flexible-sigmoidoscopy-report-template', 'obstetric-ultrasound-report-template', 'pelvic-transvaginal-ultrasound-report-template', 'thyroid-neck-ultrasound-report-template', 'renal-artery-doppler-report-template', 'holter-monitor-report-template', 'ambulatory-blood-pressure-report-template', 'general-surgical-operation-note-template', 'caesarean-section-operation-note-template', 'appendectomy-operation-note-template', 'wound-debridement-minor-operation-note-template'};
  String? slug;
  for (final candidate in slugs) {
    if (RegExp('^public_${candidate}_[a-f0-9]{16}\$').hasMatch(templateId)) { slug = candidate; break; }
  }
  if (slug == null) return;
  html.window.dispatchEvent(html.CustomEvent('ripot-template-funnel', detail: jsonEncode({'event': event, 'template': slug})));
}
