import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/features/registry/data/registry_repository.dart';
import 'package:ripot/features/registry/domain/report_link_match.dart';
import 'package:ripot/features/registry/ui/report_link_picker.dart';
import 'package:ripot/features/reports/data/reports_repository.dart';

const patient = RegistryPatient(
  id: 'p',
  name: 'Example Patient',
  reference: '001',
  facility: 'Clinic A',
);
ReportSummary report(
  String id, {
  String name = 'Example Patient',
  String identifier = '001',
  String facility = 'Clinic A',
}) => ReportSummary(
  reportId: id,
  title: id,
  subtitle: '',
  updatedAt: DateTime(2026, 10, 21),
  hasPdf: true,
  isFinalized: true,
  subjectName: name,
  subjectId: identifier,
  facility: facility,
  reportDateIso: '2026-10-20',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'same name cannot override conflicting identifiers or identifier namespaces',
    () {
      expect(
        reportLinkMatch(patient, report('r', identifier: '002')),
        ReportLinkMatch.conflict,
      );
      expect(
        reportLinkMatch(patient, report('r', identifier: '1')),
        ReportLinkMatch.conflict,
      );
      expect(
        reportLinkMatch(patient, report('r', facility: 'Clinic B')),
        ReportLinkMatch.conflict,
      );
      expect(
        reportLinkMatch(patient, report('r', name: 'Other Patient')),
        ReportLinkMatch.unverified,
      );
      expect(
        reportLinkMatch(patient, report('r', name: ' example   patient ')),
        ReportLinkMatch.identifier,
      );
      expect(
        reportLinkMatch(patient, report('r', identifier: '')),
        ReportLinkMatch.name,
      );
      expect(
        reportLinkMatch(patient, report('r', name: '', identifier: '')),
        ReportLinkMatch.unverified,
      );
    },
  );

  test(
    'a source report linked through an update cannot move to another patient',
    () async {
      final data = RegistryData(
        patients: [
          patient,
          const RegistryPatient(id: 'other', name: 'Other Patient'),
        ],
        updates: [
          RegistryUpdate(
            id: 'u',
            registryId: 'registry',
            patientId: 'other',
            patientName: 'Other Patient',
            observedAt: DateTime(2026),
            recordedAt: DateTime(2026),
            sourceReportId: 'r',
            values: const {},
            definitions: const {},
          ),
        ],
      );
      SharedPreferences.setMockInitialValues({
        RegistryRepository.storageKey: jsonEncode(data.toJson()),
      });
      expect(reportsOwnedByOtherPatients(data, patient.id), contains('r'));
      await expectLater(
        RegistryRepository().linkReport(patient.id, 'r'),
        throwsStateError,
      );
    },
  );

  testWidgets(
    'only suggestions initially; broader search is deliberate and conflicts disabled',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportLinkPicker(
              patient: patient,
              reports: [
                report('matching-report'),
                report('conflicting-report', identifier: '002'),
                report('unknown-report', name: '', identifier: ''),
              ],
              unavailableReportIds: const {},
            ),
          ),
        ),
      );
      expect(find.text('matching-report'), findsOneWidget);
      expect(find.text('conflicting-report'), findsNothing);
      expect(find.text('unknown-report'), findsNothing);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(find.text('matching-report'), findsNothing);
      await tester.enterText(find.byType(TextField), 'report');
      await tester.pumpAndSettle();
      final tile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('conflicting-report'),
          matching: find.byType(ListTile),
        ),
      );
      expect(tile.onTap, isNull);
    },
  );

  testWidgets(
    'same-name suggestion requires confirmation and explicit identity check',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportLinkPicker(
              patient: patient,
              reports: [report('name-only-report', identifier: '')],
              unavailableReportIds: const {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('name-only-report'));
      await tester.pumpAndSettle();
      expect(find.text('Link to this patient?'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Link report'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Link report'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Link to this patient?'), findsNothing);
      expect(find.text('name-only-report'), findsOneWidget);
    },
  );
}
