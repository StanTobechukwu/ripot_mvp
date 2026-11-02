import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../../../core/platform/report_clipboard_data.dart';
import '../domain/finding_report_order.dart';
import '../domain/guided_report_presentation.dart';
import '../domain/models/nodes.dart';
import '../domain/models/report_doc.dart';
import '../domain/pdf/pdf_estimates.dart';

/// Projects only visible report text, never attachment paths or record-only
/// values. The same projection supplies both clipboard representations.
class ReportTextService {
  const ReportTextService();

  /// Stable v1 text used for allowance fingerprints. Keep its whitespace and
  /// punctuation independent of presentation changes and clipboard formats so
  /// this update cannot charge again for an already-copied report.
  String render(ReportDoc doc) {
    List<String> lines(_TextSection section) => [
      if (section.node.title.trim().isNotEmpty) '${section.node.title.trim()}:',
      ...section.paragraphs,
      for (final child in section.children) ...lines(child),
    ];
    return [
      ..._header(doc),
      for (final root in _sections(doc))
        if (lines(root).isNotEmpty) lines(root).join('\n'),
      ..._signature(doc),
    ].join('\n\n').replaceAll('\r\n', '\n');
  }

  ReportClipboardData clipboard(ReportDoc doc) {
    final sections = _sections(doc);
    String plainSection(_TextSection section) {
      final layout = section.node.reportRole == 'report.paragraph'
          ? ReportLayout.inline : doc.reportLayout;
      final indent = doc.indentHierarchy ? '  ' * section.depth : '';
      final contentIndent = '$indent${layout == ReportLayout.block && doc.indentContent ? '  ' : ''}';
      final title = section.node.title.trim();
      final label = '$title${title.isNotEmpty && doc.showColonAfterTitlesWithContent ? ':' : ''}';
      String indentLines(String text, String prefix) =>
          text.split('\n').map((line) => '$prefix$line').join('\n');
      final own = <String>[];
      if (layout != ReportLayout.block && section.paragraphs.isNotEmpty) {
        own.add(indentLines('${label.isEmpty ? '' : '$label '}${section.paragraphs.first}', indent));
        own.addAll(section.paragraphs.skip(1).map((text) => indentLines(text, indent)));
      } else {
        if (title.isNotEmpty) own.add('$indent$label');
        own.addAll(section.paragraphs.map((text) => indentLines(text, contentIndent)));
      }
      return [...own, ...section.children.map(plainSection)].join('\n\n');
    }

    final html = StringBuffer();
    final fontSize = (11 * doc.fontScale.clamp(0.7, 2.0)).toStringAsFixed(2);
    html.write('<div style="font-family:Arial,sans-serif;font-size:${fontSize}pt;line-height:1.35;color:#000000;">');
    html.write('<p style="margin:0 0 6pt 0;">DRAFT</p>');
    if (effectiveReportTitle(doc).isNotEmpty) {
      html.write('<p style="margin:0 0 10pt 0;font-size:16pt;font-weight:bold;text-align:center;">${_escape(effectiveReportTitle(doc))}</p>');
    }
    final date = _date(doc);
    if (date != null) html.write('<p style="margin:0 0 10pt 0;">${_escape(date)}</p>');
    final subjectFields = _subjectFields(doc);
    if (subjectFields.isNotEmpty) {
      final heading = visibleSubjectInfoHeading(doc);
      if (heading.isNotEmpty) html.write('<p style="margin:0 0 6pt 0;font-weight:bold;">${_escape(heading)}</p>');
      final columns = doc.subjectInfoDef.columns == 2 ? 2 : 1;
      html.write('<table style="width:100%;border-collapse:collapse;margin-bottom:10pt;" cellpadding="0" cellspacing="0"><tbody>');
      for (var i = 0; i < subjectFields.length; i += columns) {
        html.write('<tr>');
        for (var j = 0; j < columns; j++) {
          html.write('<td style="width:${100 ~/ columns}%;vertical-align:top;padding:0 12pt 6pt 0;">');
          if (i + j < subjectFields.length) html.write(_escape(subjectFields[i + j]));
          html.write('</td>');
        }
        html.write('</tr>');
      }
      html.write('</tbody></table>');
    }

    void htmlSection(_TextSection section) {
      final node = section.node;
      final layout = node.reportRole == 'report.paragraph'
          ? ReportLayout.inline : doc.reportLayout;
      final indent = doc.indentHierarchy ? 12 * section.depth : 0;
      final title = node.title.trim();
      final label = '$title${title.isNotEmpty && doc.showColonAfterTitlesWithContent ? ':' : ''}';
      final weight = section.depth == 0 || node.style.bold ? 'bold' : 'normal';
      final align = node.style.align.name;
      final first = section.paragraphs.isEmpty ? '' : section.paragraphs.first;
      final labelHtml = '<span style="font-weight:$weight;">${_escape(label)}</span>';
      final blockTitle = layout == ReportLayout.block || section.paragraphs.isEmpty;
      if (blockTitle) {
        if (title.isNotEmpty) {
          final scale = switch (node.style.level) {
            HeadingLevel.h1 => 1.45,
            HeadingLevel.h2 => 1.25,
            HeadingLevel.h3 => 1.10,
            HeadingLevel.h4 => 1.0,
          };
          final titleSize = (double.parse(fontSize) * scale).toStringAsFixed(2);
          html.write('<p style="margin:0 0 4pt ${indent}pt;font-size:${titleSize}pt;text-align:$align;">$labelHtml</p>');
        }
      } else if (layout == ReportLayout.aligned && title.isNotEmpty) {
        html.write('<table style="width:100%;border-collapse:collapse;margin:0 0 10pt ${indent}pt;" cellpadding="0" cellspacing="0"><tbody><tr>');
        html.write('<td style="width:140pt;vertical-align:top;padding:0 10pt 0 0;text-align:$align;">$labelHtml</td>');
        html.write('<td style="vertical-align:top;padding:0;">${_escape(first)}</td></tr></tbody></table>');
      } else {
        html.write('<p style="margin:0 0 10pt ${indent}pt;">${title.isEmpty ? '' : '$labelHtml '}${_escape(first)}</p>');
      }
      final contentIndent = indent + (layout == ReportLayout.block && doc.indentContent ? 12 : 0);
      for (final paragraph in blockTitle ? section.paragraphs : section.paragraphs.skip(1)) {
        html.write('<p style="margin:0 0 10pt ${contentIndent}pt;">${_escape(paragraph)}</p>');
      }
      for (final child in section.children) { htmlSection(child); }
    }

    for (final section in sections) { htmlSection(section); }
    for (final signature in _signature(doc)) {
      html.write('<p style="margin:10pt 0 0 0;">${_escape(signature)}</p>');
    }
    html.write('</div>');
    return ReportClipboardData(
      text: [..._header(doc), ...sections.map(plainSection), ..._signature(doc)]
          .join('\n\n').replaceAll('\r\n', '\n'),
      html: html.toString(),
    );
  }

