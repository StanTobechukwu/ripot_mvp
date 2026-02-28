import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readFileBytes(String path) async {
  if (path.isEmpty) return null;
  final f = File(path);
  if (!await f.exists()) return null;
  final bytes = await f.readAsBytes();
  if (bytes.isEmpty) return null;
  return bytes;
}
