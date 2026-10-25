import 'dart:typed_data';

bool get ripotTemplateIsNativeDesktop => false;

Future<void> ripotExportTemplateFile({
  required Uint8List bytes,
  required String fileName,
  required String templateName,
}) async {
  throw UnsupportedError('Template file export is not available on this platform.');
}