  static String _escape(String value) => const HtmlEscape()
      .convert(value.replaceAll('\r\n', '\n'))
      .replaceAll('\n', '<br>');

  static String? _date(ReportDoc doc) {
    final date = DateTime.tryParse(doc.reportDateIso);
    if (date == null) return null;
    return 'Date: ${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static List<String> _subjectFields(ReportDoc doc) => [
    if (doc.subjectInfoDef.enabled)
      for (final field in doc.subjectInfoDef.orderedFields)
        if (doc.subjectInfo.valueOf(field.key).trim().isNotEmpty)
          '${field.title}: ${doc.subjectInfo.valueOf(field.key).trim()}',
  ];

  static List<String> _header(ReportDoc doc) {
    final fields = _subjectFields(doc);
    return [
      'DRAFT',
      if (effectiveReportTitle(doc).isNotEmpty) effectiveReportTitle(doc),
      if (_date(doc) case final String date) date,
      if (fields.isNotEmpty) [
        if (visibleSubjectInfoHeading(doc).isNotEmpty) visibleSubjectInfoHeading(doc),
        ...fields,
      ].join('\n'),
    ];
  }

  static List<String> _signature(ReportDoc doc) {
    final signature = doc.signature;
    final clinician = [signature.roleTitle, signature.name, signature.credentials]
        .map((v) => v.trim()).where((v) => v.isNotEmpty).join('\n');
    return [
      if (clinician.isNotEmpty) clinician,
      if (signature.assistantName.trim().isNotEmpty)
        '${signature.assistantLabel.trim().isEmpty ? 'Assistant' : signature.assistantLabel.trim()}: ${signature.assistantName.trim()}',
    ];
  }

  static List<_TextSection> _sections(ReportDoc doc) {
    final roots = findingsInAnatomicalOrder(prepareGuidedReport(doc.roots));
    final sections = <String, SectionNode>{};
    void index(SectionNode section) {
      sections[section.id] = section;
      for (final child in section.children.whereType<SectionNode>()) { index(child); }
    }
    for (final root in roots) { index(root); }
    String firstValue(SectionNode section) {
      for (final child in section.children) {
        if (child is ContentNode && child.text.trim().isNotEmpty) return child.text.trim();
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
    List<_TextSection> project(SectionNode section, int depth) {
      if (!visible(section)) return [];
      final nested = <_TextSection>[];
      final own = <String>[];
      for (final child in section.children) {
        if (child is SectionNode) nested.addAll(project(child, depth + 1));
        if (child is ContentNode && section.showInPdf) {
          var text = child.text.trim();
          if (text.isEmpty) continue;
          if (section.inputType == FieldInputType.numeric && section.unit.trim().isNotEmpty &&
              !text.endsWith(section.unit.trim())) text = '$text ${section.unit.trim()}';
          own.add(text);
        }
      }
      if (section.note.trim().isNotEmpty) own.add(section.note.trim());
      if (!section.showInPdf && own.isEmpty) return nested;
      if (section.omitWhenEmpty && own.isEmpty && nested.isEmpty) return [];
      return [_TextSection(section, own, nested, math.max(depth, section.indent))];
    }
    return [for (final root in roots) ...project(root, 0)];
  }

  static String fingerprint(String uid, String text) =>
      sha256.convert(utf8.encode('ripot-copy-v1\n$uid\n$text')).toString();
}

class _TextSection {
  const _TextSection(this.node, this.paragraphs, this.children, this.depth);
  final SectionNode node;
  final List<String> paragraphs;
  final List<_TextSection> children;
  final int depth;
}
