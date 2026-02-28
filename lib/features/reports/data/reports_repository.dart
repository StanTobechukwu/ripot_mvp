import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/models/report_doc.dart';
import '../domain/serialization/report_codec.dart';

class ReportSummary {
  final String reportId;
  final String title;
  final DateTime updatedAt;

  const ReportSummary({
    required this.reportId,
    required this.title,
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

  Future<File> _reportFile(String reportId) async {
    final dir = await _reportsDir();
    return File('${dir.path}/$reportId.json');
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
        final id = j['reportId'] as String;
        final updated = DateTime.parse(j['updatedAtIso'] as String);

        // Title heuristic: first section title if exists, else fallback
        final roots = (j['roots'] as List?) ?? const [];
        final title = roots.isNotEmpty ? (roots.first['title'] as String? ?? 'Untitled Report') : 'Untitled Report';

        summaries.add(ReportSummary(reportId: id, title: title, updatedAt: updated));
      } catch (_) {
        // ignore corrupted file
      }
    }

    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
  }
}
