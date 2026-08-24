import 'dart:typed_data';

Future<void> savePdfFile(String reportId, Uint8List bytes) async {
  throw UnsupportedError(
    'Filesystem PDF storage is not available on this platform.',
  );
}

Future<Uint8List?> loadPdfFile(String reportId) async {
  return null;
}

Future<bool> pdfFileExists(String reportId) async {
  return false;
}

Future<void> deletePdfFile(String reportId) async {}
