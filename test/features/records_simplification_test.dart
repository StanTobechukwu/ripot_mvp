import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ripot/features/records/data/records_repository.dart';
import 'package:ripot/features/records/domain/record_models.dart';
import 'package:ripot/features/records/providers/records_provider.dart';
import 'package:ripot/features/records/ui/record_details_screen.dart';
import 'package:ripot/features/reports/domain/models/nodes.dart';
import 'package:ripot/features/reports/domain/models/report_doc.dart';
import 'package:ripot/features/reports/domain/models/subject_info_def.dart';
import 'package:ripot/features/reports/domain/models/subject_info_value.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('legacy subject fields remain included in Records by default', () {
    final field = SubjectFieldDef.fromJson(<String, dynamic>{
      'key': 'hospitalNumber',
      'title': 'Hospital number',
      'required': false,
      'order': 2,
      'isSystem': false,
    });

    expect(field.addToRecords, isTrue);
    expect(
      field.copyWith(addToRecords: false).toJson()['addToRecords'],
      isFalse,
    );
  });

  test(
    'same extra field name can be defined for different procedures',
    () async {
      final repository = RecordsRepository();
      await repository.saveCustomField(
        label: 'Procedure score',
        procedureScope: 'Endoscopy',
        inputType: RecordInputType.numeric,
      );
      await repository.saveCustomField(
        label: 'Procedure score',
        procedureScope: 'Bronchoscopy',
        inputType: RecordInputType.singleSelect,
        options: const <String>['Low', 'High'],
      );

      final fields = await repository.loadCustomFields();
      expect(fields, hasLength(2));
      expect(fields.map((field) => field.key).toSet(), hasLength(2));
      expect(fields.last.options, const <String>['Low', 'High']);
    },
  );

  test('record entries preserve structured field definitions', () {
    final entry = RecordEntry(
      recordEntryId: 'rec-1',
      linkedReportId: 'report-1',
      createdAtIso: '2026-09-13T10:00:00.000Z',
      updatedAtIso: '2026-09-13T10:00:00.000Z',
      values: const <String, String>{'ef': '55'},
      fieldDefinitions: const <String, RecordFieldDef>{
        'ef': RecordFieldDef(
          key: 'ef',
          label: 'Ejection fraction',
          hint: '',
          inputType: RecordInputType.numeric,
          unit: '%',
        ),
      },
    );

    final restored = RecordEntry.decode(entry.encode());
    expect(restored.fieldDefinitions['ef']?.inputType, RecordInputType.numeric);
    expect(restored.fieldDefinitions['ef']?.unit, '%');
  });

  test('draft copies opted-in narrative and structured fields only', () async {
    final repository = RecordsRepository();
    const subjectFields = <SubjectFieldDef>[
      SubjectFieldDef(
        key: 'subjectName',
        title: 'Patient name',
        required: true,
        order: 0,
        isSystem: true,
      ),
      SubjectFieldDef(
        key: 'secret',
        title: 'Do not copy',
        required: false,
        order: 1,
        isSystem: false,
        addToRecords: false,
      ),
    ];
    final doc = ReportDoc(
      reportId: 'report-1',
      createdAtIso: '2026-09-13T10:00:00.000Z',
      updatedAtIso: '2026-09-13T10:00:00.000Z',
      reportTitle: 'Echocardiography',
      subjectInfoDef: const SubjectInfoBlockDef(
        enabled: true,
        columns: 2,
        schemaVersion: 1,
        heading: '',
        fields: subjectFields,
      ),
      subjectInfo: const SubjectInfoValues(<String, String>{
        'subjectName': 'Example patient',
        'secret': 'private value',
      }),
      roots: const <SectionNode>[
        SectionNode(
          id: 'diagnosis-a',
          title: 'Diagnosis',
          addToRecords: true,
          children: <Node>[ContentNode(id: 'c1', text: 'Normal study')],
        ),
        SectionNode(
          id: 'ef-a',
          title: 'Ejection fraction',
          inputType: FieldInputType.numeric,
          unit: '%',
          addToRecords: true,
          children: <Node>[ContentNode(id: 'c2', text: '55')],
        ),
      ],
    );

    final draft = await repository.buildDraftForReport(doc);

    expect(
      draft.valueOf(RecordFieldCatalog.subjectName.key),
      'Example patient',
    );
    expect(draft.values.values, isNot(contains('private value')));
    expect(draft.valueOf(RecordFieldCatalog.diagnosis.key), 'Normal study');
    expect(draft.valueOf('section_ef-a'), '55');
    expect(
      draft.fieldDefinitions['section_ef-a']?.inputType,
      RecordInputType.numeric,
    );
    expect(draft.fieldDefinitions['section_ef-a']?.unit, '%');
  });

  test(
    'same field label from unrelated templates does not auto-merge',
    () async {
      final repository = RecordsRepository();

      Future<RecordEntry> draft(String reportId, String sectionId) {
        return repository.buildDraftForReport(
          ReportDoc(
            reportId: reportId,
            createdAtIso: '2026-09-13T10:00:00.000Z',
            updatedAtIso: '2026-09-13T10:00:00.000Z',
            roots: <SectionNode>[
              SectionNode(
                id: sectionId,
                title: 'Local score',
                addToRecords: true,
                children: const <Node>[ContentNode(id: 'value', text: '1')],
              ),
            ],
          ),
        );
      }

      final first = await draft('report-a', 'score-a');
      final second = await draft('report-b', 'score-b');

      expect(first.values, contains('section_score-a'));
      expect(second.values, contains('section_score-b'));
      expect(second.values, isNot(contains('section_score-a')));
    },
  );

  testWidgets('record review is simple and usable on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = RecordsRepository();
    final provider = RecordsProvider(repo: repository)
      ..allFields = <RecordFieldDef>[
        ...RecordFieldCatalog.coreFields,
        const RecordFieldDef(
          key: 'duration',
          label: 'Duration',
          hint: 'Procedure duration',
          isSystem: false,
          procedureScope: 'Endoscopy',
          inputType: RecordInputType.numeric,
          unit: 'minutes',
        ),
      ];
    const entry = RecordEntry(
      recordEntryId: 'rec-ui',
      linkedReportId: 'report-ui',
      createdAtIso: '2026-09-13T10:00:00.000Z',
      updatedAtIso: '2026-09-13T10:00:00.000Z',
      values: <String, String>{
        'report_id': 'report-ui',
        'report_date': '2026-09-13',
        'procedure': 'Endoscopy',
        'diagnosis': 'Normal study',
      },
      fieldSources: <String, String>{
        'report_id': 'template',
        'report_date': 'template',
        'procedure': 'template',
        'diagnosis': 'template',
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(
          home: RecordDetailsScreen(initialEntry: entry),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Copied from the generated report'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Additional record information'),
      250,
    );
    expect(find.text('Additional record information'), findsOneWidget);
    expect(find.text('Save to Records'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Duration'), 150);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

// Widget coverage lives here because the simplified screen must remain usable
// on the small phones common among Ripot's current Android users.
