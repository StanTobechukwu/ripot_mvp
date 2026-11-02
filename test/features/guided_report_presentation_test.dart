import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/features/reports/data/reports_repository.dart';
import 'package:ripot/features/reports/data/templates_repository.dart';
import 'package:ripot/features/reports/domain/guided_report_presentation.dart';
import 'package:ripot/features/reports/domain/models/nodes.dart';
import 'package:ripot/features/reports/domain/models/template_doc.dart';
import 'package:ripot/features/reports/domain/serialization/report_codec.dart';
import 'package:ripot/features/reports/domain/serialization/template_codec.dart';
import 'package:ripot/features/reports/domain/pdf/pdf_plan.dart';
import 'package:ripot/features/reports/providers/report_editor_provider.dart';
import 'package:ripot/features/reports/services/pdf_renderer_service.dart';
import 'package:ripot/features/reports/services/report_text_service.dart';

Iterable<SectionNode> walk(Iterable<SectionNode> roots) sync* {
  for (final n in roots) { yield n; yield* walk(n.children.whereType<SectionNode>()); }
}
TemplateDoc template() => TemplateCodec.templateFromJson(Map<String, dynamic>.from(
  jsonDecode(File('landing/y/templates/downloads/structured-upper-gi-endoscopy-report-template.ripottemplate.json').readAsStringSync())['template']));
ReportEditorProvider editor() => ReportEditorProvider(repo: ReportsRepository(), templatesRepo: TemplatesRepository())..newReportFromTemplate(template());
SectionNode node(ReportEditorProvider vm, String id) => walk(vm.doc.roots).firstWhere((n) => n.id == id);
SectionNode child(ReportEditorProvider vm, String id, String title) => walk([node(vm, id)]).firstWhere((n) => n.title == title);
void set(ReportEditorProvider vm, String id, String value) => vm.updateContent(node(vm, id).children.whereType<ContentNode>().first.id, value);
void setChild(ReportEditorProvider vm, String id, String title, String value) => set(vm, child(vm, id, title).id, value);
String reportText(List<SectionNode> roots) => walk(prepareGuidedReport(roots))
  .map((n) => '${n.title}: ${fieldValue(n)}').join('\n');
