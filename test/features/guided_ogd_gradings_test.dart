import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/features/reports/data/reports_repository.dart';
import 'package:ripot/features/reports/data/templates_repository.dart';
import 'package:ripot/features/reports/domain/guided_report_presentation.dart';
import 'package:ripot/features/reports/domain/models/nodes.dart';
import 'package:ripot/features/reports/domain/pdf/pdf_plan.dart';
import 'package:ripot/features/reports/domain/serialization/report_codec.dart';
import 'package:ripot/features/reports/domain/serialization/template_codec.dart';
import 'package:ripot/features/reports/providers/report_editor_provider.dart';
import 'package:ripot/features/reports/services/pdf_renderer_service.dart';
import 'package:ripot/features/reports/services/report_text_service.dart';
import 'package:ripot/features/reports/ui/widgets/grading_guide_button.dart';

Iterable<SectionNode> walk(Iterable<SectionNode> nodes) sync* {
  for (final n in nodes) {
    yield n;
    yield* walk(n.children.whereType<SectionNode>());
  }
}

ReportEditorProvider editor() {
  final json = jsonDecode(File('landing/y/templates/downloads/structured-upper-gi-endoscopy-report-template.ripottemplate.json').readAsStringSync());
  return ReportEditorProvider(repo: ReportsRepository(), templatesRepo: TemplatesRepository())
    ..newReportFromTemplate(TemplateCodec.templateFromJson(Map<String, dynamic>.from(json['template'])));
}

SectionNode node(ReportEditorProvider vm, String id) => walk(vm.doc.roots).firstWhere((n) => n.id == id);
SectionNode field(ReportEditorProvider vm, String entry, String role) => walk([node(vm, entry)]).firstWhere((n) => n.reportRole == role);
void set(ReportEditorProvider vm, SectionNode section, String value) =>
    vm.updateContent(section.children.whereType<ContentNode>().first.id, value);
