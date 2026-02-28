import 'dart:typed_data';

/// Web/unsupported stub. Keeps compilation working on Flutter Web.
Future<Uint8List?> readFileBytes(String path) async {
  // On web we don't have direct file system access by path.
  // The app should avoid calling PDF generation that depends on local paths on web.
  return null;
}










