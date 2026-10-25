import 'dart:typed_data';
import '../../../core/web/file_download.dart';

class BackupFolder {
  bool get supportsRotation => false;
  Future<String?> location() async => null;
  Future<String?> choose() async => null;
  Future<String?> write(Uint8List bytes) async {
    await downloadBytes(
      bytes: bytes,
      fileName:
          'ripot-logbook-${DateTime.now().toUtc().millisecondsSinceEpoch}.ripotbackup',
    );
    return 'Download started. Confirm the file was saved, then keep a copy off this device. Browser downloads are not automatically rotated.';
  }
}