void setRole(ReportEditorProvider vm, String entry, String role, String value) => set(vm, field(vm, entry, role), value);
String text(ReportEditorProvider vm) => const ReportTextService().render(vm.doc);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Prague pairs stay local to each finding, preserve zeros and survive save/reopen', () {
    final vm = editor();
    set(vm, node(vm, 'oesophagus_status'), 'Abnormal');
    final first = vm.addRepeatableFinding('oesophagus_findings', 'oesophagus_barrett')!;
    final second = vm.addRepeatableFinding('oesophagus_findings', 'oesophagus_barrett')!;
    setRole(vm, first, 'grading.prague.c', '2');
    setRole(vm, first, 'grading.prague.m', '4');
    setRole(vm, second, 'grading.prague.c', '0');
    setRole(vm, second, 'grading.prague.m', '1.5');
    expect(text(vm), contains('Prague C2M4'));
    expect(text(vm), contains('Prague C0M1.5'));
    expect(guidedReportWarnings(vm.doc.roots), isEmpty);
    final saved = ReportCodec.reportToJson(vm.doc);
    final reopened = ReportCodec.reportFromJson(saved);
    expect(const ReportTextService().render(reopened), text(vm));
    expect(ReportCodec.reportToJson(reopened), saved);
    setRole(vm, first, 'grading.prague.m', '5');
    expect(text(vm), contains('Prague C2M5'));
    expect(text(vm), isNot(contains('C2M4')));
    expect(text(vm), contains('Prague C0M1.5'));
    vm.dispose();
  });

  test('invalid or partial Prague values are retained, warned about and never presented as confirmed notation', () {
    final vm = editor();
    set(vm, node(vm, 'oesophagus_status'), 'Abnormal');
    final id = vm.addRepeatableFinding('oesophagus_findings', 'oesophagus_barrett')!;
    expect(guidedReportWarnings(vm.doc.roots), isEmpty);
    for (final pair in [ ['4', '2'], ['-1', '2'], ['NaN', '3'], ['0', 'Infinity'], ['2', ''], ['', '3'] ]) {
      setRole(vm, id, 'grading.prague.c', pair[0]);
      setRole(vm, id, 'grading.prague.m', pair[1]);
      expect(guidedReportWarnings(vm.doc.roots), hasLength(1), reason: '$pair');
      expect(text(vm), isNot(matches(r'Prague C[0-9]+M')));
      if (pair[0].isNotEmpty) expect(text(vm), contains(pair[0]));
      if (pair[1].isNotEmpty) expect(text(vm), contains(pair[1]));
    }
    set(vm, node(vm, 'oesophagus_status'), 'Normal');
    expect(guidedReportWarnings(vm.doc.roots), isEmpty);
    expect(text(vm), isNot(contains('Prague')));
    vm.dispose();
  });

  test('grading choices are optional, independent, editable and included in copy and PDF without a score', () async {
    final vm = editor();
    set(vm, node(vm, 'oesophagus_status'), 'Abnormal');
    set(vm, node(vm, 'stomach_status'), 'Abnormal');
    final reflux = vm.addRepeatableFinding('oesophagus_findings', 'oesophagus_reflux')!;
    final eoe = vm.addRepeatableFinding('oesophagus_findings', 'oesophagus_eoe')!;
    final barrett = vm.addRepeatableFinding('oesophagus_findings', 'oesophagus_barrett')!;
    final ulcer = vm.addRepeatableFinding('stomach_findings', 'stomach_ulcer')!;
    final gastricVarices = vm.addRepeatableFinding('stomach_findings', 'stomach_varices')!;
    final polyp = vm.addRepeatableFinding('stomach_findings', 'stomach_polyp')!;
    expect(walk(vm.doc.roots).where((n) => n.reportRole.startsWith('grading.')).every((n) => fieldValue(n).isEmpty), isTrue);
    setRole(vm, reflux, 'grading.la', 'B');
    setRole(vm, ulcer, 'grading.forrest', 'IIa — non-bleeding visible vessel');
    setRole(vm, gastricVarices, 'grading.sarin', 'GOV2');
    setRole(vm, polyp, 'grading.paris', '0-IIa — slightly elevated');
    setRole(vm, eoe, 'grading.erefs.oedema', 'Not assessed');
    setRole(vm, eoe, 'grading.erefs.rings', '0 — absent');
    setRole(vm, eoe, 'grading.erefs.exudates', '2 — more than 10% of the surface');
    setRole(vm, barrett, 'grading.prague.c', '2');
    setRole(vm, barrett, 'grading.prague.m', '4');
    final copied = text(vm);
    for (final expected in ['Los Angeles grade', 'IIa', 'non-bleeding visible vessel', 'GOV2', '0-IIa', 'EREFS oedema', 'Not assessed', 'Prague C2M4']) {
      expect(copied, contains(expected));
    }
    expect(copied, isNot(contains('EREFS total')));
    expect(copied, isNot(contains('grading guide')));
    // Clinician-authored wording remains possible, with no automatic recoding.
    setRole(vm, polyp, 'grading.paris', 'Mixed morphology; see description');
    expect(text(vm), contains('Mixed morphology; see description'));
    final rawBefore = jsonEncode(ReportCodec.reportToJson(vm.doc));
    final pdf = await PdfRendererService().generatePdfBytes(doc: vm.doc,
      plan: const PdfPlan(title: 'Fictional grading QA', inlineEnabled: false,
        pageOne: PageOnePlan(inlineImages: []), finalContent: FinalContentPlan(spillInlineImages: []), attachmentPages: []));
    Directory('build/ogd-qa').createSync(recursive: true);
    File('build/ogd-qa/gradings.pdf').writeAsBytesSync(pdf);
    expect(jsonEncode(ReportCodec.reportToJson(vm.doc)), rawBefore);
    vm.dispose();
  });

  for (final width in [360.0, 1280.0]) {
    testWidgets('bundled grading guides fit and work offline at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final role in ['grading.la', 'grading.prague.c', 'grading.forrest', 'grading.sarin', 'grading.baveno', 'grading.erefs.exudates', 'grading.paris']) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: GradingGuideButton(role: role))));
        await tester.tap(find.byTooltip('Grading guide'));
        await tester.pumpAndSettle();
        expect(find.text('This guide is unavailable. You can still enter your findings.'), findsNothing);
        expect(find.text('Loading guide…'), findsNothing);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      }
    });
  }
}
