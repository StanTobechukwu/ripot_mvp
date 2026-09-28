import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/features/registry/data/registry_repository.dart';
import 'package:ripot/features/registry/domain/registry_table.dart';
import 'package:ripot/features/registry/services/registry_backup.dart';
import 'package:ripot/features/registry/services/registry_backup_cipher.dart';
import 'package:ripot/features/registry/ui/registry_screen.dart';
import 'package:ripot/features/registry/ui/registry_tools.dart';
import 'package:ripot/features/records/data/records_repository.dart';
import 'package:ripot/features/records/domain/record_models.dart';

const field = RecordFieldDef(key:'hb',label:'Haemoglobin',hint:'',unit:'g/dL',groupName:'Blood count',inputType:RecordInputType.numeric);
RegistryUpdate observation(String id, String registryId, String patientId, {String value='12', String unit='g/dL', int day=1}) => RegistryUpdate(
  id:id,registryId:registryId,patientId:patientId,patientName:'Patient',observedAt:DateTime(2026,9,day),recordedAt:DateTime(2026,9,day),
  values:{'hb':value},definitions:{'hb':field.copyWith(unit:unit)},sourceReportId:'report-$id');

void main() {
  setUp(()=>SharedPreferences.setMockInitialValues({}));
  testWidgets('report import creates a patient only after review and save', (tester) async {
    final records = RecordsRepository();
    final registry = await records.createRegistry(title: 'Clinic');
    final source = RecordEntry(recordEntryId: 'e', linkedReportId: 'report-import',
      createdAtIso: '2026-09-14', updatedAtIso: '2026-09-14',
      values: {RecordFieldCatalog.subjectName.key: 'New patient', 'hb':'12'},
      fieldDefinitions: {'hb': field});
    await tester.pumpWidget(Provider.value(value: records, child: MaterialApp(
      home: RegistryPatientsScreen(registry: registry, source: source))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create patient from report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review values'));
    await tester.pumpAndSettle();
    expect((await RegistryRepository().load()).patients, isEmpty);
    await tester.tap(find.text('Include Haemoglobin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save update'));
    await tester.pumpAndSettle();
    final data = await RegistryRepository().load();
    expect(data.patients.single.name, 'New patient');
    expect(data.updates.single.sourceReportId, 'report-import');
    expect(find.text('Open source report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('removal affects only selected registry; deleting observation keeps patient',() async {
    final repo=RegistryRepository();
    final p=await repo.addPatient(name:'Patient',registryId:'a');
    await repo.enroll(p.id,'b');
    await repo.addUpdate(observation('one','a',p.id));
    await repo.addUpdate(observation('two','b',p.id));
    await repo.deleteUpdate('a','one');
    expect((await repo.load()).patients.single.id,p.id);
    await repo.addUpdate(observation('three','a',p.id));
    await repo.removePatient('a',p.id);
    final data=await repo.load();
    expect(data.patients.single.registryIds,['b']);
    expect(data.updates.single.registryId,'b');
    await repo.removePatient('b',p.id);
    expect((await repo.load()).patients,isEmpty);
  });
  test('new patient and report values save atomically',() async {
    final repo=RegistryRepository();
    const p=RegistryPatient(id:'new',name:'New patient',registryIds:['a']);
    await expectLater(repo.addUpdate(observation('bad','a','new',value:'invalid'),newPatient:p),throwsArgumentError);
    expect((await repo.load()).patients,isEmpty);
    await repo.addUpdate(observation('valid','a','new'),newPatient:p);
    final data=await repo.load();
    expect(data.patients.single.id,'new');
    expect(data.updates.single.sourceReportId,'report-valid');
  });
  test('latest table keeps dates and units separate; history keeps every update',() {
    const r=RecordRegistry(registryId:'a',title:'Clinic',createdAtIso:'2026',fields:[field]);
    const p=RegistryPatient(id:'p',name:'Patient',registryIds:['a']);
    final data=RegistryData(patients:[p],updates:[observation('one','a','p'),observation('two','a','p',unit:'g/L',value:'125',day:2)]);
    final overview=RegistryTableData.build(r,data);
    expect(overview.rows.single,contains('12\n2026-09-01'));
    expect(overview.rows.single,contains('125\n2026-09-02'));
    expect(overview.headers.where((h)=>h.contains('Haemoglobin')).length,2);
    expect(RegistryTableData.build(r,data,patientId:'p').rows.length,2);
    expect(const RegistryTableData(['Name'],[['=SUM(1,2)']],['p']).toCsv(),contains("'=SUM"));
  });
  test('backup round trip preserves snapshots and restores a separate linked copy',() async {
    final records=RecordsRepository();
    final r=await records.createRegistry(title:'Clinic');
    await records.saveRegistryFields(r.registryId,[field]);
    final repo=RegistryRepository();
    final p=await repo.addPatient(name:'Patient',reference:'123',registryId:r.registryId);
    await repo.addUpdate(observation('one',r.registryId,p.id));
    final snapshot=await RegistrySnapshot.capture((await records.loadRegistries()).single);
    final encoded=await RegistryBackupCipher.encrypt(snapshot.toJson(),'correct passphrase');
    await expectLater(RegistryBackupCipher.decrypt(encoded,'incorrect passphrase'),throwsA(anything));
    final decoded=RegistrySnapshot.parse(await RegistryBackupCipher.decrypt(encoded,'correct passphrase'));
    expect(jsonEncode(decoded.toJson()),jsonEncode(snapshot.toJson()));
    final restored=await decoded.restoreCopy(records);
    final data=await repo.load();
    expect(restored.registryId,isNot(r.registryId));
    expect(data.updates.length,2);
    final copy=data.updates.firstWhere((u)=>u.registryId == restored.registryId);
    expect(copy.patientId,isNot(p.id));
    expect(copy.sourceReportId,'report-one');
    expect(copy.definitions['hb']!.unit,'g/dL');
    expect(data.patients.firstWhere((p)=>p.id==copy.patientId).reference,'123');
    final bad=decoded.toJson();bad['patients']=[];
    expect(()=>RegistrySnapshot.parse(bad),throwsFormatException);
  }, timeout: const Timeout(Duration(minutes:2)));

  testWidgets('patient summary, history table and removal confirmation', (tester) async {
    final records=RecordsRepository();final r=await records.createRegistry(title:'hbv');
    final repo=RegistryRepository();final p=await repo.addPatient(name:'Patient',facility:'NAUTH',registryId:r.registryId);
    await repo.addUpdate(observation('one',r.registryId,p.id));
    await tester.pumpWidget(Provider.value(value:records,child:MaterialApp(home:RegistryPatientScreen(registry:r,patient:p))));
    await tester.pumpAndSettle();
    expect(find.text('Facility: NAUTH'),findsOneWidget);
    expect(find.text('Registry: hbv'),findsOneWidget);
    expect(find.text(' · NAUTH'),findsNothing);
    await tester.tap(find.text('History table'));await tester.pumpAndSettle();
    expect(find.byType(RegistryTableView),findsOneWidget);
    await tester.tap(find.byTooltip('Remove patient from registry'));await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));await tester.pumpAndSettle();
    expect((await repo.load()).patients.length,1);
    expect(tester.takeException(),isNull);
  });
}
