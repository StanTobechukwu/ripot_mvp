import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ripot/features/reports/domain/models/report_doc.dart';
import 'package:ripot/features/reports/domain/models/nodes.dart';
import 'package:ripot/features/reports/domain/pdf/pdf_plan.dart';
import 'package:ripot/features/reports/services/pdf_renderer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('report PDF embeds a Unicode font and maps the prime character', () async {
    final doc = ReportDoc(
      reportId: 'prime-demo', createdAtIso: '2026-09-17', updatedAtIso: '2026-09-17',
      reportTitle: 'Fictional echo example',
      roots: const [SectionNode(id: 'diastolic', title: 'Diastolic function',
        children: [ContentNode(id: 'values', text: 'E/E′: 10.74\nSeptal E′: 0.06 m/s\nLateral E′: 0.08 m/s')])],
    );
    final bytes = await PdfRendererService().generatePdfBytes(
      doc: doc,
      plan: const PdfPlan(title: 'Fictional echo example', inlineEnabled: false,
        pageOne: PageOnePlan(inlineImages: []),
        finalContent: FinalContentPlan(spillInlineImages: []), attachmentPages: []),
    );
    final raw = latin1.decode(bytes);
    expect(raw, startsWith('%PDF-'));
    expect(raw, contains('/FontFile2'));
    final decoded = StringBuffer(raw);
    for (final match in RegExp(r'stream\r?\n([\s\S]*?)\r?\nendstream').allMatches(raw)) {
      try { decoded.write(latin1.decode(zlib.decode(latin1.encode(match.group(1)!)))); }
      catch (_) { /* Non-compressed streams are already in raw. */ }
    }
    expect(decoded.toString().toLowerCase(), contains('2032'));
    final output = Platform.environment['RIPOT_QA_PDF'];
    if (output != null) await File(output).writeAsBytes(bytes);
  });
}
