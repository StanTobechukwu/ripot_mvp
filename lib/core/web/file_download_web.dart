// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> downloadBytes({required List<int> bytes, required String fileName}) async {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final lowerName = fileName.toLowerCase();
  final mimeType = lowerName.endsWith('.csv')
      ? 'text/csv'
      : lowerName.endsWith('.zip')
          ? 'application/zip'
          : 'application/pdf';
  final blob = html.Blob([data], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
