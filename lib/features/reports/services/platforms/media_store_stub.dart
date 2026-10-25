import 'dart:convert';
import 'dart:typed_data';

Future<String> savePortableBytes(
  Uint8List bytes, {
  required String fileStem,
  required String extension,
  required String mimeType,
}) async {
  return 'data:$mimeType;base64,${base64Encode(bytes)}';
}
