import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/features/records/data/records_repository.dart';
import 'package:ripot/features/records/domain/record_models.dart';
import 'package:ripot/features/registry/data/registry_repository.dart';
import 'package:ripot/features/registry/domain/registry_table.dart';
import 'package:ripot/features/registry/ui/registry_screen.dart';

const height = RecordFieldDef(
  key: 'height',
  label: 'Height',
  hint: '',
  unit: 'cm',
  inputType: RecordInputType.numeric,
);
const weight = RecordFieldDef(
  key: 'weight',
  label: 'Weight',
  hint: '',
  unit: 'kg',
  inputType: RecordInputType.numeric,
);
const sex = RecordFieldDef(
  key: 'sex',
  label: 'Sex',
  hint: '',
  patientDetail: true,
  inputType: RecordInputType.singleSelect,
  options: ['Female', 'Male'],
);
const patient = RegistryPatient(
  id: 'p',
  name: 'Demo patient',
  reference: 'DEMO-1',
  facility: 'Demo clinic',
  registryIds: ['r', 'other'],
);
const registry = RecordRegistry(
  registryId: 'r',
  title: 'Demo registry',
  createdAtIso: '2026-09-28',
  fields: [height, weight, sex],
);

RegistryUpdate entry(
  String id, {
  RecordFieldDef field = height,
  String value = '170',
  int day = 1,
  String registryId = 'r',
}) => RegistryUpdate(
  id: id,
  registryId: registryId,
  patientId: patient.id,
  patientName: patient.name,
  observedAt: DateTime(2026, 9, day),
  recordedAt: DateTime(2026, 9, day),
  patientDetails: field.patientDetail,
  sourceReportId: field.patientDetail ? '' : 'report-$id',
  values: {field.key: value},
  definitions: {field.key: field},
);

Future<void> seed(List<RegistryUpdate> updates) => RegistryRepository()
    .importCopy(RegistryData(patients: [patient], updates: updates));

