import 'models/report_doc.dart';

/// Only uses explicit subject metadata. Conflicting facilities require review.
/// Never reads a letterhead image or substitutes the user's current facility.
String reportFacility(ReportDoc report) {
  if (!report.subjectInfoDef.enabled) return '';
  const labels = {'facility', 'hospital', 'centre', 'center', 'procedure facility'};
  final values = <String>{};
  for (final field in report.subjectInfoDef.orderedFields) {
    if (field.key == 'facility' || labels.contains(field.title.trim().toLowerCase())) {
      final value = report.subjectInfo.valueOf(field.key).trim();
      if (value.isNotEmpty) values.add(value);
    }
  }
  return values.length == 1 ? values.single : '';
}
