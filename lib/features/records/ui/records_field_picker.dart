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

bool _expectedNarrativeSection(SectionNode section) {
  final title = section.title.trim().toLowerCase();
  return {
    'diagnosis',
    'diagnoses',
    'impression',
    'conclusion',
    'note',
    'notes',
    'recommendation',
    'recommendations',
    'comments',
  }.contains(title);
}

Future<TemplateDoc?> chooseRecordsFields(
  BuildContext context,
  TemplateDoc template, {
  bool forReport = false,
  ValueChanged<bool>? onRememberChanged,
}) async {
  var remember = false;
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
                  forReport
                      ? 'Review fields for this report. Unchecked fields will be excluded when you save Records. The PDF stays unchanged.'
                      : 'These choices will be reused for this template. The PDF stays unchanged.',
                ),
                if (onRememberChanged != null)
                  CheckboxListTile(
                    title: const Text('Remember for this template'),
                    subtitle: const Text('Use these defaults for future reports.'),
                    value: remember,
                    onChanged: (value) => setLocal(() {
                      remember = value ?? false;
                      onRememberChanged(remember);
                    }),
                  ),
                if (template.subjectInfo.enabled)
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
                          ? (_expectedNarrativeSection(s)
                              ? 'Narrative clinical field · kept as text'
                              : 'Narrative text · consider a structured input when possible')
                          : 'Structured value${s.unit.isEmpty ? '' : ' · ${s.unit}'}',
                    ),
                    value: sections.contains(s.id),
                    onChanged: (v) async {
                      if (v == true &&
                          s.inputType == FieldInputType.freeText &&
                          !_expectedNarrativeSection(s)) {
                        final keep = await showDialog<bool>(
                          context: c,
                          builder: (warningContext) => AlertDialog(
                            title: const Text('Add narrative text to Records?'),
                            content: Text(
                              '“${s.title}” is free text. It will be kept as narrative information, '
                              'but it will be less useful for filtering, comparison and analytics. '
                              'Use a structured field instead when possible.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(warningContext, false),
                                child: const Text('Keep out of Records'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(warningContext, true),
                                child: const Text('Include text'),
                              ),
                            ],
                          ),
                        );
                        if (keep != true) return;
                      }
                      setLocal(() {
                        if (v == true) {
                          sections.add(s.id);
                        } else {
                          sections.remove(s.id);
                        }
                      });
                    },
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
  final existing = await records.loadByReportId(report.reportId);
  TemplateDoc? template;
  if (report.sourceTemplateId.isNotEmpty) {
    try {
      template = await templates.loadTemplate(report.sourceTemplateId);
    } catch (_) {
      /* Deleted template: choose for this report. */
    }
  }
  if (!context.mounted) return null;
  // The report owns the field list: its template may have changed since creation.
  var current = report;
  if (existing != null) {
    current = records.withSavedRecordSelection(report, existing);
  } else if (template != null && template.recordsConfigured) {
    final sectionFlags = {
      for (final s in _sections(template.roots)) s.id: s.addToRecords,
    };
    final subjectFlags = {
      for (final f in template.subjectInfo.fields) f.key: f.addToRecords,
    };
    SectionNode defaults(SectionNode s) => s.copyWith(
      addToRecords: sectionFlags[s.id] ?? s.addToRecords,
      children: s.children.map((n) => n is SectionNode ? defaults(n) : n).toList(),
    );
    current = report.copyWith(
      roots: report.roots.map(defaults).toList(),
      subjectInfoDef: report.subjectInfoDef.copyWith(fields: [
        for (final f in report.subjectInfoDef.fields)
          f.copyWith(addToRecords: subjectFlags[f.key] ?? f.addToRecords),
      ]),
    );
  }
  final source = TemplateDoc(
    templateId: template?.templateId ?? '',
    updatedAt: DateTime.now(),
    name: report.reportTitle,
    roots: current.roots,
    subjectInfo: current.subjectInfoDef,
  );
  var remember = false;
  final selected = await chooseRecordsFields(
    context, source, forReport: true,
    onRememberChanged: template == null ? null : (value) => remember = value,
  );
  if (selected == null) return null;
  if (template != null && remember) {
    // Update flags only; never replace a newer template with an older report.
    final flags = {for (final s in _sections(selected.roots)) s.id: s.addToRecords};
    final subjects = {for (final f in selected.subjectInfo.fields) f.key: f.addToRecords};
    SectionNode patchTemplate(SectionNode s) => s.copyWith(
      addToRecords: flags[s.id] ?? s.addToRecords,
      children: s.children.map((n) => n is SectionNode ? patchTemplate(n) : n).toList(),
    );
    await templates.saveTemplate(template.copyWith(
      recordsConfigured: true,
      updatedAt: DateTime.now(),
      roots: template.roots.map(patchTemplate).toList(),
      subjectInfo: template.subjectInfo.copyWith(fields: [
        for (final f in template.subjectInfo.fields)
          f.copyWith(addToRecords: subjects[f.key] ?? f.addToRecords),
      ]),
    ));
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
