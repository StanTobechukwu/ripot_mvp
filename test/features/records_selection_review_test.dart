import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/features/records/data/records_repository.dart';
import 'package:ripot/features/records/ui/records_field_picker.dart';
import 'package:ripot/features/reports/data/templates_repository.dart';
import 'package:ripot/features/reports/domain/models/template_doc.dart';
import 'package:ripot/features/reports/domain/models/report_doc.dart';
import 'package:ripot/features/reports/domain/models/nodes.dart';

ReportDoc report() => ReportDoc(
  reportId: 'r1', sourceTemplateId: 't1',
  createdAtIso: '2026-09-17T12:00:00Z', updatedAtIso: '2026-09-17T12:00:00Z',
  roots: const [SectionNode(id: 'ef', title: 'Ejection fraction', addToRecords: true,
    children: [ContentNode(id: 'value', text: '55')])],
);

class MemoryTemplates extends TemplatesRepository {
  TemplateDoc template = TemplateDoc(
    templateId: 't1', name: 'Echo', updatedAt: DateTime(2026),
    recordsConfigured: true,
    roots: const [SectionNode(id: 'ef', title: 'Ejection fraction', addToRecords: true),
      SectionNode(id: 'future', title: 'New template field', addToRecords: true)],
  );
  int saves = 0;
  @override
  Future<TemplateDoc> loadTemplate(String id) async => template;
  @override
  Future<void> saveTemplate(TemplateDoc value) async { template = value; saves++; }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final hasRecord in [false, true]) {
    testWidgets('picker opens with configured template, existing record=$hasRecord', (tester) async {
      final records = RecordsRepository();
      final templates = MemoryTemplates();
      if (hasRecord) await records.saveRecord(await records.buildDraftForReport(report()));
      ReportDoc? selected;
      await tester.pumpWidget(MultiProvider(
        providers: [Provider<RecordsRepository>.value(value: records),
          Provider<TemplatesRepository>.value(value: templates)],
        child: MaterialApp(home: Builder(builder: (context) => Scaffold(
          body: TextButton(onPressed: () async {
            selected = await prepareReportRecords(context, report());
          }, child: const Text('Review'))))),
      ));
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.text('Choose Records fields'), findsOneWidget);
      expect(find.text('New template field'), findsNothing);
      final field = find.widgetWithText(CheckboxListTile, 'Ejection fraction');
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.tap(find.text('Use these fields'));
      await tester.pumpAndSettle();
      expect(selected!.roots.single.addToRecords, isFalse);
      expect(templates.saves, 0);
      if (hasRecord) {
        final draft = await records.buildDraftForReport(selected!, applyFieldSelection: true);
        expect(draft.values.containsKey('template_t1_section_ef'), isFalse);
        // Preparing/cancelling an editor must not mutate the saved record.
        expect((await records.loadByReportId('r1'))!.values['template_t1_section_ef'], '55');
      }
    });
  }
  testWidgets('remember updates flags without replacing newer template fields', (tester) async {
    final records = RecordsRepository();
    final templates = MemoryTemplates();
    await tester.pumpWidget(MultiProvider(
      providers: [Provider<RecordsRepository>.value(value: records),
        Provider<TemplatesRepository>.value(value: templates)],
      child: MaterialApp(home: Builder(builder: (context) => Scaffold(
        body: TextButton(onPressed: () async {
          await prepareReportRecords(context, report());
        }, child: const Text('Review'))))),
    ));
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Remember for this template'));
    final field = find.widgetWithText(CheckboxListTile, 'Ejection fraction');
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.tap(find.text('Use these fields'));
    await tester.pumpAndSettle();
    expect(templates.saves, 1);
    expect(templates.template.roots.first.addToRecords, isFalse);
    expect(templates.template.roots.last.id, 'future');
    expect(templates.template.roots.last.addToRecords, isTrue);
  });
  test('reselecting preserves corrected values and unrelated extra fields', () async {
    final repo = RecordsRepository();
    final original = await repo.buildDraftForReport(report());
    await repo.saveRecord(original.copyWith(values: {
      ...original.values, 'template_t1_section_ef': '60', 'custom_notes': 'Keep me',
    }));
    final draft = await repo.buildDraftForReport(report(), applyFieldSelection: true);
    expect(draft.values['template_t1_section_ef'], '60');
    expect(draft.values['custom_notes'], 'Keep me');
  });
}
