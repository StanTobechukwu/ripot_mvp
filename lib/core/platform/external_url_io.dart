import 'dart:io';

Future<bool> openExternalUrl(String rawUrl) async {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;

  try {
    if (Platform.isWindows) {
      await Process.start(
        'rundll32',
        ['url.dll,FileProtocolHandler', uri.toString()],
        mode: ProcessStartMode.detached,
      );
      return true;
    }
  } catch (_) {
    return false;
  }
  return false;
}
