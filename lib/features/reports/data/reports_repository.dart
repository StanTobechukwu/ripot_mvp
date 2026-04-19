import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/report_doc.dart';
import '../domain/serialization/report_codec.dart';

class ReportSummary {
  final String reportId;
  final String title;
  final String subtitle;
  final DateTime updatedAt;
  final bool hasPdf;
  final bool isFinalized;

  const ReportSummary({
    required this.reportId,
    required this.title,
    required this.subtitle,
    required this.updatedAt,
    required this.hasPdf,
    required this.isFinalized,
  });

  bool get isFinalReport => hasPdf;
  bool get isSavedWork => !hasPdf;
  bool get canContinueEditing => !isFinalized;
}

class ReportsRepository {
  static const _reportsIndexKey = 'reports.index';
  static const _reportPrefix = 'reports.doc.';
  static const _pdfPrefix = 'reports.pdf.';
  static const _pdfNamePrefix = 'reports.pdfname.';
  static const _finalizedPrefix = 'reports.finalized.';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  String _reportKey(String reportId) => '$_reportPrefix$reportId';
  String _pdfKey(String reportId) => '$_pdfPrefix$reportId';
  String _pdfNameKey(String reportId) => '$_pdfNamePrefix$reportId';
  String _finalizedKey(String reportId) => '$_finalizedPrefix$reportId';

  Future<List<String>> _readIndex() async {
    final prefs = await _prefs;
    return prefs.getStringList(_reportsIndexKey) ?? <String>[];
  }

  Future<void> _writeIndex(List<String> ids) async {
    final prefs = await _prefs;
    await prefs.setStringList(_reportsIndexKey, ids);
  }

  Future<void> saveReport(ReportDoc doc) async {
    final prefs = await _prefs;
    await prefs.setString(_reportKey(doc.reportId), jsonEncode(ReportCodec.reportToJson(doc)));
    final ids = await _readIndex();
    ids.remove(doc.reportId);
    ids.insert(0, doc.reportId);
    await _writeIndex(ids);
  }

  Future<ReportDoc> loadReport(String reportId) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_reportKey(reportId));
    if (raw == null || raw.trim().isEmpty) {
      throw Exception('Report not found');
    }
    return ReportCodec.reportFromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> deleteReport(String reportId) async {
    final prefs = await _prefs;
    await prefs.remove(_reportKey(reportId));
    await prefs.remove(_pdfKey(reportId));
    await prefs.remove(_pdfNameKey(reportId));
    await prefs.remove(_finalizedKey(reportId));
    final ids = await _readIndex();
    ids.remove(reportId);
    await _writeIndex(ids);
  }

  Future<List<ReportSummary>> listReports() async {
    final prefs = await _prefs;
    final ids = await _readIndex();
    final summaries = <ReportSummary>[];

    for (final id in ids) {
      final raw = prefs.getString(_reportKey(id));
      if (raw == null || raw.trim().isEmpty) continue;
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final doc = ReportCodec.reportFromJson(j);
        final updated = DateTime.parse(doc.updatedAtIso);
        final hasPdf = (prefs.getString(_pdfKey(doc.reportId)) ?? '').trim().isNotEmpty;
        final isFinalized = prefs.getBool(_finalizedKey(doc.reportId)) ?? false;
        summaries.add(
          ReportSummary(
            reportId: doc.reportId,
            title: _displayTitleFor(doc),
            subtitle: _displaySubtitleFor(doc, updated),
            updatedAt: updated,
            hasPdf: hasPdf,
            isFinalized: isFinalized,
          ),
        );
      } catch (_) {}
    }

    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
  }

  Future<void> savePdfBytesForReport(
    String reportId,
    Uint8List bytes, {
    required ReportDoc doc,
  }) async {
    final prefs = await _prefs;
    await prefs.setString(_pdfKey(reportId), base64Encode(bytes));
    await prefs.setString(_pdfNameKey(reportId), _pdfFileNameFor(doc));
    await prefs.setBool(_finalizedKey(reportId), false);
  }

  Future<void> markReportAsFinal(String reportId) async {
    final prefs = await _prefs;
    await prefs.setBool(_finalizedKey(reportId), true);
  }

  Future<bool> isReportFinalized(String reportId) async {
    final prefs = await _prefs;
    return prefs.getBool(_finalizedKey(reportId)) ?? false;
  }

  Future<Uint8List?> loadPdfBytesForReport(String reportId) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_pdfKey(reportId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final bytes = base64Decode(raw);
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  Future<String?> pdfFileNameForReport(String reportId) async {
    final prefs = await _prefs;
    return prefs.getString(_pdfNameKey(reportId));
  }

  String pdfFileNameForDoc(ReportDoc doc) => _pdfFileNameFor(doc);

  String _pdfFileNameFor(ReportDoc doc) {
    final type = _reportTypeFor(doc);
    final dt = DateTime.tryParse(doc.updatedAtIso) ?? DateTime.now();
    final yyyy = dt.year.toString().padLeft(4, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    return '${type}_Report_${yyyy}-${mm}-${dd}.pdf';
  }

  String _reportTypeFor(ReportDoc doc) {
    final explicit = doc.reportTitle.trim();
    if (explicit.isNotEmpty) return _sanitizeFileSegment(explicit);
    if (doc.roots.isNotEmpty) {
      final first = doc.roots.first.title.trim();
      if (first.isNotEmpty) return _sanitizeFileSegment(first);
    }
    return 'Ripot';
  }

  String _sanitizeFileSegment(String input) {
    final cleaned = input
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (cleaned.isEmpty) return 'Ripot';
    return cleaned.length <= 40 ? cleaned : cleaned.substring(0, 40);
  }

  String _displaySubtitleFor(ReportDoc doc, DateTime updatedAt) {
    final subjectName = doc.subjectInfo.valueOf('subjectName').trim();
    final subjectId = doc.subjectInfo.valueOf('subjectId').trim();
    final stamp = _formatDateTime(updatedAt);
    if (subjectName.isNotEmpty) return '$subjectName • $stamp';
    if (subjectId.isNotEmpty) return 'ID: $subjectId • $stamp';
    return stamp;
  }

  String _formatDateTime(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}, $hh:$mm';
  }

  String _displayTitleFor(ReportDoc doc) {
    final explicit = doc.reportTitle.trim();
    if (explicit.isNotEmpty) return explicit;

    final subjectName = doc.subjectInfo.valueOf('subjectName').trim();
    if (subjectName.isNotEmpty) {
      final firstSection = doc.roots.isNotEmpty ? doc.roots.first.title.trim() : '';
      if (firstSection.isNotEmpty) return '$subjectName - $firstSection';
      return subjectName;
    }

    if (doc.roots.isNotEmpty) {
      final firstSection = doc.roots.first.title.trim();
      if (firstSection.isNotEmpty) return firstSection;
    }

    final dt = DateTime.tryParse(doc.updatedAtIso) ?? DateTime.now();
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    return 'Report $mm-$dd-${dt.year}';
  }
}
