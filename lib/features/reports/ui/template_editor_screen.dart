import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/ids.dart';
import '../../../core/web/file_download.dart';
import '../../records/data/records_repository.dart';
import '../data/reports_repository.dart';

import '../../access/providers/access_provider.dart';
import '../../access/ui/upgrade_screen.dart';
import '../data/templates_repository.dart';
import '../domain/models/nodes.dart';
import '../domain/models/template_doc.dart';
import '../domain/models/report_doc.dart';
import '../domain/serialization/template_codec.dart';
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
            appBar: AppBar(centerTitle: true, title: const Text('Edit Template')),
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

enum _UnsavedTemplateAction { save, discard, cancel }

class _TemplateEditorBody extends StatelessWidget {
  const _TemplateEditorBody();

  Future<bool> _save(BuildContext context, {bool showSnackBar = true}) async {
    final repo = context.read<TemplatesRepository>();
    final vm = context.read<TemplateEditorProvider>();
    final access = context.read<AccessProvider>().safeState;

    try {
      final templates = await repo.listTemplates();
      final isExisting = templates.any((t) => t.templateId == vm.template.templateId);
      if (!isExisting && templates.length >= access.maxSavedTemplates) {
        if (!context.mounted) return false;
        final open = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Template limit reached'),
            content: Text('Free plan allows up to ${access.maxSavedTemplates} templates. Start a premium trial to save more.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Later')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('See Premium')),
            ],
          ),
        );
        if (open == true && context.mounted) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const UpgradeScreen()));
        }
        return false;
      }

      final doc = vm.buildForSave(name: vm.template.name, includeContent: false);
      await repo.saveTemplate(doc);
      vm.markSaved();
      if (!context.mounted) return true;
      if (showSnackBar) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template updated')),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save template: $e')),
        );
      }
      return false;
    }
  }

  Future<void> _handleAttemptedExit(BuildContext context) async {
    final vm = context.read<TemplateEditorProvider>();
    if (!vm.hasUnsavedChanges) {
      Navigator.of(context).pop();
      return;
    }

    final action = await showDialog<_UnsavedTemplateAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save template changes?'),
        content: const Text('You have unsaved changes in this template.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, _UnsavedTemplateAction.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, _UnsavedTemplateAction.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, _UnsavedTemplateAction.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (!context.mounted || action == null || action == _UnsavedTemplateAction.cancel) return;

    if (action == _UnsavedTemplateAction.discard) {
      Navigator.of(context).pop();
      return;
    }

    final saved = await _save(context, showSnackBar: false);
    if (saved && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<String?> _promptText(
    BuildContext context,
    String title, {
    String hint = 'Type…',
    String initialValue = '',
  }) async {
    String value = initialValue;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initialValue,
          autofocus: true,
          decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
          onChanged: (v) => value = v,
          onFieldSubmitted: (_) => Navigator.pop(ctx, value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, value.trim()), child: const Text('OK')),
        ],
      ),
    );
    final trimmed = (result ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }


  String _safeTemplateFileName(String name) {
    final cleaned = name
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._ -]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final base = cleaned.isEmpty ? 'Ripot_Template' : cleaned;
    return base.toLowerCase().endsWith('.ripot_template') ? base : '$base.ripot_template';
  }

  Future<void> _renameTemplate(BuildContext context) async {
    final vm = context.read<TemplateEditorProvider>();
    final name = await _promptText(
      context,
      'Rename template',
      hint: vm.template.name,
      initialValue: vm.template.name,
    );
    if (name == null) return;
    vm.renameTemplate(name);
    await _save(context, showSnackBar: false);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Template renamed')));
  }

  Future<void> _duplicateTemplate(BuildContext context) async {
    final repo = context.read<TemplatesRepository>();
    final vm = context.read<TemplateEditorProvider>();
    final name = await _promptText(
      context,
      'Duplicate template as',
      hint: '${vm.template.name} copy',
      initialValue: '${vm.template.name} copy',
    );
    if (name == null) return;

    final source = vm.buildForSave(name: vm.template.name, includeContent: false);
    final duplicate = TemplateDoc(
      templateId: newId('tpl'),
      updatedAt: DateTime.now(),
      name: name,
      roots: source.roots,
      subjectInfo: source.subjectInfo,
      signature: source.signature,
    );
    await repo.saveTemplate(duplicate);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Template duplicated')));
  }

  Future<void> _exportTemplate(BuildContext context) async {
    final vm = context.read<TemplateEditorProvider>();
    final template = vm.buildForSave(name: vm.template.name, includeContent: false);
    final payload = <String, dynamic>{
      'app': 'Ripot',
      'ripotFileType': 'template',
      'ripotExportVersion': 1,
      'exportedAtIso': DateTime.now().toIso8601String(),
      'template': TemplateCodec.templateToJson(template),
    };
    final pretty = const JsonEncoder.withIndent('  ').convert(payload);
    final bytes = Uint8List.fromList(utf8.encode(pretty));
    final fileName = _safeTemplateFileName(template.name);

    if (kIsWeb) {
      await downloadBytes(bytes: bytes, fileName: fileName);
    } else {
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: fileName, mimeType: 'application/json')],
        text: 'Ripot template: ${template.name}',
      );
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Template exported: $fileName')));
  }

  Future<void> _deleteTemplate(BuildContext context) async {
    final repo = context.read<TemplatesRepository>();
    final vm = context.read<TemplateEditorProvider>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete template?'),
        content: Text('This will delete “${vm.template.name}”. Existing reports and PDFs will not be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await repo.deleteTemplate(vm.template.templateId);
    if (!context.mounted) return;
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('Template deleted')));
  }

  Future<void> _syncExistingRecords(BuildContext context) async {
    final vm = context.read<TemplateEditorProvider>();
    final reportsRepo = context.read<ReportsRepository>();
    final recordsRepo = context.read<RecordsRepository>();
    final template = vm.buildForSave(name: vm.template.name, includeContent: false);
    final saveToRecordTitles = <String>[];
    void collect(SectionNode section) {
      if (section.addToRecords) saveToRecordTitles.add(section.title);
      for (final child in section.children.whereType<SectionNode>()) {
        collect(child);
      }
    }
    for (final root in template.roots) {
      collect(root);
    }
    if (saveToRecordTitles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No template fields are marked Save to Records.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sync existing records?'),
        content: Text(
          'Ripot will scan saved editable reports that match this template structure and update their record data using fields currently marked Save to Records.\n\n'
          'Saved PDFs will not be changed.\n\n'
          'Fields: ${saveToRecordTitles.take(8).join(', ')}${saveToRecordTitles.length > 8 ? '…' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sync')),
        ],
      ),
    );
    if (confirm != true) return;

    final summaries = await reportsRepo.listReports();
    var scanned = 0;
    var matched = 0;
    var updated = 0;
    for (final summary in summaries) {
      try {
        final report = await reportsRepo.loadReport(summary.reportId);
        scanned += 1;
        if (!_reportLooksLikeTemplate(report, template)) continue;
        matched += 1;
        final patched = report.copyWith(roots: _applyTemplateRecordSettings(report.roots, template.roots));
        final draft = await recordsRepo.buildDraftForReport(patched);
        await recordsRepo.saveRecord(draft);
        updated += 1;
      } catch (_) {
        // Keep sync best-effort so one bad saved work does not stop the batch.
      }
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sync complete. Scanned: $scanned, matched: $matched, updated: $updated. PDFs unchanged.')),
    );
  }

  bool _reportLooksLikeTemplate(ReportDoc report, TemplateDoc template) {
    final reportTitles = report.roots.map((s) => s.title.trim().toLowerCase()).where((e) => e.isNotEmpty).toList();
    final templateTitles = template.roots.map((s) => s.title.trim().toLowerCase()).where((e) => e.isNotEmpty).toList();
    if (reportTitles.isEmpty || templateTitles.isEmpty) return false;
    if (reportTitles.length != templateTitles.length) return false;
    for (var i = 0; i < templateTitles.length; i += 1) {
      if (reportTitles[i] != templateTitles[i]) return false;
    }
    return true;
  }

  List<SectionNode> _applyTemplateRecordSettings(List<SectionNode> reportRoots, List<SectionNode> templateRoots) {
    final settingsByPath = <String, SectionNode>{};
    void collect(List<SectionNode> sections, String prefix) {
      for (final section in sections) {
        final path = '$prefix/${section.title.trim().toLowerCase()}';
        settingsByPath[path] = section;
        collect(section.children.whereType<SectionNode>().toList(growable: false), path);
      }
    }
    collect(templateRoots, '');

    SectionNode patch(SectionNode section, String prefix) {
      final path = '$prefix/${section.title.trim().toLowerCase()}';
      final templateSection = settingsByPath[path];
      return section.copyWith(
        showInPdf: true,
        addToRecords: templateSection?.addToRecords ?? section.addToRecords,
        inputType: templateSection?.inputType ?? section.inputType,
        options: templateSection?.options ?? section.options,
        conditionalParentSectionId: templateSection?.conditionalParentSectionId ?? section.conditionalParentSectionId,
        conditionalEquals: templateSection?.conditionalEquals ?? section.conditionalEquals,
        children: section.children.map((child) {
          if (child is SectionNode) return patch(child, path);
          return child;
        }).toList(growable: false),
      );
    }

    return reportRoots.map((root) => patch(root, '')).toList(growable: false);
  }

  Future<void> _handleTemplateMenu(BuildContext context, String action) async {
    switch (action) {
      case 'duplicate':
        await _duplicateTemplate(context);
        break;
      case 'rename':
        await _renameTemplate(context);
        break;
      case 'sync':
        await _syncExistingRecords(context);
        break;
      case 'export':
        await _exportTemplate(context);
        break;
      case 'delete':
        await _deleteTemplate(context);
        break;
    }
  }


  List<SectionNode> _allSectionsExcept(List<SectionNode> roots, String excludedId) {
    final out = <SectionNode>[];
    void walk(SectionNode section) {
      if (section.id != excludedId) out.add(section);
      for (final child in section.children.whereType<SectionNode>()) {
        walk(child);
      }
    }
    for (final root in roots) {
      walk(root);
    }
    return out;
  }

  Future<void> _showSectionActions(BuildContext context, SectionNode section) async {
    final vm = context.read<TemplateEditorProvider>();
    final useResponsiveSheet = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;

    Widget sheetContent(BuildContext ctx) {
      return Column(
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
            title: const Text('Edit section'),
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
      );
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: useResponsiveSheet,
      builder: (ctx) {
        if (!useResponsiveSheet) {
          return SafeArea(child: sheetContent(ctx));
        }

        final availableHeight = MediaQuery.of(ctx).size.height;
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: availableHeight * 0.85),
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 16),
              child: sheetContent(ctx),
            ),
          ),
        );
      },
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
          isScrollControlled: true,
          builder: (_) => _SectionEditSheet(section: section, possibleParents: _allSectionsExcept(vm.template.roots, section.id)),
        );
        if (res != null) {
          if ((res.rename ?? '').trim().isNotEmpty) vm.renameSection(section.id, res.rename!.trim());
          if (res.style != null) vm.updateSectionStyle(section.id, res.style!);
          vm.updateSectionFieldSettings(
            section.id,
            inputType: res.inputType,
            options: res.options,
            addToRecords: res.addToRecords,
            conditionalParentSectionId: res.conditionalParentSectionId,
            conditionalEquals: res.conditionalEquals,
          );
        }
        break;
      case 'up':
        vm.moveSectionUp(section.id);
        break;
      case 'down':
        vm.moveSectionDown(section.id);
        break;
      case 'rename':
        final title = await _promptText(context, 'Edit section title', hint: section.title, initialValue: section.title);
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
                    if (section.addToRecords) ...[
                      Tooltip(
                        message: 'Added to Records',
                        child: Icon(
                          Icons.fact_check_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
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
    return PopScope(
      canPop: !vm.hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleAttemptedExit(context);
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(vm.template.name),
          leading: BackButton(
            onPressed: () => _handleAttemptedExit(context),
          ),
          actions: [
            IconButton(
              tooltip: 'Save',
              icon: const Icon(Icons.save_outlined),
              onPressed: () => _save(context),
            ),
            PopupMenuButton<String>(
              tooltip: 'Template options',
              onSelected: (value) => _handleTemplateMenu(context, value),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'duplicate', child: Text('Duplicate Template')),
                PopupMenuItem(value: 'rename', child: Text('Rename Template')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'sync', child: Text('Sync Existing Records')),
                PopupMenuItem(value: 'export', child: Text('Export Template')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'delete', child: Text('Delete Template')),
              ],
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
      ),
    );
  }
}

