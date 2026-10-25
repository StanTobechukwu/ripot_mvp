import 'dart:convert';
import 'dart:typed_data';

Future<Uint8List?> readFileBytes(String path) async {
  if (path.isEmpty) return null;
  if (!path.startsWith('data:')) return null;
  final comma = path.indexOf(',');
  if (comma == -1 || comma == path.length - 1) return null;
  try {
    final bytes = base64Decode(path.substring(comma + 1));
    return bytes.isEmpty ? null : bytes;
  } catch (_) {
    return null;
  }
}
