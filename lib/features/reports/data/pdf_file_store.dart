import 'dart:typed_data';

import 'pdf_file_store_stub.dart'
    if (dart.library.io) 'pdf_file_store_io.dart'
    as platform;

Future<void> savePdfFile(String reportId, Uint8List bytes) {
  return platform.savePdfFile(reportId, bytes);
}

Future<Uint8List?> loadPdfFile(String reportId) {
  return platform.loadPdfFile(reportId);
}

Future<bool> pdfFileExists(String reportId) {
  return platform.pdfFileExists(reportId);
}

Future<void> deletePdfFile(String reportId) {
  return platform.deletePdfFile(reportId);
}
