import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/features/registry/data/registry_repository.dart';
import 'package:ripot/features/registry/domain/registry_table.dart';
import 'package:ripot/features/registry/services/registry_backup.dart';
import 'package:ripot/features/registry/ui/registry_screen.dart';
import 'package:ripot/features/records/data/records_repository.dart';
import 'package:ripot/features/records/domain/record_models.dart';

const sex = RecordFieldDef(key: 'sex', label: 'Sex', hint: '', patientDetail: true,
  inputType: RecordInputType.singleSelect, options: ['Female', 'Male']);
const weight = RecordFieldDef(key: 'weight', label: 'Weight', hint: '', unit: 'kg',
  inputType: RecordInputType.numeric);
const registry = RecordRegistry(registryId: 'r', title: 'Clinic', createdAtIso: '2026', fields: [sex, weight]);
const patient = RegistryPatient(id: 'p', name: 'Test patient', registryIds: ['r']);
RegistryUpdate entry(String id, RecordFieldDef field, String value, int day) => RegistryUpdate(
  id: id, registryId: 'r', patientId: 'p', patientName: 'Test patient',
  observedAt: DateTime(2026, 9, day), recordedAt: DateTime(2026, 9, day),
  patientDetails: field.patientDetail, values: {field.key: value}, definitions: {field.key: field});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('legacy storage loads without reclassifying any existing field', () async {
    final old = entry('old', weight, '65', 1).toJson()..remove('patientDetails');
    SharedPreferences.setMockInitialValues({RegistryRepository.storageKey: jsonEncode({
      'version': 1, 'patients': [patient.toJson()], 'updates': [old],
    })});
    final repo = RegistryRepository();
    expect((await repo.load()).updates.single.patientDetails, false);
    await repo.addUpdate(entry('profile', sex, 'Female', 2));
    expect((await repo.load()).updates.length, 2);
    final raw = (await SharedPreferences.getInstance()).getString(RegistryRepository.storageKey)!;
    expect(jsonDecode(raw)['version'], 2);
  });
  test('overview uses current profile; history never carries measurements forward', () {
    final data = RegistryData(patients: [patient], updates: [
      entry('s', sex, 'Female', 1), entry('w', weight, '65', 2),
      entry('clear', sex, '', 3),
    ]);
    final overview = RegistryTableData.build(registry, data);
    final sexColumn = overview.headers.indexWhere((h) => h.startsWith('Sex'));
    expect(overview.rows.single[sexColumn], '');
    expect(overview.rows.single, contains('65\n2026-09-02'));
    final history = RegistryTableData.build(registry, data, allUpdates: true);
    expect(history.rows.length, 3);
    final weightColumn = history.headers.indexWhere((h) => h.startsWith('Weight'));
    expect(history.rows.where((r) => r[weightColumn] == '65').length, 1);
    expect(history.toCsv(), contains('Patient details'));
  });
  test('reclassification preserves the historical dated column', () {
    final oldSex = sex.copyWith(patientDetail: false);
    final data = RegistryData(patients: [patient], updates: [
      entry('old', oldSex, 'Female', 1), entry('new', sex, 'Female', 2),
    ]);
    final table = RegistryTableData.build(registry, data);
    expect(table.headers.where((h) => h.startsWith('Sex')).length, 2);
    expect(data.updates.first.definitions['sex']!.patientDetail, false);
  });
  test('backup restores both scopes and profile revisions without changing originals', () async {
    final repo = RegistryRepository();
    await repo.importCopy(RegistryData(patients: [patient], updates: [entry('s', sex, 'Male', 1)]));
    final snapshot = await RegistrySnapshot.capture(registry);
    expect(snapshot.toJson()['version'], 3);
    final restored = await RegistrySnapshot.parse(snapshot.toJson()).restoreCopy(RecordsRepository());
    final data = await repo.load();
    expect(data.updates.length, 2);
    final copy = data.updates.singleWhere((u) => u.registryId == restored.registryId);
    expect(copy.patientDetails, true);
    expect(copy.definitions['sex']!.patientDetail, true);
    expect(copy.values['sex'], 'Male');
    expect(copy.patientId, isNot('p'));
  });
  testWidgets('dated editor excludes patient details and profile editor restores its value', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RegistryUpdateScreen(registry: registry, patient: patient)));
    expect(find.text('Weight'), findsOneWidget);
    expect(find.text('Sex'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(home: RegistryUpdateScreen(registry: registry, patient: patient,
      patientDetails: true, previousUpdates: [entry('s', sex, 'Female', 1)])));
    expect(find.text('Sex'), findsOneWidget);
    expect(find.text('Weight'), findsNothing);
    expect(find.text('Female'), findsOneWidget);
    expect(find.text('Date of observation'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
