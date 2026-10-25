import '../data/registry_repository.dart';
import '../../reports/data/reports_repository.dart';

enum ReportLinkMatch { identifier, name, unverified, conflict }

String normalizePatientText(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Suggestions only: no name, identifier or facility match creates a link.
/// Keep punctuation and leading zeros in identifiers to avoid false matches.
ReportLinkMatch reportLinkMatch(RegistryPatient patient, ReportSummary report) {
  final patientId = normalizePatientText(patient.reference);
  final reportId = normalizePatientText(report.subjectId);
  final patientName = normalizePatientText(patient.name);
  final reportName = normalizePatientText(report.subjectName);
  final facility = normalizePatientText(patient.facility);
  final reportFacility = normalizePatientText(report.facility);
  if (patientId.isNotEmpty && reportId.isNotEmpty) {
    if (patientId != reportId) return ReportLinkMatch.conflict;
    // An identifier is local to its facility, not a global patient identifier.
    if (facility.isNotEmpty &&
        reportFacility.isNotEmpty &&
        facility != reportFacility)
      return ReportLinkMatch.conflict;
    if (patientName.isNotEmpty &&
        reportName.isNotEmpty &&
        patientName != reportName)
      return ReportLinkMatch.unverified;
    return ReportLinkMatch.identifier;
  }
  if (patientName.isNotEmpty && patientName == reportName) {
    if (facility.isNotEmpty &&
        reportFacility.isNotEmpty &&
        facility != reportFacility)
      return ReportLinkMatch.unverified;
    return ReportLinkMatch.name;
  }
  return ReportLinkMatch.unverified;
}

bool isSuggestedReport(RegistryPatient patient, ReportSummary report) => {
  ReportLinkMatch.identifier,
  ReportLinkMatch.name,
}.contains(reportLinkMatch(patient, report));

Set<String> reportsOwnedByOtherPatients(RegistryData data, String patientId) =>
    {
      for (final patient in data.patients)
        if (patient.id != patientId) ...patient.relatedReportIds,
      for (final update in data.updates)
        if (update.patientId != patientId && update.sourceReportId.isNotEmpty)
          update.sourceReportId,
    };
