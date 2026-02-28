import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/template_editor_provider.dart';

class SubjectInfoTemplateEditor extends StatefulWidget {
  const SubjectInfoTemplateEditor({super.key});

  @override
  State<SubjectInfoTemplateEditor> createState() => _SubjectInfoTemplateEditorState();
}

class _SubjectInfoTemplateEditorState extends State<SubjectInfoTemplateEditor> {
  void _renameDialog(
    BuildContext context,
    TemplateEditorProvider vm,
    String fieldId,
    String currentTitle,
  ) {
    final c = TextEditingController(text: currentTitle);

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename field'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final next = c.text.trim().isEmpty ? currentTitle : c.text.trim();
              vm.renameField(fieldId, next);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(() => c.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TemplateEditorProvider>(
      builder: (context, vm, _) {
        final def = vm.subjectInfo;

        final fields = def.fields.toList()
          ..sort((a, b) => a.order.compareTo(b.order));

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Subject Info (Template)',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Switch(
                      value: def.enabled,
                      onChanged: vm.toggleSubjectInfo,
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                Row(
                  children: [
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () => vm.addCustomField(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add field'),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: fields.length,
                  onReorder: vm.reorderFields,
                  itemBuilder: (_, i) {
                    final f = fields[i];

                    return ListTile(
                      key: ValueKey(f.key),
                      title: Text(f.title),
                      subtitle: Text(f.isSystem ? 'System field' : 'Custom field'),
                      leading: const Icon(Icons.drag_handle),
                      trailing: Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Checkbox(
                            value: f.required,
                            onChanged: (v) => vm.toggleRequired(f.key, v ?? false),
                          ),
                          IconButton(
                            tooltip: 'Rename',
                            icon: const Icon(Icons.edit),
                            onPressed: () => _renameDialog(context, vm, f.key, f.title),
                          ),
                          if (!f.isSystem)
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => vm.removeField(f.key),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
