import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<File> _pdfFile(String reportId) async {
  final dir = await getApplicationDocumentsDirectory();

  final reportsDir = Directory('${dir.path}/reports');
  if (!await reportsDir.exists()) {
    await reportsDir.create(recursive: true);
  }

  return File('${reportsDir.path}/$reportId.pdf');
}

Future<void> savePdfFile(String reportId, Uint8List bytes) async {
  final file = await _pdfFile(reportId);
  await file.writeAsBytes(bytes, flush: true);
}

Future<Uint8List?> loadPdfFile(String reportId) async {
  final file = await _pdfFile(reportId);

  if (!await file.exists()) {
    return null;
  }

  final bytes = await file.readAsBytes();
  return bytes.isEmpty ? null : bytes;
}

Future<bool> pdfFileExists(String reportId) async {
  final file = await _pdfFile(reportId);
  return file.exists();
}

Future<void> deletePdfFile(String reportId) async {
  final file = await _pdfFile(reportId);

  if (await file.exists()) {
    await file.delete();
  }
}
