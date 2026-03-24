import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/models/report_doc.dart';
import '../domain/serialization/report_codec.dart';

class ReportSummary {
  final String reportId;
  final String title;
  final String subtitle;
  final DateTime updatedAt;

  const ReportSummary({
    required this.reportId,
    required this.title,
    required this.subtitle,
    required this.updatedAt,
  });
}

class ReportsRepository {
  Future<Directory> _reportsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/reports');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _pdfDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/saved_pdfs');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _reportFile(String reportId) async {
    final dir = await _reportsDir();
    return File('${dir.path}/$reportId.json');
  }


  Future<File> pdfFileForReport(String reportId, {ReportDoc? doc}) async {
    final dir = await _pdfDir();
    final reportDir = Directory('${dir.path}/$reportId');
    if (!await reportDir.exists()) {
      await reportDir.create(recursive: true);
    }

    if (doc != null) {
      final fileName = _pdfFileNameFor(doc);
      final existing = reportDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.pdf'))
          .toList();
      for (final f in existing) {
        try {
          await f.delete();
        } catch (_) {}
      }
      return File('${reportDir.path}/$fileName');
    }

    final existing = reportDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.pdf'))
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    if (existing.isNotEmpty) return existing.first;

    final legacy = File('${dir.path}/$reportId.pdf');
    return legacy;
  }

  Future<void> saveReport(ReportDoc doc) async {
    final f = await _reportFile(doc.reportId);
    final jsonMap = ReportCodec.reportToJson(doc);
    await f.writeAsString(jsonEncode(jsonMap), flush: true);
  }

  Future<ReportDoc> loadReport(String reportId) async {
    final f = await _reportFile(reportId);
    final text = await f.readAsString();
    return ReportCodec.reportFromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  Future<void> deleteReport(String reportId) async {
    final f = await _reportFile(reportId);
    if (await f.exists()) await f.delete();

    final dir = await _pdfDir();
    final reportDir = Directory('${dir.path}/$reportId');
    if (await reportDir.exists()) {
      await reportDir.delete(recursive: true);
    }

    final legacy = File('${dir.path}/$reportId.pdf');
    if (await legacy.exists()) await legacy.delete();
  }

  Future<List<ReportSummary>> listReports() async {
    final dir = await _reportsDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();

    final summaries = <ReportSummary>[];
    for (final f in files) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final doc = ReportCodec.reportFromJson(j);
        final updated = DateTime.parse(doc.updatedAtIso);
        final title = _displayTitleFor(doc);
        final subtitle = _displaySubtitleFor(doc, updated);

        summaries.add(ReportSummary(
          reportId: doc.reportId,
          title: title,
          subtitle: subtitle,
          updatedAt: updated,
        ));
      } catch (_) {
        // ignore corrupted file
      }
    }

    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
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
