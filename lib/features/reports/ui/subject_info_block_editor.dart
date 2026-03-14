import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/template_editor_provider.dart';

class SubjectInfoTemplateEditor extends StatefulWidget {
  const SubjectInfoTemplateEditor({super.key});

  @override
  State<SubjectInfoTemplateEditor> createState() => _SubjectInfoTemplateEditorState();
}

class _SubjectInfoTemplateEditorState extends State<SubjectInfoTemplateEditor> {

  Future<void> _showAddFieldDialog(BuildContext context, TemplateEditorProvider vm) async {
    final c = TextEditingController();
    bool required = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add field'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: c,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Field title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: required,
                onChanged: (v) => setLocal(() => required = v ?? false),
                title: const Text('Required'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok == true) {
      FocusManager.instance.primaryFocus?.unfocus();
      vm.addCustomField(title: c.text.trim().isEmpty ? 'Custom Field' : c.text.trim(), required: required);
    }
    Future<void>.delayed(const Duration(milliseconds: 250), c.dispose);
  }

  void _renameDialog(
    BuildContext context,
    TemplateEditorProvider vm,
    String fieldId,
    String currentTitle,
  ) {
    final c = TextEditingController(text: currentTitle);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename field'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final next = c.text.trim().isEmpty ? currentTitle : c.text.trim();
              FocusManager.instance.primaryFocus?.unfocus();
              vm.renameField(fieldId, next);
              Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(() => Future<void>.delayed(const Duration(milliseconds: 250), c.dispose));
  }

  void _editHeadingDialog(BuildContext context, TemplateEditorProvider vm, String currentHeading) {
    final c = TextEditingController(text: currentHeading);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Subject info heading'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
            hintText: 'Leave empty to hide heading',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              vm.setSubjectInfoHeading(c.text);
              Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(() => Future<void>.delayed(const Duration(milliseconds: 250), c.dispose));
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
                            def.heading.trim().isEmpty ? '(Heading hidden in output)' : 'Heading: ${def.heading}',
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

                const SizedBox(height: 8),

                Row(
                  children: [
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () => _showAddFieldDialog(context, vm),
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