Future<void> openEditor(
  WidgetTester tester,
  RegistryUpdateScreen screen,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => screen),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'renaming and regrouping keeps latest values under the current label',
    () {
      final old = entry('old');
      final renamed = height.copyWith(
        label: 'Stature',
        groupName: 'Measurements',
      );
      final table = RegistryTableData.build(
        registry.copyWith(fields: [renamed]),
        RegistryData(patients: [patient], updates: [old]),
      );
      expect(table.headers.length, 5);
      expect(table.headers.last, contains('Stature'));
      expect(table.rows.single.last, '170\n2026-09-01');
      expect(old.definitions['height']!.label, 'Height');
      expect(table.editableCell(0, 4)!.correction, false);
    },
  );

  test('legacy values stay visible without assuming their missing units', () {
    final legacy = RegistryUpdate(
      id: 'old',
      registryId: 'r',
      patientId: patient.id,
      patientName: patient.name,
      observedAt: DateTime(2026, 9, 1),
      recordedAt: DateTime(2026, 9, 1),
      values: const {'height': '1.7'},
      definitions: const {},
    );
    final table = RegistryTableData.build(
      registry,
      RegistryData(patients: [patient], updates: [legacy]),
    );
    final column = table.headers.indexWhere(
      (h) => h.contains('settings unavailable'),
    );
    expect(table.rows.single[column], '1.7\n2026-09-01');
    expect(table.editableCell(0, column), isNull);
    final currentColumn = table.headers.indexWhere((h) => h.contains('(cm)'));
    expect(table.rows.single[currentColumn], '');
  });

  test(
    'legacy storage without definitions loads without rewriting its values',
    () async {
      final old = entry('old').toJson()..remove('definitions');
      SharedPreferences.setMockInitialValues({
        RegistryRepository.storageKey: jsonEncode({
          'version': 1,
          'patients': [patient.toJson()],
          'updates': [old],
        }),
      });
      final data = await RegistryRepository().load();
      expect(data.updates.single.values, {'height': '170'});
      expect(data.updates.single.definitions, isEmpty);
      final table = RegistryTableData.build(registry, data);
      expect(table.rows.single, contains('170\n2026-09-01'));
    },
  );

  test(
    'historical units and field types offer correction, never reinterpretation',
    () {
      final old = entry(
        'old',
        field: height.copyWith(unit: 'm'),
        value: '1.7',
      );
      final data = RegistryData(patients: [patient], updates: [old]);
      final table = RegistryTableData.build(registry, data);
      final historicColumn = table.headers.indexWhere((h) => h.contains('(m)'));
      final cell = table.editableCell(0, historicColumn)!;
      expect(cell.correction, true);
      expect(cell.update!.id, old.id);
      expect(cell.field.unit, 'm');
      final history = RegistryTableData.build(registry, data, allUpdates: true);
      final emptyColumn = history.headers.indexWhere((h) => h.contains('(kg)'));
      expect(history.editableCell(0, emptyColumn), isNull);
      final changedType = RegistryTableData.build(
        registry.copyWith(
          fields: [height.copyWith(inputType: RecordInputType.freeText)],
        ),
        RegistryData(patients: [patient], updates: [entry('numeric')]),
      );
      expect(changedType.headers.length, 6);
    },
  );

  test(
    'identity and static detail save atomically, retaining enrollments and snapshots',
    () async {
      final old = entry('old');
      await seed([old]);
      final repo = RegistryRepository();
      await repo.editPatient(
        expected: patient,
        name: 'Updated demo',
        reference: 'DEMO-2',
        facility: 'Second clinic',
        details: entry('sex', field: sex, value: 'Female'),
      );
      final data = await repo.load();
      expect(data.patients.single.id, patient.id);
      expect(data.patients.single.registryIds, ['r', 'other']);
      expect(data.patients.single.name, 'Updated demo');
      expect(jsonEncode(data.updates.first.toJson()), jsonEncode(old.toJson()));
      expect(data.updates.last.patientDetails, true);
      await expectLater(
        repo.editPatient(
          expected: patient,
          name: 'Stale name',
          reference: 'DEMO-1',
          facility: 'Demo clinic',
        ),
        throwsStateError,
      );
      expect((await repo.load()).patients.single.name, 'Updated demo');
    },
  );

  test(
    'duplicate identity or invalid detail leaves both identity and values unchanged',
    () async {
      await seed([]);
      final repo = RegistryRepository();
      await repo.addPatient(
        name: 'Other demo',
        reference: 'DEMO-2',
        facility: 'Other',
        registryId: 'r',
      );
      await expectLater(
        repo.editPatient(
          expected: patient,
          name: 'Changed',
          reference: 'demo-2',
          facility: 'other',
          details: entry('sex', field: sex, value: 'Female'),
        ),
        throwsStateError,
      );
      await expectLater(
        repo.editPatient(
          expected: patient,
          name: 'Changed',
          reference: 'DEMO-3',
          facility: '',
          details: entry(
            'bad',
            field: height.copyWith(patientDetail: true),
            value: 'not a number',
          ),
        ),
        throwsArgumentError,
      );
      final data = await repo.load();
      expect(data.patients.first.name, patient.name);
      expect(data.updates, isEmpty);
    },
  );

  test(
    'a restored copy with the same identifier does not block a name-only edit',
    () async {
      await RegistryRepository().importCopy(
        const RegistryData(
          patients: [
            patient,
            RegistryPatient(
              id: 'restored-p',
              name: 'Restored demo',
              reference: 'DEMO-1',
              facility: 'Demo clinic',
              registryIds: ['restored-r'],
            ),
          ],
        ),
      );
      await RegistryRepository().editPatient(
        expected: patient,
        name: 'New demo name',
        reference: patient.reference,
        facility: patient.facility,
      );
      final data = await RegistryRepository().load();
      expect(data.patients.first.name, 'New demo name');
      expect(data.patients.last.name, 'Restored demo');
    },
  );

  test(
    'explicit correction preserves source, units, order and unrelated entries; stale edits fail',
    () async {
      final old = entry(
        'old',
        field: height.copyWith(unit: 'm'),
        value: '1.7',
      );
      final next = entry('next', day: 2);
      final other = entry('other', registryId: 'other');
      await seed([old, next, other]);
      final repo = RegistryRepository();
      await repo.correctUpdate(
        expected: old,
        values: {'height': '1.75'},
        observedAt: DateTime(2026, 9, 1),
      );
      final data = await repo.load();
      expect(data.updates.length, 3);
      expect(data.updates.first.id, old.id);
      expect(data.updates.first.sourceReportId, old.sourceReportId);
      expect(data.updates.first.recordedAt, old.recordedAt);
      expect(data.updates.first.definitions['height']!.unit, 'm');
      expect(data.updates.first.values['height'], '1.75');
      expect(jsonEncode(data.updates[1].toJson()), jsonEncode(next.toJson()));
      expect(jsonEncode(data.updates[2].toJson()), jsonEncode(other.toJson()));
      await expectLater(
        repo.correctUpdate(
          expected: old,
          values: {'height': '1.8'},
          observedAt: old.observedAt,
        ),
        throwsStateError,
      );
      await expectLater(
        repo.correctUpdate(
          expected: data.updates.first,
          values: {'height': 'NaN'},
          observedAt: old.observedAt,
        ),
        throwsArgumentError,
      );
      expect((await repo.load()).updates.first.values['height'], '1.75');
    },
  );

  testWidgets(
    'quick entry validates and saves several fields as one new observation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final old = entry('old');
      await seed([old]);
      await openEditor(
        tester,
        const RegistryUpdateScreen(
          registry: registry,
          patient: patient,
          quickEntry: true,
          initialFieldKey: 'height',
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Height'),
        'invalid',
      );
      await tester.tap(find.text('Next field'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid number'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Height'),
        '175',
      );
      await tester.tap(find.text('Next field'));
      await tester.pumpAndSettle();
      expect(find.text('Sex'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Weight'),
        '68',
      );
      await tester.tap(find.text('Save update'));
      await tester.pumpAndSettle();
      final data = await RegistryRepository().load();
      expect(data.updates.length, 2);
      expect(jsonEncode(data.updates.first.toJson()), jsonEncode(old.toJson()));
      expect(data.updates.last.values, {'height': '175', 'weight': '68'});
      expect(data.updates.last.sourceReportId, '');
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelling quick entry or correction writes nothing', (
    tester,
  ) async {
    final old = entry('old');
    await seed([old]);
    for (final correction in [null, old]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await openEditor(
        tester,
        RegistryUpdateScreen(
          registry: registry,
          patient: patient,
          quickEntry: true,
          correction: correction,
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Height'),
        '180',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      final data = await RegistryRepository().load();
      expect(
        jsonEncode(data.updates.single.toJson()),
        jsonEncode(old.toJson()),
      );
    }
  });

  testWidgets(
    'correction editor uses original units and changes only that entry',
    (tester) async {
      final old = entry(
        'old',
        field: height.copyWith(unit: 'm'),
        value: '1.7',
      );
      final newer = entry('new', day: 2);
      await seed([old, newer]);
      await openEditor(
        tester,
        RegistryUpdateScreen(
          registry: registry,
          patient: patient,
          correction: old,
          quickEntry: true,
        ),
      );
      expect(find.text('Correct this entry'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '1.7',
      );
      expect(find.text('m'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '1.72');
      await tester.tap(find.text('Save correction'));
      await tester.pumpAndSettle();
      final data = await RegistryRepository().load();
      expect(data.updates.length, 2);
      expect(data.updates.first.values['height'], '1.72');
      expect(data.updates.first.definitions['height']!.unit, 'm');
      expect(
        jsonEncode(data.updates.last.toJson()),
        jsonEncode(newer.toJson()),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'static quick entry can clear a value without resurrecting earlier details',
    (tester) async {
      final original = entry('sex', field: sex, value: 'Female');
      await seed([original]);
      await openEditor(
        tester,
        RegistryUpdateScreen(
          registry: registry,
          patient: patient,
          patientDetails: true,
          quickEntry: true,
          previousUpdates: [original],
        ),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not recorded').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save patient details'));
      await tester.pumpAndSettle();
      final data = await RegistryRepository().load();
      expect(data.updates.length, 2);
      expect(data.updates.last.values, {'sex': ''});
      final table = RegistryTableData.build(registry, data);
      expect(
        table.rows.single[table.headers.indexWhere((h) => h.startsWith('Sex'))],
        '',
      );
    },
  );

  testWidgets(
    'mobile table tap opens a sheet and Add offers patients and fields',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final records = RecordsRepository();
      final created = await records.createRegistry(title: 'Demo registry');
      await records.saveRegistryFields(created.registryId, [height, weight]);
      final current = (await records.loadRegistries()).single;
      await RegistryRepository().addPatient(
        name: 'Demo patient',
        registryId: current.registryId,
      );
      await tester.pumpWidget(
        Provider.value(
          value: records,
          child: MaterialApp(home: RegistryPatientsScreen(registry: current)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Add patient'), findsOneWidget);
      await tester.tap(find.text('Add field'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Field name'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Table view'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('registry-cell-0-4')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Height'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Height'),
        '165',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(
        tester
            .getBottomLeft(find.widgetWithText(FilledButton, 'Save update'))
            .dy,
        lessThanOrEqualTo(544),
      );
      await tester.tap(find.text('Save update'));
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect((await RegistryRepository().load()).updates.single.values, {
        'height': '165',
      });
      expect(find.textContaining('165\n'), findsOneWidget);
      await tester.tap(find.byTooltip('Height field options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit field'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Field name'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'patient menus and compact history support a small screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final records = RecordsRepository();
      await seed([entry('height'), entry('sex', field: sex, value: 'Female')]);
      await tester.pumpWidget(
        Provider.value(
          value: records,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!,
            ),
            home: const RegistryPatientScreen(
              registry: registry,
              patient: patient,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(patient.name), findsOneWidget);
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(find.text('Add dated update'), findsOneWidget);
      await tester.ensureVisible(find.text('Edit patient details'));
      await tester.tap(find.text('Edit patient details'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('patient-name')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
