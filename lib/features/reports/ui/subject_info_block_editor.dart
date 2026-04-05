import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/template_editor_provider.dart';

class SubjectInfoTemplateEditor extends StatefulWidget {
  const SubjectInfoTemplateEditor({super.key});

  @override
  State<SubjectInfoTemplateEditor> createState() => _SubjectInfoTemplateEditorState();
}

class _SubjectInfoTemplateEditorState extends State<SubjectInfoTemplateEditor> {
  Future<String?> _promptText(
    BuildContext context,
    String title, {
    String initialValue = '',
    String hint = '',
    String confirmText = 'Save',
  }) async {
    String value = initialValue;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initialValue,
          autofocus: true,
          decoration: InputDecoration(
            hintText: hint.isEmpty ? null : hint,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => value = v,
          onFieldSubmitted: (_) => Navigator.pop(ctx, value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, value.trim()),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    if (!mounted) return null;
    final trimmed = (result ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _showAddFieldDialog(BuildContext context, TemplateEditorProvider vm) async {
    final title = await _promptText(
      context,
      'Add field',
      hint: 'Field title',
      confirmText: 'Add',
    );
    if (!mounted || title == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    vm.addCustomField(title: title, required: false);
  }

  Future<void> _renameDialog(
    BuildContext context,
    TemplateEditorProvider vm,
    String fieldId,
    String currentTitle,
  ) async {
    final next = await _promptText(
      context,
      'Rename field',
      initialValue: currentTitle,
      confirmText: 'Save',
    );
    if (!mounted || next == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    vm.renameField(fieldId, next);
  }

  Future<void> _editHeadingDialog(BuildContext context, TemplateEditorProvider vm, String currentHeading) async {
    final next = await _promptText(
      context,
      'Subject info heading',
      initialValue: currentHeading,
      hint: 'Leave empty to hide heading',
      confirmText: 'Save',
    );
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    vm.setSubjectInfoHeading(next ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TemplateEditorProvider>(
      builder: (context, vm, _) {
        final def = vm.subjectInfo;
        final fields = def.orderedFields;

        Widget fieldTile(field) {
          return Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.7)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      field.title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 96,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Rename',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _renameDialog(context, vm, field.key, field.title),
                        ),
                        field.isSystem
                            ? const SizedBox(width: 40)
                            : IconButton(
                                tooltip: 'Discard field',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => vm.removeField(field.key),
                              ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        Widget fieldsBody;
        if (fields.isEmpty) {
          fieldsBody = const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No fields yet.'),
          );
        } else if (def.columns == 2) {
          fieldsBody = LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth > 560
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: fields
                    .map((f) => SizedBox(width: width, child: fieldTile(f)))
                    .toList(growable: false),
              );
            },
          );
        } else {
          fieldsBody = Column(
            children: [
              for (final f in fields) ...[
                fieldTile(f),
                const SizedBox(height: 10),
              ]
            ],
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Subject Info (Template)',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            !def.enabled
                                ? 'Disabled in this template'
                                : def.heading.trim().isEmpty
                                    ? '(Heading hidden in output)'
                                    : 'Heading: ${def.heading}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit heading',
                      icon: const Icon(Icons.edit_note),
                      onPressed: () => _editHeadingDialog(context, vm, def.heading),
                    ),
                    Switch(
                      value: def.enabled,
                      onChanged: vm.toggleSubjectInfo,
                    ),
                  ],
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 180),
                  crossFadeState: def.enabled ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                  firstChild: Column(
                    children: [
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            'Columns',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const Spacer(),
                          SegmentedButton<int>(
                            segments: const [
                              ButtonSegment(value: 1, label: Text('1 col')),
                              ButtonSegment(value: 2, label: Text('2 col')),
                            ],
                            selected: {def.columns},
                            onSelectionChanged: (s) => vm.setSubjectInfoColumns(s.first),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      fieldsBody,
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => _showAddFieldDialog(context, vm),
                          icon: const Icon(Icons.add),
                          label: const Text('Add field'),
                        ),
                      ),
                    ],
                  ),
                  secondChild: const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Subject info is disabled for this template.'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