const plan = PdfPlan(title: 'Fictional guided OGD QA', inlineEnabled: false,
  pageOne: PageOnePlan(inlineImages: []), finalContent: FinalContentPlan(spillInlineImages: []), attachmentPages: []);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('new form keeps roles on cloning and save; legacy reports retain their layout', () async {
    final vm = editor();
    expect(node(vm, 'extra_details').collapsed, isTrue);
    expect(node(vm, 'medications').isRepeatable, isTrue);
    expect(walk(vm.doc.roots).where((n) => n.id == 'sedation_drugs' || n.id == 'medication_plan'), isEmpty);
    final id = vm.addRepeatableFinding('medications', 'medication_entry')!;
    setChild(vm, id, 'Drug', 'Fictional drug');
    setChild(vm, id, 'Dose', '2.5');
    setChild(vm, id, 'Dose unit', 'mg');
    setChild(vm, id, 'Route', 'IV');
    final saved = ReportCodec.reportToJson(vm.doc);
    final reopened = ReportCodec.reportFromJson(saved);
    expect(reportText(reopened.roots), contains('Fictional drug: 2.5 mg; IV'));
    expect(const ReportTextService().render(reopened), contains('Fictional drug:\n2.5 mg; IV'));
    expect(ReportCodec.reportToJson(reopened), saved);
    final roundTrip = TemplateCodec.templateFromJson(TemplateCodec.templateToJson(template()));
    expect(walk(roundTrip.roots).firstWhere((n) => n.id == 'extra_details').reportRole, 'ogd.details');
    final original = jsonEncode(ReportCodec.reportToJson(vm.doc));
    prepareGuidedReport(vm.doc.roots);
    expect(jsonEncode(ReportCodec.reportToJson(vm.doc)), original);
    final legacy = [const SectionNode(id: 'old', title: 'Location', children: [ContentNode(id: 'old_value', text: 'Antrum')])];
    expect(identical(prepareGuidedReport(legacy), legacy), isTrue);
    vm.dispose();
  });

  test('compact anatomical findings, explicit normal status and one biopsy summary produce real PDFs', () async {
    final vm = editor();
    set(vm, 'consent', 'Obtained'); set(vm, 'fasting', 'Confirmed');
    set(vm, 'antithrombotics', 'None reported'); set(vm, 'safety', 'Completed');
    set(vm, 'duration', '8'); set(vm, 'extent', 'Second part of duodenum');
    set(vm, 'oesophagus_status', 'Abnormal');
    final reflux = vm.addRepeatableFinding('oesophagus_findings', 'oesophagus_reflux')!;
    setChild(vm, reflux, 'Location', 'Upper oesophagus');
    setChild(vm, reflux, 'Los Angeles grade', 'B');
    final varices = vm.addRepeatableFinding('oesophagus_findings', 'oesophagus_varices')!;
    setChild(vm, varices, 'Location', 'Middle oesophagus');
    setChild(vm, varices, 'Size', 'Large (5 mm or greater)');
    setChild(vm, varices, 'Red signs', 'Red wale marks');
    setChild(vm, varices, 'Bleeding', 'White nipple sign');
    set(vm, 'stomach_status', 'Abnormal');
    final ulcer = vm.addRepeatableFinding('stomach_findings', 'stomach_ulcer')!;
    setChild(vm, ulcer, 'Location', 'Antrum'); setChild(vm, ulcer, 'Size', '10');
    setChild(vm, ulcer, 'Shape', 'Oval'); setChild(vm, ulcer, 'Edge', 'Regular');
    setChild(vm, ulcer, 'Bleeding stigmata / Forrest category', 'III — clean base');
    setChild(vm, ulcer, 'Biopsy taken?', 'Yes');
    setChild(vm, ulcer, 'Number of biopsies', '2');
    setChild(vm, ulcer, 'Sampling type', 'Targeted');
    setChild(vm, ulcer, 'Container / label', 'A');
    final erosion = vm.addRepeatableFinding('stomach_findings', 'stomach_erosions')!;
    setChild(vm, erosion, 'Location', 'Fundus');
    setChild(vm, erosion, 'Number', 'Multiple');
    setChild(vm, erosion, 'Distribution', 'Patchy');
    setChild(vm, erosion, 'Appearance', 'Linear');
    setChild(vm, erosion, 'Bleeding', 'Oozing');
    set(vm, 'duodenum_status', 'Normal');
    final sample = vm.addRepeatableFinding('specimens', 'specimen_entry')!;
    setChild(vm, sample, 'Region', 'Duodenum');
    setChild(vm, sample, 'Site', 'Second part of duodenum');
    setChild(vm, sample, 'Number of biopsies', '4');
    setChild(vm, sample, 'Sampling type', 'Non-targeted / random');
    setChild(vm, sample, 'Container / label', 'B');
    final drug = vm.addRepeatableFinding('medications', 'medication_entry')!;
    setChild(vm, drug, 'Drug', 'Midazolam'); setChild(vm, drug, 'Dose', '2');
    setChild(vm, drug, 'Dose unit', 'mg'); setChild(vm, drug, 'Route', 'IV');
    final original = ReportCodec.reportToJson(vm.doc);
    final rendered = prepareGuidedReport(vm.doc.roots);
    final text = reportText(vm.doc.roots);
    for (final prompt in ['if applicable', 'if recorded', 'if relevant', 'Abnormal', 'oesophagus finding', 'stomach finding', 'Location:']) {
      expect(text, isNot(contains(prompt)), reason: prompt);
    }
    expect(walk(rendered).where((n) => n.title == 'Upper oesophagus'), hasLength(1));
    expect(text, contains('Los Angeles grade: B'));
    expect(text, contains('Red signs: Red wale marks'));
    expect(text, contains('Distribution: Patchy'));
    expect(text, contains('Bleeding: Oozing'));
    expect(text, contains('Duodenum: Normal'));
    expect(text, contains('Midazolam: 2 mg; IV'));
    expect(text, contains('Preparation and safety: Consent: Obtained'));
    expect(guidedSamplingSummary(vm.doc.roots), hasLength(2));
    expect('Container: A'.allMatches(text), hasLength(1));
    expect(guidedReportWarnings(vm.doc.roots), isEmpty);
    expect(ReportCodec.reportToJson(vm.doc), original);
    final out = Directory('build/ogd-qa')..createSync(recursive: true);
    await File('${out.path}/concise-report.pdf').writeAsBytes(await PdfRendererService().generatePdfBytes(doc: vm.doc, plan: plan));
    set(vm, 'stomach_status', 'Normal');
    expect(guidedSamplingSummary(vm.doc.roots), hasLength(1), reason: 'Hidden abnormal biopsies must not leak into sampling');
    expect(reportText(vm.doc.roots), isNot(contains('Container: A')));
    await File('${out.path}/concise-normal.pdf').writeAsBytes(await PdfRendererService().generatePdfBytes(doc: vm.doc, plan: plan));
    set(vm, 'stomach_status', 'Abnormal');
    expect(guidedSamplingSummary(vm.doc.roots), hasLength(2));
    setChild(vm, ulcer, 'Biopsy taken?', 'No');
    expect(guidedSamplingSummary(vm.doc.roots), hasLength(1));
    expect(reportText(vm.doc.roots), contains('Biopsy: No'));
    vm.dispose();
  });

  test('unanswered fields never invent normal findings; assessment controls and location notes retain meaning', () {
    final vm = editor();
    expect(reportText(vm.doc.roots), isNot(contains(': Normal')));
    set(vm, 'oesophagus_status', 'Not examined');
    expect(reportText(vm.doc.roots), contains('Oesophagus: Not examined'));
    set(vm, 'stomach_status', 'Abnormal');
    expect(guidedReportWarnings(vm.doc.roots), hasLength(1));
    expect(reportText(vm.doc.roots), contains('Abnormal — findings not recorded'));
    final erosion = vm.addRepeatableFinding('stomach_findings', 'stomach_erosions')!;
    setChild(vm, erosion, 'Location', 'Body');
    setChild(vm, erosion, 'Appearance', 'A clinician-entered description');
    expect(guidedReportWarnings(vm.doc.roots), isEmpty);
    final text = reportText(vm.doc.roots);
    expect(text, contains('A clinician-entered description'));
    expect(text, isNot(contains('None seen')));
    expect(text, isNot(contains('No bleeding')));
    expect(text, isNot(contains('Number: 0')));
    vm.dispose();
  });
}
