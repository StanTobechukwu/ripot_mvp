import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readFileBytes(String path) async {
  if (path.isEmpty) return null;
  if (path.startsWith('data:')) {
    final comma = path.indexOf(',');
    if (comma == -1 || comma == path.length - 1) return null;
    try {
      final bytes = base64Decode(path.substring(comma + 1));
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  final f = File(path);
  if (!await f.exists()) return null;
  final bytes = await f.readAsBytes();
  if (bytes.isEmpty) return null;
  return bytes;
}
