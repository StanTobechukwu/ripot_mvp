import '../../reports/domain/models/report_doc.dart';
import '../../reports/domain/report_facility.dart';
import '../../reports/domain/models/nodes.dart';
import '../domain/logbook_models.dart';

LogData logDataFromReport(ReportDoc report, {String meId = ''}) {
  final sections = <String, SectionNode>{};
  void index(SectionNode s) {
    sections[s.id] = s;
    for (final n in s.children.whereType<SectionNode>()) {
      index(n);
    }
  }

  for (final s in report.roots) {
    index(s);
  }
  String value(SectionNode s) => s.children
      .whereType<ContentNode>()
      .map((n) => n.text.trim())
      .where((v) => v.isNotEmpty)
      .join('\n');
  bool visible(SectionNode s, Set<String> visited) {
    if (!s.hasCondition) return true;
    if (!visited.add(s.id)) return false;
    final parent = sections[s.conditionalParentSectionId];
    if (parent == null || !visible(parent, visited)) return false;
    final actual = value(parent).toLowerCase();
    final expected = s.conditionalEquals.trim().toLowerCase();
    return actual == expected ||
        actual.split(';').map((v) => v.trim()).contains(expected);
  }

  final fields = <LogField>[];
  // Subject ID has its own editable reference field. Other subject values are
  // offered for explicit review, including removal, before the log is saved.
  for (final field in report.subjectInfoDef.orderedFields) {
    final v = report.subjectInfo.valueOf(field.key).trim();
    if (field.key != 'subjectId' && v.isNotEmpty) {
      fields.add(LogField('subject:${field.key}', field.title, v));
    }
  }
  void collect(SectionNode s, String parentLabel) {
    if (!visible(s, {})) return;
    final label = parentLabel.isEmpty ? s.title : '$parentLabel / ${s.title}';
    final v = value(s);
    if (s.addToLog && v.isNotEmpty) {
      fields.add(
        LogField(
          'section:${s.id}',
          label,
          '$v${s.unit.isEmpty ? '' : ' ${s.unit}'}${s.note.trim().isEmpty ? '' : '\n${s.note.trim()}'}',
        ),
      );
    }
    for (final child in s.children.whereType<SectionNode>()) {
      collect(child, label);
    }
  }

  for (final s in report.roots) {
    collect(s, '');
  }
  return LogData(
    procedure: report.reportTitle,
    facility: reportFacility(report),
    procedureDate: DateTime.tryParse(report.reportDateIso) ?? DateTime.now(),
    reference: report.subjectInfo.valueOf('subjectId'),
    fields: fields,
    reportAuthor: report.signature.name,
    participants: meId.isEmpty
        ? []
        : [LogParticipant(meId, ProcedureRole.performer)],
  );
}
