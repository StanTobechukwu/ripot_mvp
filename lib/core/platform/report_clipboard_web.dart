import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import 'report_clipboard_data.dart';

Future<void> writeReportClipboard(ReportClipboardData data) async {
  if (data.html != null) {
    try {
      final item = web.ClipboardItem({
        'text/plain': web.Blob([data.text.toJS].toJS,
            web.BlobPropertyBag(type: 'text/plain')),
        'text/html': web.Blob([data.html!.toJS].toJS,
            web.BlobPropertyBag(type: 'text/html')),
      }.jsify()! as JSObject);
      await web.window.navigator.clipboard.write([item].toJS).toDart;
      return;
    } catch (_) {
      // A browser may support text copying but not HTML. If both fail, the
      // service keeps its short authorization so a new tap can retry for free.
    }
  }
  await Clipboard.setData(ClipboardData(text: data.text));
}
