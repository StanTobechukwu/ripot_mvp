import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../features/records/data/records_repository.dart';
import '../../features/reports/data/reports_repository.dart';
import '../../features/reports/data/templates_repository.dart';
import '../../features/reports/domain/models/template_doc.dart';
import '../../features/reports/domain/serialization/template_codec.dart';
import '../utils/ids.dart';

class IncomingFileResult {
  const IncomingFileResult(this.message, {this.changed = false});

  final String message;
  final bool changed;
}

class IncomingFileService {
  IncomingFileService({
    required this.templatesRepository,
    required this.recordsRepository,
    required this.reportsRepository,
  });

  static const _channel = MethodChannel('ripot/incoming_file');

  final TemplatesRepository templatesRepository;
  final RecordsRepository recordsRepository;
  final ReportsRepository reportsRepository;

  void listen(void Function(IncomingFileResult result) onResult) {
    if (kIsWeb) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'incomingFile') return null;
      final result = await handlePayload(call.arguments);
      if (result != null) onResult(result);
      return null;
    });
  }

  Future<IncomingFileResult?> handleInitialFile() async {
    if (kIsWeb) return null;
    try {
      final payload = await _channel.invokeMethod<dynamic>('getInitialFile');
      return handlePayload(payload);
    } catch (_) {
      return null;
    }
  }

  Future<IncomingFileResult?> handlePayload(dynamic payload) async {
    if (payload is! Map) return null;
    final name = (payload['name'] ?? 'file').toString();
    final base64 = payload['bytesBase64'];
    if (base64 is! String || base64.trim().isEmpty) return null;

    late final Uint8List bytes;
    try {
      bytes = Uint8List.fromList(base64Decode(base64));
    } catch (_) {
      return const IncomingFileResult('Could not read the selected file.');
    }
    return importBytes(bytes, fileName: name);
  }

  Future<IncomingFileResult> importBytes(Uint8List bytes, {required String fileName}) async {
    final lower = fileName.toLowerCase();

    // Try package first for ZIP-like files, but content validation is the real check.
    if (lower.endsWith('.zip') || lower.endsWith('.ripotpackage') || _looksLikeZip(bytes)) {
      final result = await _tryImportRecordsPackage(bytes);
      if (result != null) return result;
    }

    final text = _decodeText(bytes);
    final templateResult = await _tryImportTemplate(text);
    if (templateResult != null) return templateResult;

    final csvResult = await _tryImportRecordsCsv(text);
    if (csvResult != null) return csvResult;

    return const IncomingFileResult('This file is not a recognised Ripot template, records CSV, or records package.');
  }

  bool _looksLikeZip(Uint8List bytes) {
    return bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;
  }

  String _decodeText(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  Future<IncomingFileResult?> _tryImportTemplate(String text) async {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      if (decoded['app'] != 'Ripot' || decoded['ripotFileType'] != 'template') return null;
      final templateJson = decoded['template'];
      if (templateJson is! Map) return const IncomingFileResult('This Ripot template file is missing template data.');
      final imported = TemplateCodec.templateFromJson(templateJson.cast<String, dynamic>());
      final template = TemplateDoc(
        templateId: newId('tpl'),
        updatedAt: DateTime.now(),
        name: _importedTemplateName(imported.name),
        roots: imported.roots,
        subjectInfo: imported.subjectInfo,
        signature: imported.signature,
      );
      await templatesRepository.saveTemplate(template);
      return IncomingFileResult('Template imported: ${template.name}', changed: true);
    } catch (_) {
      return null;
    }
  }

  String _importedTemplateName(String rawName) {
    final base = rawName.trim().isEmpty ? 'Imported Template' : rawName.trim();
    return '$base (Imported)';
  }

  Future<IncomingFileResult?> _tryImportRecordsCsv(String text) async {
    try {
      final result = await recordsRepository.mergeRipotCsv(text);
      return IncomingFileResult(
        'Records merged. Imported: ${result.imported}, Updated: ${result.updated}, Duplicates skipped: ${result.duplicatesSkipped}',
        changed: result.totalChanged > 0,
      );
    } on FormatException {
      return null;
    } catch (e) {
      return IncomingFileResult('Records CSV merge failed: $e');
    }
  }

  Future<IncomingFileResult?> _tryImportRecordsPackage(Uint8List bytes) async {
    late final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return null;
    }

    final manifestFile = archive.findFile('manifest.json');
    final csvFile = archive.findFile('records.csv');
    if (manifestFile == null || csvFile == null) return null;

    try {
      final manifestText = _decodeText(Uint8List.fromList(List<int>.from(manifestFile.content as List)));
      final manifest = jsonDecode(manifestText);
      if (manifest is! Map || manifest['app'] != 'Ripot' || manifest['exportType'] != 'recordsPackage') {
        return null;
      }
      final csvText = _decodeText(Uint8List.fromList(List<int>.from(csvFile.content as List)));
      final mergeResult = await recordsRepository.mergeRipotCsv(csvText);
      var importedPdfs = 0;
      for (final item in archive.files) {
        if (!item.isFile || !item.name.startsWith('pdfs/') || !item.name.toLowerCase().endsWith('.pdf')) continue;
        final name = item.name.split('/').last;
        final separator = name.indexOf('__');
        if (separator <= 0) continue;
        final recordId = name.substring(0, separator);
        final entry = await recordsRepository.loadByRecordId(recordId);
        if (entry == null) continue;
        try {
          final content = Uint8List.fromList(List<int>.from(item.content as List));
          final pdfName = name.substring(separator + 2);
          await reportsRepository.importPdfBytesForReport(entry.linkedReportId, content, fileName: pdfName);
          importedPdfs += 1;
        } catch (_) {}
      }
      return IncomingFileResult(
        'Records package merged. Imported: ${mergeResult.imported}, Updated: ${mergeResult.updated}, PDFs: $importedPdfs',
        changed: mergeResult.totalChanged > 0 || importedPdfs > 0,
      );
    } catch (e) {
      return IncomingFileResult('Records package merge failed: $e');
    }
  }
}
