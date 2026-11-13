import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/features/reports/domain/models/nodes.dart';
import 'package:ripot/features/reports/domain/models/template_doc.dart';
import 'package:ripot/features/reports/domain/serialization/template_codec.dart';
import 'package:ripot/features/reports/domain/serialization/report_codec.dart';
import 'package:ripot/features/reports/domain/finding_report_order.dart';
import 'package:ripot/features/reports/providers/report_editor_provider.dart';
import 'package:ripot/features/reports/data/reports_repository.dart';
import 'package:ripot/features/reports/data/templates_repository.dart';
import 'package:ripot/features/reports/ui/report_editor_screen.dart';
import 'package:ripot/features/reports/domain/pdf/pdf_plan.dart';
import 'package:ripot/features/reports/services/pdf_renderer_service.dart';

TemplateDoc loadOgd() => TemplateCodec.templateFromJson(Map<String,dynamic>.from(
  jsonDecode(File('landing/y/templates/downloads/structured-upper-gi-endoscopy-report-template.ripottemplate.json').readAsStringSync())['template'] as Map));
Iterable<SectionNode> sections(Iterable<SectionNode> roots) sync* {
  for(final s in roots) { yield s; yield* sections(s.children.whereType<SectionNode>()); }
}
SectionNode node(ReportEditorProvider vm, String id) => sections(vm.doc.roots).firstWhere((s)=>s.id==id);
void setValue(ReportEditorProvider vm, String id, String value) => vm.updateContent(node(vm,id).children.whereType<ContentNode>().first.id,value);
String value(SectionNode n) => n.children.whereType<ContentNode>().first.text;
SectionNode childNamed(ReportEditorProvider vm, String item, String title) => sections([node(vm,item)]).firstWhere((n)=>n.title==title);
ReportEditorProvider editor() => ReportEditorProvider(repo:ReportsRepository(),templatesRepo:TemplatesRepository())..newReportFromTemplate(loadOgd());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>SharedPreferences.setMockInitialValues({}));
  test('blank form, field types, independent lesions, remapped conditionals, save/reopen and PDF order', () async {
    final vm=editor();
    expect(node(vm,'extent').inputType,FieldInputType.singleSelect);
    expect(node(vm,'extent').options,contains('Second part of duodenum'));
    for(final id in ['consent','fasting','antithrombotics','safety']) {
      expect(node(vm,id).inputType,FieldInputType.singleSelect);
    }
    expect(sections(vm.doc.roots).expand((s)=>s.children.whereType<ContentNode>()).every((c)=>c.text.isEmpty),isTrue);
    expect(node(vm,'stomach_findings').children,isEmpty);
    setValue(vm,'stomach_status','Abnormal');
    final a=vm.addRepeatableFinding('stomach_findings','stomach_ulcer')!;
    final b=vm.addRepeatableFinding('stomach_findings','stomach_ulcer')!;
    final p=vm.addRepeatableFinding('stomach_findings','stomach_polyp')!;
    expect({a,b,p},hasLength(3));
    final all=sections(vm.doc.roots).map((s)=>s.id).toList();
    expect(all.toSet().length,all.length);
    setValue(vm,childNamed(vm,a,'Location').id,'Antrum');
    setValue(vm,childNamed(vm,b,'Location').id,'Body');
    setValue(vm,childNamed(vm,p,'Location').id,'Cardia');
    setValue(vm,childNamed(vm,a,'Size').id,'10');
    setValue(vm,childNamed(vm,b,'Size').id,'20');
    setValue(vm,childNamed(vm,a,'Bleeding stigmata / Forrest category').id,'III — clean base');
    setValue(vm,childNamed(vm,b,'Bleeding stigmata / Forrest category').id,'IIa — non-bleeding visible vessel');
    setValue(vm,childNamed(vm,a,'Biopsy taken?').id,'Yes');
    final containerA=childNamed(vm,a,'Container / label');
    expect(containerA.conditionalParentSectionId,childNamed(vm,a,'Biopsy taken?').id);
    expect(containerA.conditionalParentSectionId,isNot(childNamed(vm,b,'Biopsy taken?').id));
    setValue(vm,containerA.id,'A');
    final restored=ReportCodec.reportFromJson(ReportCodec.reportToJson(vm.doc));
    expect(value(sections(restored.roots).firstWhere((s)=>s.id==childNamed(vm,a,'Size').id)),'10');
    expect(sections(restored.roots).firstWhere((s)=>s.id=='stomach_findings').repeatableTemplates,hasLength(12));
    final ordered=findingsInAnatomicalOrder(vm.doc.roots);
    final group=sections(ordered).firstWhere((s)=>s.id=='stomach_findings');
    expect(group.children.whereType<SectionNode>().map((s)=>s.title).toList(),['Cardia','Body','Antrum']);
    expect(node(vm,'stomach_findings').children.first.id,a,reason:'PDF ordering must not mutate saved entry order');
    final out=Directory('build/ogd-qa')..createSync(recursive:true);
    const plan=PdfPlan(title:'Fictional OGD QA',inlineEnabled:false,pageOne:PageOnePlan(inlineImages:[]),finalContent:FinalContentPlan(spillInlineImages:[]),attachmentPages:[]);
    await File('${out.path}/different-findings.pdf').writeAsBytes(await PdfRendererService().generatePdfBytes(doc:vm.doc,plan:plan));
    setValue(vm,'stomach_status','Normal');
    await File('${out.path}/normal-after-abnormal.pdf').writeAsBytes(await PdfRendererService().generatePdfBytes(doc:vm.doc,plan:plan));
    setValue(vm,'stomach_status','Abnormal');
    vm.removeRepeatableFinding('stomach_findings',a);
    expect(value(childNamed(vm,b,'Size')),'20');
    expect(node(vm,'stomach_findings').children,hasLength(2));
    final template=vm.doc.roots.map((r)=>r.toTemplateNode(includeContent:false)).toList();
    expect(sections(template).firstWhere((s)=>s.id=='stomach_findings').children,isEmpty);
    vm.dispose();
  });

  test('numeric landmarks and lesion levels retain their values and units on save and PDF export', () async {
    final vm=editor();
    for (final id in ['landmark_gej','landmark_z_line','landmark_pinch']) {
      expect(node(vm,id).inputType,FieldInputType.numeric);
      expect(node(vm,id).unit,'cm from incisors');
      expect(value(node(vm,id)),isEmpty);
    }
    setValue(vm,'oesophagus_status','Abnormal');
    setValue(vm,'oesophagus_landmarks','Yes');
    setValue(vm,'landmark_gej','39.5');
    setValue(vm,'landmark_z_line','37.5');
    setValue(vm,'landmark_pinch','41');
    final ulcer=vm.addRepeatableFinding('oesophagus_findings','oesophagus_ulcer')!;
    final level=childNamed(vm,ulcer,'Level');
    expect(level.inputType,FieldInputType.numeric);
    expect(level.unit,'cm from incisors');
    setValue(vm,level.id,'32.5');
    setValue(vm,childNamed(vm,ulcer,'Size').id,'7');
    final count=childNamed(vm,ulcer,'Number at this location');
    expect(count.inputType,FieldInputType.numeric);
    expect(count.unit,isEmpty);
    setValue(vm,count.id,'2');
    final repo=ReportsRepository();
    await repo.saveReport(vm.doc);
    final reopened=await repo.loadReport(vm.doc.reportId);
    final gej=sections(reopened.roots).firstWhere((s)=>s.id=='landmark_gej');
    expect(value(gej),'39.5');
    expect(gej.unit,'cm from incisors');
    final out=Directory('build/ogd-qa')..createSync(recursive:true);
    const plan=PdfPlan(title:'Fictional landmark QA',inlineEnabled:false,pageOne:PageOnePlan(inlineImages:[]),finalContent:FinalContentPlan(spillInlineImages:[]),attachmentPages:[]);
    await File('${out.path}/landmarks.pdf').writeAsBytes(await PdfRendererService().generatePdfBytes(doc:reopened,plan:plan));
    setValue(vm,'oesophagus_landmarks','No');
    await File('${out.path}/hidden-landmarks.pdf').writeAsBytes(await PdfRendererService().generatePdfBytes(doc:vm.doc,plan:plan));
    vm.dispose();
  });

  testWidgets('real Report Editor selects one pathology and keeps separate repeated entries', (tester) async {
    // Readable visual evidence instead of Flutter's square-glyph test font.
    await tester.runAsync(() async {
      final font = FontLoader('OGD QA')..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      await font.load();
      final sdk = Platform.environment['FLUTTER_ROOT'];
      if (sdk != null) {
        final icons = File('$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
        if (icons.existsSync()) {
          final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
          await loader.load();
        }
      }
    });
    await tester.binding.setSurfaceSize(const Size(360,920));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final vm=editor();
    final boundary=GlobalKey();
    await tester.pumpWidget(ChangeNotifierProvider.value(value:vm,child:MaterialApp(
      theme:ThemeData(colorScheme:ColorScheme.fromSeed(seedColor:Colors.teal),useMaterial3:true,fontFamily:'OGD QA'),
      home:RepaintBoundary(key:boundary,child:const ReportEditorScreen()))));
    await tester.pumpAndSettle();
    Future<void> reveal(Finder finder) async { await tester.ensureVisible(finder); await tester.pumpAndSettle(); }
    Future<void> choose(String id,String option) async {
      if (id == 'oesophagus_landmarks') {
        final control = find.byKey(ValueKey('landmark-measurements-$id'));
        await reveal(control);
        if (value(node(vm, id)) != option) {
          await tester.tap(control); await tester.pumpAndSettle();
        }
        return;
      }
      final field=find.byKey(ValueKey('structured-field-$id'));
      await reveal(field);await tester.tap(field);await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip,option));await tester.pumpAndSettle();
    }
    Future<void> add(String container,String type) async {
      final action=find.byKey(ValueKey('add-finding-$container'));
      await reveal(action);await tester.tap(action);await tester.pumpAndSettle();
      final option=find.byKey(ValueKey('finding-type-$type'));
      await reveal(option);await tester.tap(option);await tester.pumpAndSettle();
    }
    Future<void> capture(String name) async { await tester.runAsync(() async {
      final image=await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio:1);
      final png=await image.toByteData(format:ui.ImageByteFormat.png);
      Directory('build/ogd-qa').createSync(recursive:true);
      await File('build/ogd-qa/$name.png').writeAsBytes(png!.buffer.asUint8List());
    }); }
    expect(find.text('Consent'), findsNothing);
    final details = find.byKey(const ValueKey('procedure-details-extra_details'));
    await reveal(details); await tester.tap(details); await tester.pumpAndSettle();
    await choose('consent', 'Obtained');
    await reveal(details); await tester.tap(details); await tester.pumpAndSettle();
    expect(find.text('Consent'), findsNothing);
    expect(value(node(vm, 'consent')), 'Obtained');
    expect(find.text('Preparation: 1 of 4 fields recorded'), findsOneWidget);
    final addMedication = find.byKey(const ValueKey('add-finding-medications'));
    await reveal(addMedication); await tester.tap(addMedication); await tester.pumpAndSettle();
    expect(find.text('Drug'), findsOneWidget);
    final medication = node(vm, 'medications').children.whereType<SectionNode>().single.id;
    final dose = childNamed(vm, medication, 'Dose');
    final doseInput = find.byKey(ValueKey('content-form-numeric-${dose.children.whereType<ContentNode>().first.id}'));
    await reveal(doseInput); await tester.enterText(doseInput, '2'); await tester.pumpAndSettle();
    await choose(childNamed(vm, medication, 'Dose unit').id, 'mg');
    await choose(childNamed(vm, medication, 'Route').id, 'IV');
    await reveal(find.text('Drug')); await capture('editor-medications');
    expect(find.text('GEJ (top of gastric folds)'),findsNothing);
    final landmarkControl = find.byKey(const ValueKey('landmark-measurements-oesophagus_landmarks'));
    final assessment = find.byKey(const ValueKey('structured-field-oesophagus_status'));
    await reveal(landmarkControl);
    expect(tester.getTopLeft(landmarkControl).dy, lessThan(tester.getTopLeft(assessment).dy));
    expect(value(node(vm, 'oesophagus_landmarks')), isEmpty,
      reason: 'Displaying the optional control must not record a clinical answer');
    await capture('editor-landmark-flow');
    await choose('oesophagus_landmarks','Yes');
    final gejInput=find.byKey(ValueKey('content-form-numeric-${node(vm,'landmark_gej').children.whereType<ContentNode>().first.id}'));
    await reveal(gejInput);await tester.enterText(gejInput,'39.5');await tester.pumpAndSettle();
    expect(find.text('cm from incisors'),findsNWidgets(3));
    await reveal(find.text('GEJ (top of gastric folds)'));
    await capture('editor-landmarks');
    await choose('oesophagus_landmarks','No');
    expect(find.text('GEJ (top of gastric folds)'),findsNothing);
    await choose('oesophagus_landmarks','Yes');
    expect(value(node(vm,'landmark_gej')),'39.5');
    await choose('oesophagus_status','Normal');
    expect(find.text('GEJ (top of gastric folds)'), findsOneWidget);
    await choose('oesophagus_status','Abnormal');
    expect(find.text('GEJ (top of gastric folds)'), findsOneWidget);
    await choose('oesophagus_status','Normal');
    await choose('extent','Second part of duodenum');
    expect(value(node(vm,'extent')),'Second part of duodenum');
    expect(find.byKey(const ValueKey('add-finding-stomach_findings')),findsNothing);
    await choose('stomach_status','Abnormal');
    expect(find.text('Bleeding stigmata / Forrest category'),findsNothing);
    await add('stomach_findings','stomach_ulcer');
    expect(find.text('Bleeding stigmata / Forrest category'),findsOneWidget);
    expect(find.text('Sarin type'),findsNothing);
    final first=node(vm,'stomach_findings').children.whereType<SectionNode>().single.id;
    final stomachAction = find.byKey(const ValueKey('add-finding-stomach_findings'));
    expect(stomachAction, findsOneWidget);
    expect(find.descendant(of: stomachAction, matching: find.text('Add another finding')), findsOneWidget);
    expect(tester.getTopLeft(stomachAction).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.byKey(ValueKey('finding-card-$first'))).dy));
    expect(tester.getTopLeft(find.byKey(ValueKey('toggle-finding-$first'))).dy,
      inInclusiveRange(0, 920), reason: 'Adding a finding brings its heading into view');
    await choose(childNamed(vm,first,'Location').id,'Antrum');
    final size=childNamed(vm,first,'Size');
    final input=find.byKey(ValueKey('content-form-${size.children.whereType<ContentNode>().first.id}'));
    // Numeric fields have their own stable key.
    final numeric=find.byKey(ValueKey('content-form-numeric-${size.children.whereType<ContentNode>().first.id}'));
    final target=input.evaluate().isNotEmpty ? input : numeric;
    await reveal(target);await tester.enterText(target,'10');await tester.pumpAndSettle();
    await add('stomach_findings','stomach_ulcer');
    final second=node(vm,'stomach_findings').children.whereType<SectionNode>().last.id;
    expect(find.text('Antrum · 10 mm'), findsOneWidget);
    expect(stomachAction, findsOneWidget);
    expect(tester.getTopLeft(stomachAction).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.byKey(ValueKey('finding-card-$second'))).dy));
    await choose(childNamed(vm,second,'Location').id,'Body');
    expect(value(childNamed(vm,first,'Size')),'10');
    expect(value(childNamed(vm,second,'Size')),isEmpty);
    await add('stomach_findings','stomach_polyp');
    expect(find.text('Morphology'),findsOneWidget);
    expect(find.text('Bleeding stigmata / Forrest category'),findsNothing,reason:'Previous ulcer cards are collapsed');
    await capture('editor-polyp');
    await reveal(stomachAction); await capture('editor-add-another');
    await choose('stomach_status','Normal');
    expect(find.byKey(const ValueKey('add-finding-stomach_findings')),findsNothing);
    expect(find.text('Morphology'),findsNothing);
    await choose('stomach_status','Abnormal');
    expect(node(vm,'stomach_findings').children,hasLength(3));
    for (final item in node(vm, 'stomach_findings').children.whereType<SectionNode>().toList()) {
      vm.removeRepeatableFinding('stomach_findings', item.id);
    }
    await tester.pumpAndSettle();
    expect(stomachAction, findsOneWidget);
    expect(find.descendant(of: stomachAction, matching: find.text('Add finding')), findsOneWidget);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    vm.dispose();
  });
}
