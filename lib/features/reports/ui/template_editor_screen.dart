import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/templates_repository.dart';
import '../domain/models/nodes.dart';
import '../domain/models/template_doc.dart';
import '../providers/template_editor_provider.dart';
import 'subject_info_block_editor.dart';

class TemplateEditorScreen extends StatelessWidget {
  final String templateId;
  const TemplateEditorScreen({super.key, required this.templateId});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<TemplatesRepository>();

    return FutureBuilder<TemplateDoc>(
      future: repo.loadTemplate(templateId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Edit Template')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        return ChangeNotifierProvider(
          create: (_) => TemplateEditorProvider(snap.data!),
          child: const _TemplateEditorBody(),
        );
      },
    );
  }
}

class _TemplateEditorBody extends StatelessWidget {
  const _TemplateEditorBody();

  Future<void> _save(BuildContext context) async {
    final repo = context.read<TemplatesRepository>();
    final vm = context.read<TemplateEditorProvider>();
    final doc = vm.buildForSave(name: vm.template.name, includeContent: false);
    await repo.saveTemplate(doc);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Template updated')),
    );
  }

  Future<String?> _promptText(BuildContext context, String title, {String hint = 'Type…'}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    controller.dispose();
    return result?.trim().isEmpty ?? true ? null : result!.trim();
  }

  Future<void> _showSectionActions(BuildContext context, SectionNode section) async {
    final vm = context.read<TemplateEditorProvider>();
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.subdirectory_arrow_right),
              title: const Text('Add subsection'),
              onTap: () => Navigator.pop(ctx, 'add_sub'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Style section'),
              onTap: () => Navigator.pop(ctx, 'style'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: const Text('Move up'),
              onTap: () => Navigator.pop(ctx, 'up'),
            ),
            ListTile(
              leading: const Icon(Icons.arrow_downward),
              title: const Text('Move down'),
              onTap: () => Navigator.pop(ctx, 'down'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit title'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete section'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;

    switch (action) {
      case 'add_sub':
        final title = await _promptText(context, 'New subsection');
        if (title != null) vm.addSubsection(section.id, title);
        break;
      case 'style':
        final res = await showModalBottomSheet<_SectionEditResult>(
          context: context,
          showDragHandle: true,
          builder: (_) => _SectionEditSheet(section: section),
        );
        if (res != null) {
          if ((res.rename ?? '').trim().isNotEmpty) vm.renameSection(section.id, res.rename!.trim());
          if (res.style != null) vm.updateSectionStyle(section.id, res.style!);
        }
        break;
      case 'up':
        vm.moveSectionUp(section.id);
        break;
      case 'down':
        vm.moveSectionDown(section.id);
        break;
      case 'rename':
        final title = await _promptText(context, 'Edit section title', hint: section.title);
        if (title != null) vm.renameSection(section.id, title);
        break;
      case 'delete':
        vm.deleteSection(section.id);
        break;
    }
  }

  Widget _sectionTile(BuildContext context, SectionNode section) {
    final vm = context.watch<TemplateEditorProvider>();
    final left = section.indent * 14.0;
    return Padding(
      padding: EdgeInsets.only(left: left, top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => vm.toggleCollapsed(section.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  children: [
                    Icon(section.collapsed ? Icons.chevron_right : Icons.expand_more),
                    const SizedBox(width: 6),
                    Expanded(child: Text(section.title, style: const TextStyle(fontWeight: FontWeight.w600))),
                    IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => _showSectionActions(context, section),
                    )
                  ],
                ),
              ),
            ),
          ),
          if (!section.collapsed)
            ...section.children.whereType<SectionNode>().map((s) => _sectionTile(context, s)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TemplateEditorProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text(vm.template.name),
        actions: [
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.save_outlined),
            onPressed: () => _save(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final title = await _promptText(context, 'New top-level section');
          if (title != null) vm.addTopLevelSection(title);
        },
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SubjectInfoTemplateEditor(),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sections', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if (vm.template.roots.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No sections yet. Use + to add the first section.'),
                    )
                  else
                    ...vm.template.roots.map((s) => _sectionTile(context, s)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionEditResult {
  final String? rename;
  final TitleStyle? style;
  const _SectionEditResult({this.rename, this.style});
}

class _SectionEditSheet extends StatefulWidget {
  final SectionNode section;
  const _SectionEditSheet({required this.section});

  @override
  State<_SectionEditSheet> createState() => _SectionEditSheetState();
}

class _SectionEditSheetState extends State<_SectionEditSheet> {
  late final TextEditingController _title;
  late HeadingLevel _level;
  late bool _bold;
  late TitleAlign _align;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.section.title);
    _level = widget.section.style.level;
    _bold = widget.section.style.bold;
    _align = widget.section.style.align;
  }

  @override
  void dispose() { _title.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Style section')),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<HeadingLevel>(
                    initialValue: _level,
                    decoration: const InputDecoration(labelText: 'Size', border: OutlineInputBorder(), isDense: true),
                    items: HeadingLevel.values.map((h) => DropdownMenuItem(value: h, child: Text(h.name.toUpperCase()))).toList(),
                    onChanged: (v) => setState(() => _level = v ?? _level),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<TitleAlign>(
                    initialValue: _align,
                    decoration: const InputDecoration(labelText: 'Align', border: OutlineInputBorder(), isDense: true),
                    items: TitleAlign.values.map((a) => DropdownMenuItem(value: a, child: Text(a.name))).toList(),
                    onChanged: (v) => setState(() => _align = v ?? _align),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              value: _bold,
              onChanged: (v) => setState(() => _bold = v),
              title: const Text('Bold title'),
              contentPadding: EdgeInsets.zero,
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, _SectionEditResult(
                rename: _title.text.trim(),
                style: widget.section.style.copyWith(level: _level, bold: _bold, align: _align),
              )),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }
}
