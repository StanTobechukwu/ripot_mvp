import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ripot/features/records/data/records_repository.dart';
import 'package:ripot/features/registry/data/registry_repository.dart';
import 'package:ripot/features/reports/domain/models/nodes.dart';
import 'package:ripot/features/reports/domain/models/report_doc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('Records detect changed reports and preserve deliberate corrections', () async {
    final repo = RecordsRepository();
    const stamp = '2026-10-04T10:00:00.000Z';

    ReportDoc reportWith(String value) => ReportDoc(
      reportId: 'rpt_test',
      sourceTemplateId: '',
      createdAtIso: stamp,
      updatedAtIso: stamp,
      reportTitle: 'Colonoscopy',
      roots: [
        SectionNode(
          id: 'finding',
          title: 'Finding',
          inputType: FieldInputType.singleSelect,
          options: const ['Normal', 'Polyp'],
          addToRecords: true,
          children: [ContentNode(id: 'finding_value', text: value)],
        ),
      ],
    );

    final first = reportWith('Normal');
    final draft = await repo.buildDraftForReport(first);
    await repo.saveRecord(draft);
    expect(await repo.statusForReport(first), RecordReportStatus.current);

    final changed = reportWith('Polyp');
    expect(
      await repo.statusForReport(changed),
      RecordReportStatus.reportChanged,
    );

    final stored = await repo.loadByReportId(first.reportId);
    expect(stored, isNotNull);
    final findingKey = stored!.fieldLabels.entries
        .firstWhere((entry) => entry.value == 'Finding')
        .key;

    await repo.saveRecord(
      stored.copyWith(
        values: {
          ...stored.values,
          findingKey: 'Clinician corrected wording',
        },
      ),
    );

    final updatedDraft = await repo.buildDraftForReport(changed);
    expect(
      updatedDraft.values[findingKey],
      'Clinician corrected wording',
    );
    expect(updatedDraft.originalReportValues[findingKey], 'Polyp');
  });

  test('Registry supports related reports and image-only dated updates', () async {
    final repo = RegistryRepository();
    final patient = await repo.addPatient(
      name: 'Test Patient',
      reference: 'P001',
      facility: 'Test Facility',
      registryId: 'reg1',
    );

    await repo.linkReport(patient.id, 'rpt_manual');

    await repo.addUpdate(
      RegistryUpdate(
        id: 'obs1',
        registryId: 'reg1',
        patientId: patient.id,
        patientName: patient.name,
        observedAt: DateTime(2026, 10, 4),
        recordedAt: DateTime(2026, 10, 4, 12),
        values: const {},
        definitions: const {},
        sourceReportId: 'rpt_source',
        images: const [
          RegistryImageAttachment(
            id: 'img1',
            ref: 'data:image/jpeg;base64,AA==',
            label: 'Follow-up image',
            sourceReportId: 'rpt_source',
          ),
        ],
      ),
    );

    final data = await repo.load();
    final savedPatient = data.patients.single;
    expect(savedPatient.relatedReportIds, contains('rpt_manual'));
    expect(savedPatient.relatedReportIds, contains('rpt_source'));

    final update = data.updates.single;
    expect(update.images, hasLength(1));
    expect(update.images.single.label, 'Follow-up image');
    expect(update.values, isEmpty);
  });
}
