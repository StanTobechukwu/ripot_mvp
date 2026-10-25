import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

bool get ripotIsNativeDesktop =>
    !kIsWeb &&
    const {
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }.contains(defaultTargetPlatform);

String _safePdfName(String fileName) {
  final trimmed = fileName.trim();
  final base = trimmed.isEmpty ? 'Ripot_Report.pdf' : trimmed;
  final normalized = base.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
  return normalized.toLowerCase().endsWith('.pdf') ? normalized : '$normalized.pdf';
}

Future<File> _writePdfToDirectory({
  required Directory dir,
  required Uint8List bytes,
  required String fileName,
}) async {
  await dir.create(recursive: true);
  final file = File('${dir.path}/${_safePdfName(fileName)}');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<File> ripotWritePdfToShareLocation(Uint8List bytes, String fileName) async {
  final dir = await getApplicationSupportDirectory();
  return _writePdfToDirectory(dir: dir, bytes: bytes, fileName: fileName);
}

Future<File?> ripotDownloadPdf({required Uint8List bytes, required String fileName}) async {
  final safeName = _safePdfName(fileName);

  if (ripotIsNativeDesktop) {
    final location = await getSaveLocation(
      suggestedName: safeName,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PDF', extensions: ['pdf']),
      ],
    );
    if (location == null) return null;
    final path = location.path.toLowerCase().endsWith('.pdf') ? location.path : '${location.path}.pdf';
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  final targetDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  return _writePdfToDirectory(dir: targetDir, bytes: bytes, fileName: safeName);
}


String _safeExportName(String fileName, String fallback, String extension) {
  final trimmed = fileName.trim();
  final base = trimmed.isEmpty ? fallback : trimmed;
  final normalized = base.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
  return normalized.toLowerCase().endsWith('.$extension') ? normalized : '$normalized.$extension';
}

String _safeCsvName(String fileName) => _safeExportName(fileName, 'Ripot_Records.csv', 'csv');
String _safePackageName(String fileName) => _safeExportName(fileName, 'Ripot_Records_Backup.ripotpackage.zip', 'zip');

Future<File> _writeCsvToDirectory({
  required Directory dir,
  required Uint8List bytes,
  required String fileName,
}) async {
  await dir.create(recursive: true);
  final file = File('${dir.path}/${_safeCsvName(fileName)}');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<File> _writePackageToDirectory({
  required Directory dir,
  required Uint8List bytes,
  required String fileName,
}) async {
  await dir.create(recursive: true);
  final file = File('${dir.path}/${_safePackageName(fileName)}');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<File> ripotWriteCsvToShareLocation(Uint8List bytes, String fileName) async {
  final dir = await getApplicationSupportDirectory();
  return _writeCsvToDirectory(dir: dir, bytes: bytes, fileName: fileName);
}

Future<File?> ripotDownloadCsv({required Uint8List bytes, required String fileName}) async {
  final safeName = _safeCsvName(fileName);
  if (ripotIsNativeDesktop) {
    final location = await getSaveLocation(
      suggestedName: safeName,
      acceptedTypeGroups: const [XTypeGroup(label: 'CSV', extensions: ['csv'])],
    );
    if (location == null) return null;
    final path = location.path.toLowerCase().endsWith('.csv') ? location.path : '${location.path}.csv';
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
  final targetDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  return _writeCsvToDirectory(dir: targetDir, bytes: bytes, fileName: safeName);
}

Future<File?> ripotDownloadRecordsPackage({required Uint8List bytes, required String fileName}) async {
  final safeName = _safePackageName(fileName);
  if (ripotIsNativeDesktop) {
    final location = await getSaveLocation(
      suggestedName: safeName,
      acceptedTypeGroups: const [XTypeGroup(label: 'Ripot records package', extensions: ['zip', 'ripotpackage'])],
    );
    if (location == null) return null;
    final path = location.path.toLowerCase().endsWith('.zip') ? location.path : '${location.path}.zip';
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
  final targetDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  return _writePackageToDirectory(dir: targetDir, bytes: bytes, fileName: safeName);
}

Future<File> ripotWritePackageToShareLocation(Uint8List bytes, String fileName) async {
  final dir = await getApplicationSupportDirectory();
  return _writePackageToDirectory(dir: dir, bytes: bytes, fileName: fileName);
}

Future<void> ripotShareCsv({required Uint8List bytes, required String fileName}) async {
  final safeName = _safeCsvName(fileName);
  final file = await ripotWriteCsvToShareLocation(bytes, safeName);
  if (!await file.exists()) {
    throw FileSystemException('Shared CSV could not be created', file.path);
  }
  final datePart = safeName
      .replaceFirst('Ripot_Records_', '')
      .replaceFirst('.csv', '');
  await Share.shareXFiles(
    [XFile(file.path, name: safeName, mimeType: 'text/csv')],
    subject: 'Ripot records export - $datePart',
    text: 'Attached is the Ripot records CSV export.',
  );
}

Future<void> ripotShareRecordsPackage({required Uint8List bytes, required String fileName}) async {
  final safeName = _safePackageName(fileName);
  final file = await ripotWritePackageToShareLocation(bytes, safeName);
  if (!await file.exists()) {
    throw FileSystemException('Shared records package could not be created', file.path);
  }
  await Share.shareXFiles(
    [XFile(file.path, name: safeName, mimeType: 'application/zip')],
    subject: safeName,
    text: 'Attached is a Ripot records package. Import it from Records > Import / Merge in Ripot.',
  );
}

Future<void> ripotPrintPdf({required Uint8List bytes, required String fileName}) {
  return Printing.layoutPdf(name: _safePdfName(fileName), onLayout: (_) async => bytes);
}

Future<void> ripotSharePdf({required Uint8List bytes, required String fileName}) async {
  final file = await ripotWritePdfToShareLocation(bytes, fileName);
  if (!await file.exists()) {
    throw FileSystemException('Shared PDF could not be created', file.path);
  }
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'application/pdf')],
    subject: _safePdfName(fileName),
  );
}
