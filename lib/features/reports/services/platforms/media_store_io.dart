import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String> savePortableBytes(
  Uint8List bytes, {
  required String fileStem,
  required String extension,
  required String mimeType,
}) async {
  final dir = await getApplicationDocumentsDirectory();
  final safeExt = extension.replaceAll('.', '');
  final file = File('${dir.path}/${fileStem}_${DateTime.now().millisecondsSinceEpoch}.$safeExt');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
