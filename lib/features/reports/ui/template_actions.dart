import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/utils/ids.dart';
import '../../../core/web/file_download.dart';
import '../../access/providers/access_provider.dart';
import '../../access/ui/premium_prompt.dart';
import '../data/templates_repository.dart';
import '../domain/models/template_doc.dart';
import '../domain/models/nodes.dart';
import '../domain/serialization/template_codec.dart';
import '../services/template_file_actions.dart';

Future<bool> canAddTemplate(BuildContext context) async {
  final access = context.read<AccessProvider>().safeState;
  final templates = await context.read<TemplatesRepository>().listTemplates();
  if (!context.mounted) return false;
  if (templates.where((t) => !t.isBuiltIn).length < access.maxSavedTemplates)
    return true;
  if (!access.isPremiumLike) {
    await showPremiumFeatureSheet(context, PremiumFeature.moreTemplates);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Your plan supports ${access.maxSavedTemplates} saved templates. Remove an unused template to add another.',
        ),
      ),
    );
  }
  return false;
}

TemplateDoc copyTemplate(TemplateDoc source, String name) => TemplateDoc(
  templateId: newId('tpl'),
  updatedAt: DateTime.now(),
  name: name,
  groupName: source.groupName,
  roots: source.roots
      .map((s) => s.toTemplateNode(includeContent: false))
      .toList(),
  subjectInfo: source.subjectInfo,
  signature: source.signature,
);

Future<void> exportTemplate(TemplateDoc source) async {
  final template = source.copyWith(
    roots: source.roots
        .map((s) => s.toTemplateNode(includeContent: false))
        .toList(),
  );
  final bytes = Uint8List.fromList(
    utf8.encode(
      const JsonEncoder.withIndent('  ').convert({
        'app': 'Ripot',
        'ripotFileType': 'template',
        'ripotExportVersion': 1,
        'exportedAtIso': DateTime.now().toIso8601String(),
        'template': TemplateCodec.templateToJson(template),
      }),
    ),
  );
  final name = source.name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
  final fileName =
      '${name.isEmpty ? 'Ripot_Template' : name}.ripottemplate${!kIsWeb && !ripotTemplateIsNativeDesktop ? '.json' : ''}';
  if (kIsWeb) {
    await downloadBytes(bytes: bytes, fileName: fileName);
  } else {
    await ripotExportTemplateFile(
      bytes: bytes,
      fileName: fileName,
      templateName: source.name,
    );
  }
}
