import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/features/registry/data/registry_repository.dart';
import 'package:ripot/features/registry/ui/registry_screen.dart';
import 'package:ripot/features/records/data/records_repository.dart';
import 'package:ripot/features/records/domain/record_models.dart';
import 'package:ripot/features/reports/domain/models/report_doc.dart';
import 'package:ripot/features/reports/domain/models/nodes.dart';

void main() {
  testWidgets(
    'import keeps the source unit when a registry field has changed',
    (tester) async {
      const original = RecordFieldDef(
        key: 'hb',
        label: 'Haemoglobin',
        hint: '',
        inputType: RecordInputType.numeric,
        unit: 'g/dL',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RegistryUpdateScreen(
            registry: RecordRegistry(
              registryId: 'r',
              title: 'Clinic',
              createdAtIso: '2026-09-01',
              fields: [original.copyWith(unit: 'g/L')],
            ),
            patient: const RegistryPatient(id: 'p', name: 'Patient'),
            source: const RecordEntry(
              recordEntryId: 'e',
              linkedReportId: 'report',
              createdAtIso: '2026-09-01',
              updatedAtIso: '2026-09-01',
              values: {'hb': '12'},
              fieldDefinitions: {'hb': original},
            ),
          ),
        ),
      );
      expect(find.text('g/dL'), findsOneWidget);
      expect(find.text('g/L'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const hb = RecordFieldDef(
    key: 'hb',
    label: 'Haemoglobin',
    hint: '',
    inputType: RecordInputType.numeric,
    unit: 'g/dL',
    groupName: 'Full blood count',
  );
  RegistryUpdate update(
    RegistryPatient p,
    String id, {
    String value = '12',
    String report = '',
    RecordFieldDef field = hb,
  }) => RegistryUpdate(
    id: id,
    registryId: 'r',
    patientId: p.id,
    patientName: p.name,
    observedAt: DateTime(2026, 9, 1),
    recordedAt: DateTime(2026, 9, 2),
    sourceReportId: report,
    values: {field.key: value},
    definitions: {field.key: field},
  );

  test(
    'same name remains separate; identifier and facility prevent accidental duplicates',
    () async {
      final repo = RegistryRepository();
      final a = await repo.addPatient(
        name: 'Same name',
        reference: '1',
        facility: 'A',
        registryId: 'r',
      );
      final b = await repo.addPatient(
        name: 'Same name',
        reference: '1',
        facility: 'B',
        registryId: 'r',
      );
      expect(a.id, isNot(b.id));
      await expectLater(
        repo.addPatient(
          name: 'Other spelling',
          reference: '1',
          facility: 'A',
          registryId: 'r',
        ),
        throwsStateError,
      );
      await repo.enroll(a.id, 'other');
      expect(
        (await repo.load()).patients.first.registryIds,
        containsAll(['r', 'other']),
      );
    },
  );
  test(
    'concurrent updates survive and historic units and groups remain unchanged',
    () async {
      final repo = RegistryRepository();
      final p = await repo.addPatient(name: 'Patient', registryId: 'r');
      await Future.wait([
        repo.addUpdate(update(p, 'one')),
        RegistryRepository().addUpdate(
          update(
            p,
            'two',
            value: '120',
            field: hb.copyWith(unit: 'g/L'),
          ),
        ),
      ]);
      final stored = await RegistryRepository().load();
      expect(stored.updates, hasLength(2));
      expect(stored.updates.first.definitions['hb']!.unit, 'g/dL');
      expect(stored.updates.last.definitions['hb']!.unit, 'g/L');
      expect(
        stored.updates.first.definitions['hb']!.groupName,
        'Full blood count',
      );
      await repo.addUpdate(update(p, 'one'));
      expect((await repo.load()).updates, hasLength(2));
    },
  );
  test(
    'report cannot be duplicated into another patient in the same registry',
    () async {
      final repo = RegistryRepository();
      final a = await repo.addPatient(name: 'A', registryId: 'r');
      final b = await repo.addPatient(name: 'B', registryId: 'r');
      await repo.addUpdate(update(a, 'one', report: 'rpt-1'));
      await expectLater(
        repo.addUpdate(update(b, 'two', report: 'rpt-1')),
        throwsStateError,
      );
      expect((await repo.load()).updates, hasLength(1));
    },
  );
  test(
    'numeric validation rejects nonfinite and nonnumeric input without saving',
    () async {
      final repo = RegistryRepository();
      final p = await repo.addPatient(name: 'A', registryId: 'r');
      for (final v in ['NaN', 'Infinity', 'abc']) {
        await expectLater(
          repo.addUpdate(update(p, v, value: v)),
          throwsArgumentError,
        );
      }
      expect((await repo.load()).updates, isEmpty);
    },
  );
  test('corrupt storage is not overwritten with an empty registry', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(RegistryRepository.storageKey, 'corrupt');
    await expectLater(
      RegistryRepository().addPatient(name: 'A', registryId: 'r'),
      throwsFormatException,
    );
    expect(prefs.getString(RegistryRepository.storageKey), 'corrupt');
  });
  test(
    'report fields can be imported without selecting them for Records',
    () async {
      final report = ReportDoc(
        reportId: 'rpt',
        createdAtIso: '2026-09-01',
        updatedAtIso: '2026-09-01',
        sourceTemplateId: 'template-A',
        roots: const [
          SectionNode(
            id: 'measurement',
            title: 'Value',
            inputType: FieldInputType.numeric,
            unit: 'mm',
            addToRecords: false,
            children: [ContentNode(id: 'value', text: '5')],
          ),
        ],
      );
      final repo = RecordsRepository();
      expect(
        (await repo.buildDraftForReport(report)).values.keys,
        isNot(contains('template_template-A_section_measurement')),
      );
      final imported = repo.registrySourceForReport(report);
      expect(imported.values['template_template-A_section_measurement'], '5');
      expect(
        imported
            .fieldDefinitions['template_template-A_section_measurement']!
            .unit,
        'mm',
      );
      expect(report.roots.first.addToRecords, isFalse);
      expect(await repo.listRecords(), isEmpty);
    },
  );
  test(
    'record correction and its original snapshot survive opening from report',
    () async {
      final report = ReportDoc(
        reportId: 'rpt',
        createdAtIso: '2026-09-01',
        updatedAtIso: '2026-09-01',
        roots: const [
          SectionNode(
            id: 'dx',
            title: 'Diagnosis',
            addToRecords: true,
            children: [ContentNode(id: 'v', text: 'Original')],
          ),
        ],
      );
      final repo = RecordsRepository();
      final original = await repo.buildDraftForReport(report);
      await repo.saveRecord(
        original.copyWith(
          values: {...original.values, 'diagnosis': 'Correction'},
        ),
      );
      final reopened = await repo.buildDraftForReport(report);
      expect(reopened.values['diagnosis'], 'Correction');
      expect(reopened.originalReportValues['diagnosis'], 'Original');
    },
  );
  testWidgets('grouped numeric update can be saved on a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = RegistryRepository();
    final p = await repo.addPatient(name: 'A', registryId: 'r');
    await tester.pumpWidget(
      MaterialApp(
        home: RegistryUpdateScreen(
          registry: const RecordRegistry(
            registryId: 'r',
            title: 'Clinic',
            createdAtIso: '2026-09-01',
            fields: [hb],
          ),
          patient: p,
        ),
      ),
    );
    expect(find.text('Full blood count'), findsOneWidget);
    expect(find.text('g/dL'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '13.5');
    await tester.tap(find.text('Save update'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect((await repo.load()).updates.single.values['hb'], '13.5');
  });
  testWidgets('registry list uses existing Records registry definitions', (
    tester,
  ) async {
    final records = RecordsRepository();
    await records.createRegistry(title: 'Existing clinic');
    await tester.pumpWidget(
      Provider.value(
        value: records,
        child: const MaterialApp(home: RegistryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Existing clinic'), findsOneWidget);
  });
}
