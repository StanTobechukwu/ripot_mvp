import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/finding_report_order.dart';
import '../domain/guided_report_presentation.dart';
import '../domain/models/nodes.dart';
import '../domain/models/report_doc.dart';
import '../domain/pdf/pdf_estimates.dart';

/// Plain-text projection of the report shown in Preview. It never serializes
/// storage paths, record-only fields, template blueprints or attachment bytes.
class ReportTextService {
  const ReportTextService();

  String render(ReportDoc doc) {
    final roots = findingsInAnatomicalOrder(prepareGuidedReport(doc.roots));
    final sections = <String, SectionNode>{};
    void index(SectionNode section) {
      sections[section.id] = section;
      for (final child in section.children.whereType<SectionNode>()) {
        index(child);
      }
    }
    for (final root in roots) {
      index(root);
    }

    String firstValue(SectionNode section) {
      for (final child in section.children) {
        if (child is ContentNode && child.text.trim().isNotEmpty) {
          return child.text.trim();
        }
        if (child is SectionNode) {
          final value = firstValue(child);
          if (value.isNotEmpty) return value;
        }
      }
      return '';
    }

    bool visible(SectionNode section) {
      if (!section.hasCondition) return true;
      final parent = sections[section.conditionalParentSectionId];
      if (parent == null) return true;
      final expected = section.conditionalEquals.trim().toLowerCase();
      final value = firstValue(parent).toLowerCase();
      return value == expected || value.split(';').any((v) => v.trim() == expected);
    }

    List<String> project(SectionNode section) {
      if (!visible(section)) return [];
      final nested = <String>[];
      final own = <String>[];
      for (final child in section.children) {
        if (child is SectionNode) nested.addAll(project(child));
        if (child is ContentNode && section.showInPdf) {
          var text = child.text.trim();
          if (text.isEmpty) continue;
          if (section.inputType == FieldInputType.numeric &&
              section.unit.trim().isNotEmpty &&
              !text.endsWith(section.unit.trim())) {
            text = '$text ${section.unit.trim()}';
          }
          own.add(text);
        }
      }
      final note = section.note.trim();
      if (note.isNotEmpty) own.add(note);
      if (!section.showInPdf && own.isEmpty) return nested;
      if (section.omitWhenEmpty && own.isEmpty && nested.isEmpty) return [];
      final title = section.title.trim();
      return [
        if (title.isNotEmpty) '$title:',
        ...own,
        ...nested,
      ];
    }

    final parts = <String>[
      'DRAFT',
      if (effectiveReportTitle(doc).isNotEmpty) effectiveReportTitle(doc),
    ];
    final date = DateTime.tryParse(doc.reportDateIso);
    if (date != null) {
      parts.add('Date: ${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}');
    }
    if (doc.subjectInfoDef.enabled) {
      final fields = <String>[
        for (final field in doc.subjectInfoDef.orderedFields)
          if (doc.subjectInfo.valueOf(field.key).trim().isNotEmpty)
            '${field.title}: ${doc.subjectInfo.valueOf(field.key).trim()}',
      ];
      if (fields.isNotEmpty) {
        parts.add([
          if (visibleSubjectInfoHeading(doc).isNotEmpty)
            visibleSubjectInfoHeading(doc),
          ...fields,
        ].join('\n'));
      }
    }
    for (final root in roots) {
      final lines = project(root);
      if (lines.isNotEmpty) parts.add(lines.join('\n'));
    }
    final signature = doc.signature;
    final clinician = [signature.roleTitle, signature.name, signature.credentials]
        .map((v) => v.trim()).where((v) => v.isNotEmpty).join('\n');
    if (clinician.isNotEmpty) parts.add(clinician);
    if (signature.assistantName.trim().isNotEmpty) {
      parts.add('${signature.assistantLabel.trim().isEmpty ? 'Assistant' : signature.assistantLabel.trim()}: ${signature.assistantName.trim()}');
    }
    return parts.join('\n\n').replaceAll('\r\n', '\n');
  }

  /// IDs and edit timestamps are deliberately excluded. The same output on a
  /// second device or a restored/duplicated draft uses the same authorization.
  static String fingerprint(String uid, String text) =>
      sha256.convert(utf8.encode('ripot-copy-v1\n$uid\n$text')).toString();
}
