import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

bool get ripotTemplateIsNativeDesktop =>
    !kIsWeb &&
    const {
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }.contains(defaultTargetPlatform);

String _safeName(String name) {
  final trimmed = name.trim().isEmpty ? 'Ripot_Template.ripottemplate' : name.trim();
  return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
}

Future<void> ripotExportTemplateFile({
  required Uint8List bytes,
  required String fileName,
  required String templateName,
}) async {
  final safeName = _safeName(fileName);

  if (ripotTemplateIsNativeDesktop) {
    final location = await getSaveLocation(
      suggestedName: safeName,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Ripot template', extensions: ['ripottemplate', 'json']),
      ],
    );
    if (location == null) return;
    final lower = location.path.toLowerCase();
    final path = lower.endsWith('.ripottemplate') || lower.endsWith('.json')
        ? location.path
        : '${location.path}.ripottemplate';
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return;
  }

  // Mobile: WhatsApp/Telegram handle real files more reliably than raw in-memory
  // XFile data. Keep the final .json extension so common apps preserve it.
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$safeName');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles(
    [XFile(file.path, name: safeName, mimeType: 'application/json')],
    subject: 'Ripot template: $templateName',
    text: 'Ripot template: $templateName',
  );
}
