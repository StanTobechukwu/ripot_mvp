import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../reports/data/templates_repository.dart';
import '../../reports/domain/models/template_doc.dart';
import '../../reports/domain/models/report_doc.dart';
import '../../reports/domain/models/nodes.dart';
import '../data/records_repository.dart';

List<SectionNode> _sections(List<SectionNode> roots) => [
  for (final root in roots) ...[
    root,
    ..._sections(root.children.whereType<SectionNode>().toList()),
  ],
];

Future<TemplateDoc?> chooseRecordsFields(
  BuildContext context,
  TemplateDoc template,
) async {
  final subjects = {
    for (final f in template.subjectInfo.fields)
      if (f.addToRecords) f.key,
  };
  final sections = {
    for (final s in _sections(template.roots))
      if (s.addToRecords) s.id,
  };
  final accepted = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setLocal) => AlertDialog(
        title: const Text('Choose Records fields'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  template.templateId.isEmpty
                      ? 'Choose fields for this report. The PDF stays unchanged.'
                      : 'These choices will be reused for this template. The PDF stays unchanged.',
                ),
                for (final f in template.subjectInfo.fields)
                  CheckboxListTile(
                    title: Text(f.title),
                    subtitle: const Text('Subject information'),
                    value: subjects.contains(f.key),
                    onChanged: (v) => setLocal(() {
                      if (v == true) {
                        subjects.add(f.key);
                      } else {
                        subjects.remove(f.key);
                      }
                    }),
                  ),
                for (final s in _sections(template.roots))
                  CheckboxListTile(
                    title: Text(s.title),
                    subtitle: Text(
                      s.inputType == FieldInputType.freeText
                          ? 'Text'
                          : 'Structured value${s.unit.isEmpty ? '' : ' · ${s.unit}'}',
                    ),
                    value: sections.contains(s.id),
                    onChanged: (v) => setLocal(() {
                      if (v == true) {
                        sections.add(s.id);
                      } else {
                        sections.remove(s.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Use these fields'),
          ),
        ],
      ),
    ),
  );
  if (accepted != true) return null;
  SectionNode patch(SectionNode s) => s.copyWith(
    addToRecords: sections.contains(s.id),
    children: s.children.map((n) => n is SectionNode ? patch(n) : n).toList(),
  );
  return template.copyWith(
    recordsConfigured: true,
    updatedAt: DateTime.now(),
    roots: template.roots.map(patch).toList(),
    subjectInfo: template.subjectInfo.copyWith(
      fields: [
        for (final f in template.subjectInfo.fields)
          f.copyWith(addToRecords: subjects.contains(f.key)),
      ],
    ),
  );
}

Future<ReportDoc?> prepareReportRecords(
  BuildContext context,
  ReportDoc report, {
  bool force = false,
}) async {
  final records = context.read<RecordsRepository>();
  final templates = context.read<TemplatesRepository>();
  if (!force && await records.loadByReportId(report.reportId) != null) {
    return report;
  }
  TemplateDoc? template;
  if (report.sourceTemplateId.isNotEmpty) {
    try {
      template = await templates.loadTemplate(report.sourceTemplateId);
    } catch (_) {
      /* Deleted template: choose for this report. */
    }
  }
  if (!context.mounted) return null;
  final source =
      template ??
      TemplateDoc(
        templateId: '',
        updatedAt: DateTime.now(),
        name: report.reportTitle,
        roots: report.roots,
        subjectInfo: report.subjectInfoDef,
      );
  final selected = source.recordsConfigured && !force
      ? source
      : await chooseRecordsFields(context, source);
  if (selected == null) return null;
  if (template != null && !identical(selected, source)) {
    await templates.saveTemplate(selected);
  }
  final flags = {
    for (final s in _sections(selected.roots)) s.id: s.addToRecords,
  };
  final subjects = {
    for (final f in selected.subjectInfo.fields) f.key: f.addToRecords,
  };
  SectionNode patch(SectionNode s) => s.copyWith(
    addToRecords: flags[s.id] ?? s.addToRecords,
    children: s.children.map((n) => n is SectionNode ? patch(n) : n).toList(),
  );
  return report.copyWith(
    roots: report.roots.map(patch).toList(),
    subjectInfoDef: report.subjectInfoDef.copyWith(
      fields: [
        for (final f in report.subjectInfoDef.fields)
          f.copyWith(addToRecords: subjects[f.key] ?? f.addToRecords),
      ],
    ),
  );
}
