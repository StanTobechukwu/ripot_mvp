import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/ui/item_actions.dart';
import '../../../core/utils/ids.dart';
import '../data/templates_repository.dart';
import '../domain/models/template_doc.dart';
import '../domain/serialization/template_codec.dart';
import '../providers/template_list_provider.dart';
import '../providers/report_editor_provider.dart';
import '../providers/reports_list_provider.dart';
import 'report_editor_screen.dart';
import 'template_editor_screen.dart';
import 'template_actions.dart';

class TemplatesListScreen extends StatefulWidget {
  const TemplatesListScreen({super.key});
  @override
  State<TemplatesListScreen> createState() => _TemplatesListScreenState();
}

class _TemplatesListScreenState extends State<TemplatesListScreen> {
  String? _group;
  List<String> _groups = [];
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run(_load);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not complete that action. Your existing templates are still available.',
        );
        showMessage(context, _error!);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    final repo = context.read<TemplatesRepository>();
    await context.read<TemplateListProvider>().load();
    final groups = await repo.listGroups();
    if (mounted) {
      setState(() {
        _groups = groups;
        if (_group != null && _group!.isNotEmpty && !groups.contains(_group)) {
          _group = null;
        }
      });
    }
  }

  Future<void> _use(TemplateSummary t) async {
    final doc = await context.read<TemplatesRepository>().loadTemplate(
      t.templateId,
    );
    if (!mounted) return;
    context.read<ReportEditorProvider>().newReportFromTemplate(doc);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReportEditorScreen()),
    );
    if (!mounted) return;
    await context.read<ReportsListProvider>().refresh();
    if (mounted) await _load();
  }

  Future<void> _import() async {
    if (!await canAddTemplate(context) || !mounted) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (picked == null || !mounted) return;
    final bytes = picked.files.single.bytes;
    if (bytes == null || bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw const FormatException('Invalid template size');
    }
    final payload = jsonDecode(utf8.decode(bytes));
    if (payload is! Map ||
        payload['app'] != 'Ripot' ||
        payload['ripotFileType'] != 'template' ||
        payload['template'] is! Map) {
      showMessage(context, 'Choose a template exported from Ripot.');
      return;
    }
    final imported = TemplateCodec.templateFromJson(
      Map<String, dynamic>.from(payload['template'] as Map),
    );
    final name = await askName(
      context,
      'Import template',
      initial: imported.name,
    );
    if (name == null || !mounted) return;
    // Imports keep explicitly exported default content; duplication is structure-only.
    await context.read<TemplatesRepository>().saveTemplate(
      TemplateDoc(
        templateId: newId('tpl'),
        updatedAt: DateTime.now(),
        name: name,
        groupName: _group ?? '',
        roots: imported.roots,
        subjectInfo: imported.subjectInfo,
        signature: imported.signature,
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _newGroup() async {
    final name = await askName(context, 'New template group');
    if (name == null || !mounted) return;
    if (_groups.any((n) => n.toLowerCase() == name.toLowerCase())) {
      showMessage(context, 'That group already exists.');
      return;
    }
    await context.read<TemplatesRepository>().addGroup(name);
    if (!mounted) return;
    setState(() => _group = name);
    await _load();
  }

  Future<void> _move(TemplateDoc doc) async {
    final target = await showItemActions(context, 'Move to group', [
      const ItemAction('ungrouped', 'Ungrouped', Icons.folder_off_outlined),
      for (var i = 0; i < _groups.length; i++)
        ItemAction('group:$i', _groups[i], Icons.folder_outlined),
      const ItemAction('new', 'New group', Icons.create_new_folder_outlined),
    ]);
    if (target == null || !mounted) return;
    String group = '';
    if (target == 'new') {
      final name = await askName(context, 'New template group');
      if (name == null || !mounted) return;
      if (_groups.any((n) => n.toLowerCase() == name.toLowerCase())) {
        group = _groups.firstWhere(
          (n) => n.toLowerCase() == name.toLowerCase(),
        );
      } else {
        await context.read<TemplatesRepository>().addGroup(name);
        group = name;
      }
    } else if (target.startsWith('group:')) {
      group = _groups[int.parse(target.substring(6))];
    }
    if (!mounted) return;
    await context.read<TemplatesRepository>().saveTemplate(
      doc.copyWith(groupName: group, updatedAt: DateTime.now()),
    );
  }

  Future<void> _menu(TemplateSummary t) async {
    final action = await showItemActions(context, t.name, const [
      ItemAction('use', 'Use template', Icons.note_add_outlined),
      ItemAction('edit', 'Edit template', Icons.edit_outlined),
      ItemAction('rename', 'Rename', Icons.drive_file_rename_outline),
      ItemAction('duplicate', 'Duplicate', Icons.copy_outlined),
      ItemAction('export', 'Export template', Icons.ios_share),
      ItemAction('group', 'Move to group', Icons.drive_file_move_outlined),
      ItemAction(
        'delete',
        'Delete template',
        Icons.delete_outline,
        destructive: true,
      ),
    ]);
    if (action == null || !mounted) return;
    await _run(() async {
      final repo = context.read<TemplatesRepository>();
      if (action == 'use') {
        await _use(t);
        return;
      }
      if (action == 'edit') {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TemplateEditorScreen(templateId: t.templateId),
          ),
        );
      } else if (action == 'delete') {
        if (!await confirmAction(
              context,
              'Delete template?',
              'Delete “${t.name}”? Existing reports, PDFs, Records and logs are kept.',
            ) ||
            !mounted) {
          return;
        }
        await repo.deleteTemplate(t.templateId);
      } else {
        final doc = await repo.loadTemplate(t.templateId);
        if (!mounted) return;
        if (action == 'group') {
          await _move(doc);
        }
        if (action == 'export') {
          await exportTemplate(doc);
        }
        if (action == 'rename' || action == 'duplicate') {
          if (action == 'duplicate' &&
              (!await canAddTemplate(context) || !mounted)) {
            return;
          }
          if (!mounted) return;
          final name = await askName(
            context,
            action == 'rename' ? 'Rename template' : 'Duplicate template',
            initial: action == 'rename' ? t.name : '${t.name} (copy)',
          );
          if (name == null) return;
          await repo.saveTemplate(
            action == 'rename'
                ? doc.copyWith(name: name, updatedAt: DateTime.now())
                : copyTemplate(doc, name),
          );
        }
      }
      if (mounted) await _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TemplateListProvider>();
    final templates = vm.templates
        .where((t) => _group == null || t.groupName == _group)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Templates'),
        actions: [
          IconButton(
            tooltip: 'New group',
            onPressed: _busy ? null : () => _run(_newGroup),
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
          IconButton(
            tooltip: 'Import template',
            onPressed: _busy ? null : () => _run(_import),
            icon: const Icon(Icons.file_upload_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy || vm.loading) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_group),
                      initialValue: _group == null
                          ? '__all__'
                          : _group!.isEmpty
                          ? ''
                          : 'name:$_group',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Template group',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '__all__',
                          child: Text('All templates'),
                        ),
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Ungrouped'),
                        ),
                        for (final g in _groups)
                          DropdownMenuItem(
                            value: 'name:$g',
                            child: Text(g, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      // Group values are namespaced so user names cannot collide with filters.
                      onChanged: _busy
                          ? null
                          : (v) => setState(
                              () => _group = v == '__all__'
                                  ? null
                                  : v == ''
                                  ? ''
                                  : v!.substring(5),
                            ),
                    ),
                  ),
                  if (_group != null && _group!.isNotEmpty)
                    IconButton(
                      tooltip: 'Remove group',
                      icon: const Icon(Icons.folder_delete_outlined),
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              if (!await confirmAction(
                                    context,
                                    'Remove group?',
                                    'Move all templates in “$_group” to Ungrouped? No templates will be deleted.',
                                    action: 'Remove group',
                                  ) ||
                                  !context.mounted) {
                                return;
                              }
                              await context
                                  .read<TemplatesRepository>()
                                  .removeGroup(_group!);
                              if (mounted) {
                                setState(() => _group = null);
                                await _load();
                              }
                            }),
                    ),
                ],
              ),
            ),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Tap to start a report. Hold a template or tap ⋮ for options.',
              ),
            ),
            Expanded(
              child: templates.isEmpty
                  ? const Center(child: Text('No templates in this group.'))
                  : RefreshIndicator(
                      onRefresh: () => _run(_load),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
                        itemCount: templates.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final t = templates[i];
                          return Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.fromLTRB(
                                16,
                                8,
                                8,
                                8,
                              ),
                              title: Text(
                                t.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Updated ${readableDate(t.updatedAt)}${_group == null && t.groupName.isNotEmpty ? '\n${t.groupName}' : ''}',
                                ),
                              ),
                              onTap: _busy ? null : () => _run(() => _use(t)),
                              onLongPress: _busy ? null : () => _menu(t),
                              trailing: IconButton(
                                tooltip: 'Options for ${t.name}',
                                onPressed: _busy ? null : () => _menu(t),
                                icon: const Icon(Icons.more_vert),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