class _SectionEditResult {
  final String? rename;
  final TitleStyle? style;
  final FieldInputType? inputType;
  final List<String>? options;
  final bool? addToRecords;
  final String? conditionalParentSectionId;
  final String? conditionalEquals;
  const _SectionEditResult({
    this.rename,
    this.style,
    this.inputType,
    this.options,
    this.addToRecords,
    this.conditionalParentSectionId,
    this.conditionalEquals,
  });
}

class _SectionEditSheet extends StatefulWidget {
  final SectionNode section;
  final List<SectionNode> possibleParents;
  const _SectionEditSheet({required this.section, this.possibleParents = const []});

  @override
  State<_SectionEditSheet> createState() => _SectionEditSheetState();
}

class _SectionEditSheetState extends State<_SectionEditSheet> {
  late final TextEditingController _title;
  late HeadingLevel _level;
  late bool _bold;
  late TitleAlign _align;
  late FieldInputType _inputType;
  late final TextEditingController _options;
  late bool _addToRecords;
  late bool _useCondition;
  late String _conditionParentId;
  late final TextEditingController _conditionEquals;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.section.title);
    _level = widget.section.style.level;
    _bold = widget.section.style.bold;
    _align = widget.section.style.align;
    _inputType = widget.section.inputType;
    _options = TextEditingController(text: widget.section.options.join('\n'));
    _addToRecords = widget.section.addToRecords;
    _useCondition = widget.section.hasCondition;
    _conditionParentId = widget.section.conditionalParentSectionId;
    if (_conditionParentId.isEmpty && widget.possibleParents.isNotEmpty) {
      _conditionParentId = widget.possibleParents.first.id;
    }
    _conditionEquals = TextEditingController(text: widget.section.conditionalEquals);
  }

  @override
  void dispose() {
    _title.dispose();
    _options.dispose();
    _conditionEquals.dispose();
    super.dispose();
  }

  List<String> _parsedOptions() {
    return _options.text
        .split(RegExp(r'[\n,;]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.88;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text('Edit section'),
                  subtitle: Text('These settings affect this template field in future reports.'),
                  contentPadding: EdgeInsets.zero,
                ),
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Formatting',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
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
                const Divider(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Field behavior',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<FieldInputType>(
                  initialValue: _inputType,
                  decoration: const InputDecoration(
                    labelText: 'Input type',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: FieldInputType.values
                      .map((type) => DropdownMenuItem(value: type, child: Text(type.label)))
                      .toList(),
                  onChanged: (v) => setState(() => _inputType = v ?? _inputType),
                ),
                if (_inputType != FieldInputType.freeText) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _options,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: _inputType == FieldInputType.yesNo ? 'Options' : 'Options / suggestions',
                      hintText: _inputType == FieldInputType.yesNo ? 'Yes and No are used automatically' : 'One option per line, or comma-separated',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    enabled: _inputType != FieldInputType.yesNo,
                  ),
                ],
                CheckboxListTile(
                  value: _addToRecords,
                  onChanged: (v) => setState(() => _addToRecords = v ?? false),
                  title: const Text('Save to Records'),
                  subtitle: const Text('Store this field as searchable/exportable data.'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                const Divider(height: 24),
                SwitchListTile(
                  value: _useCondition,
                  onChanged: widget.possibleParents.isEmpty
                      ? null
                      : (v) => setState(() => _useCondition = v),
                  title: const Text('Show conditionally'),
                  subtitle: Text(
                    widget.possibleParents.isEmpty
                        ? 'Add another field first to use it as the parent.'
                        : 'Example: show Biopsy Site only when Biopsy Taken is Yes.',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                if (_useCondition && widget.possibleParents.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: widget.possibleParents.any((s) => s.id == _conditionParentId)
                        ? _conditionParentId
                        : widget.possibleParents.first.id,
                    decoration: const InputDecoration(
                      labelText: 'Parent field',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: widget.possibleParents
                        .map((section) => DropdownMenuItem<String>(
                              value: section.id,
                              child: Text(section.title, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(growable: false),
                    onChanged: (value) => setState(() => _conditionParentId = value ?? ''),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _conditionEquals,
                    decoration: const InputDecoration(
                      labelText: 'Show when parent value is',
                      hintText: 'e.g. Yes or Abnormal',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final options = _inputType == FieldInputType.yesNo
                          ? const <String>['Yes', 'No']
                          : _parsedOptions();
                      Navigator.pop(context, _SectionEditResult(
                        rename: _title.text.trim(),
                        style: widget.section.style.copyWith(level: _level, bold: _bold, align: _align),
                        inputType: _inputType,
                        options: options,
                        addToRecords: _addToRecords,
                        conditionalParentSectionId: _useCondition ? _conditionParentId : '',
                        conditionalEquals: _useCondition ? _conditionEquals.text.trim() : '',
                      ));
                    },
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
