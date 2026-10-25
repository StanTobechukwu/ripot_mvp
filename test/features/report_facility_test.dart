import 'package:flutter_test/flutter_test.dart';
import 'package:ripot/features/reports/domain/report_facility.dart';
import 'package:ripot/features/reports/domain/models/report_doc.dart';
import 'package:ripot/features/reports/domain/models/subject_info_def.dart';
import 'package:ripot/features/reports/domain/models/subject_info_value.dart';
import 'package:ripot/features/logbook/services/report_log_draft.dart';
import 'package:ripot/features/records/data/records_repository.dart';

ReportDoc report({bool conflicting = false, bool enabled = true}) => ReportDoc(
  reportId: 'report-1', createdAtIso: '2026-09-14', updatedAtIso: '2026-09-14',
  subjectInfoDef: SubjectInfoBlockDef(
    enabled: enabled, columns: 1, schemaVersion: 1, heading: '',
    fields: [
      const SubjectFieldDef(key: 'site', title: 'Hospital', required: false, order: 0, isSystem: false),
      if (conflicting)
        const SubjectFieldDef(key: 'other', title: 'Facility', required: false, order: 1, isSystem: false),
    ],
  ),
  subjectInfo: const SubjectInfoValues({'site': 'NAUTH', 'other': 'Other hospital'}),
);

void main() {
  test('explicit report facility reaches log and Registry source', () {
    final doc = report();
    expect(reportFacility(doc), 'NAUTH');
    expect(logDataFromReport(doc).facility, 'NAUTH');
    expect(RecordsRepository().registrySourceForReport(doc).valueOf('facility'), 'NAUTH');
  });
  test('hidden or conflicting facility is not guessed by the shared extractor', () {
    expect(reportFacility(report(enabled: false)), isEmpty);
    expect(reportFacility(report(conflicting: true)), isEmpty);
  });
}
