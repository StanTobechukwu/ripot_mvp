/// Two representations of the same complete draft. Neither leaves the device.
class ReportClipboardData {
  const ReportClipboardData({required this.text, this.html});

  final String text;
  final String? html;
}
