import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/ids.dart';
import '../data/templates_repository.dart';
import '../domain/models/template_doc.dart';
import '../domain/serialization/template_codec.dart';
import '../providers/template_list_provider.dart';
import '../providers/report_editor_provider.dart';
import '../providers/reports_list_provider.dart';
import 'report_editor_screen.dart';
import 'template_editor_screen.dart';

class TemplatesListScreen extends StatefulWidget {
  const TemplatesListScreen({super.key});

  @override
  State<TemplatesListScreen> createState() => _TemplatesListScreenState();
}

class _TemplatesListScreenState extends State<TemplatesListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TemplateListProvider>().load();
    });
  }

  Future<_TemplateOpenChoice?> _askOpenChoice(BuildContext context) {
    return showDialog<_TemplateOpenChoice>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Open template'),
        content: const Text('How do you want to use this template?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _TemplateOpenChoice.fillReport),
            child: const Text('Fill as report'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _TemplateOpenChoice.editTemplate),
            child: const Text('Edit template'),
          ),
        ],
      ),
    );
  }


  Future<void> _importTemplate(BuildContext context) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Ripot template'),
        content: const Text('Import only templates exported from Ripot. Patient records, saved reports, and PDFs are not imported.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Choose file')),
        ],
      ),
    );
    if (proceed != true) return;

    try {
      final picked = await FilePicker.platform.pickFiles(
        // Pick broadly because WhatsApp/Telegram/file managers may rename
        // custom files or hide compound extensions. The payload is validated
        // below before anything is imported.
        type: FileType.any,
        withData: true,
      );
      if (!mounted || picked == null || picked.files.isEmpty) return;
      final bytes = picked.files.first.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('The selected file could not be read.');
      }

      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('This is not a valid Ripot template file.');
      }
      if (decoded['app'] != 'Ripot' || decoded['ripotFileType'] != 'template') {
        throw const FormatException('This file does not contain a Ripot template.');
      }
      final templateJson = decoded['template'];
      if (templateJson is! Map) {
        throw const FormatException('Template data is missing.');
      }
      final imported = TemplateCodec.templateFromJson(templateJson.cast<String, dynamic>());

      final name = await _promptImportName(context, imported.name);
      if (!mounted || name == null) return;
      final template = TemplateDoc(
        templateId: newId('tpl'),
        updatedAt: DateTime.now(),
        name: name,
        roots: imported.roots,
        subjectInfo: imported.subjectInfo,
        signature: imported.signature,
      );
      await context.read<TemplatesRepository>().saveTemplate(template);
      if (!mounted) return;
      await context.read<TemplateListProvider>().load();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported template: ${template.name}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Future<String?> _promptImportName(BuildContext context, String initialName) async {
    var value = initialName.trim().isEmpty ? 'Imported Template' : initialName.trim();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import template'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('A valid Ripot template file was found. It will be imported as a separate copy.'),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: value,
              decoration: const InputDecoration(labelText: 'Template name', border: OutlineInputBorder()),
              onChanged: (v) => value = v,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final trimmed = value.trim();
              Navigator.pop(ctx, trimmed.isEmpty ? null : trimmed);
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteTemplate(BuildContext context, TemplateSummary template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete template?'),
        content: Text(
          'This will delete “${template.name}”. Existing reports, PDFs, and records created from this template will not be deleted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete Template')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<TemplateListProvider>().delete(template.templateId);
  }

  @override
  Widget build(BuildContext context) {
    final listVm = context.watch<TemplateListProvider>();
    final repo = context.read<TemplatesRepository>();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Templates'),
        actions: [
          IconButton(
            tooltip: 'Import Template',
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: () => _importTemplate(context),
          ),
        ],
      ),
      body: Builder(
        builder: (_) {
          if (listVm.loading) return const Center(child: CircularProgressIndicator());
          if (listVm.templates.isEmpty) {
            return const Center(child: Text('No templates yet. Create one from the Report Editor.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: listVm.templates.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final t = listVm.templates[i];
              return Card(
                child: ListTile(
                  title: Text(t.name),
                  subtitle: Text('Updated: ${t.updatedAt}'),
                  onTap: () async {
                    final choice = await _askOpenChoice(context);
                    if (choice == null) return;

                    if (choice == _TemplateOpenChoice.fillReport) {
                      final template = await repo.loadTemplate(t.templateId);
                      context.read<ReportEditorProvider>().newReportFromTemplate(template);
                      if (!context.mounted) return;
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ReportEditorScreen()),
                      );
                      if (!context.mounted) return;
                      await context.read<TemplateListProvider>().load();
                      await context.read<ReportsListProvider>().refresh();
                      return;
                    }

                    if (!context.mounted) return;
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TemplateEditorScreen(templateId: t.templateId),
                      ),
                    );
                    if (!context.mounted) return;
                    await context.read<TemplateListProvider>().load();
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmDeleteTemplate(context, t),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

enum _TemplateOpenChoice { fillReport, editTemplate }
