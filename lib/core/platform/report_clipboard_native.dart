import 'package:flutter/services.dart';

import 'report_clipboard_data.dart';

const _channel = MethodChannel('ripot/report_clipboard');

Future<void> writeReportClipboard(ReportClipboardData data) async {
  if (data.html != null) {
    try {
      await _channel.invokeMethod<void>('write', {
        'text': data.text,
        'html': data.html,
      });
      return;
    } on MissingPluginException {
      // Platforms without the native bridge still receive the entire draft.
    }
  }
  await Clipboard.setData(ClipboardData(text: data.text));
}
