import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../domain/logbook_models.dart';
import '../../../core/ui/item_actions.dart' show readableDate;

Future<Uint8List> buildLogbookPdf({
  required List<LogEntry> entries,
  required LogbookData book,
  String doctorId = '',
  String dateRange = 'All dates',
  bool includeDetails = false,
}) async {
  final font = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
  );
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: font, bold: font),
  );
  final doctor = book.doctor(doctorId);
  String names(LogEntry e) => e.data.participants
      .map(
        (p) =>
            '${e.currentSignature?.doctorNames[p.doctorId] ?? book.doctor(p.doctorId)?.name ?? 'Unknown'}: ${p.role.label}${p.supervised ? ' (supervised)' : ''}',
      )
      .join('\n');
  String compactParticipation(LogEntry e) {
    if (doctorId.isNotEmpty) {
      final roles = e.data.participants.where((p) => p.doctorId == doctorId).map((p) => '${p.role.label}${p.supervised ? ' (supervised)' : ''}').toList();
      if (e.data.supervisorId == doctorId) roles.add('Named supervisor');
      return roles.join('\n');
    }
    return ProcedureRole.values.map((role) {
      final count = e.data.participants.where((p) => p.role == role).length;
      return count == 0 ? '' : '${role.label}: $count';
    }).where((s) => s.isNotEmpty).join('\n');
  }
  final counts = {
    for (final role in ProcedureRole.values)
      role: entries
          .where(
            (e) => e.data.participants.any(
              (p) =>
                  (doctorId.isEmpty || p.doctorId == doctorId) &&
                  p.role == role,
            ),
          )
          .length,
  };
  final supervisedCount = entries
      .where(
        (e) =>
            e.data.supervisorId.isNotEmpty &&
            (doctorId.isEmpty || e.data.supervisorId == doctorId),
      )
      .length;
  final signed = entries.where((e) => e.currentSignature != null).length;
  final sorted = [...entries]
    ..sort((a, b) => a.data.procedureDate.compareTo(b.data.procedureDate));
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      maxPages: 10000,
      header: (_) => pw.Text(
        'Ripot Logbook${doctor == null ? '' : ' · ${doctor.name}'}',
        style: pw.TextStyle(fontSize: 16),
      ),
      footer: (c) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Personal procedure log · ${readableDate(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.Text(
            '${c.pageNumber} / ${c.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
      build: (_) => [
        pw.SizedBox(height: 8),
        pw.Text(
          '$dateRange · ${entries.length} entries · $signed with a current signature',
        ),
        pw.Text(
          '${counts.entries.map((e) => '${e.key.label}: ${e.value}').join('   ')}   Named supervisor: $supervisedCount',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.Text(
          'Counts cover only the selected entries. Roles may overlap across doctors. A recorded signature is not independent identity verification or a competency assessment.',
          style: const pw.TextStyle(fontSize: 8),
        ),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: [
            'Date',
            'Procedure',
            'Case reference',
            'Participation',
            'Named supervisor',
            'Signature',
          ],
          data: [
            for (final e in sorted)
              [
                readableDate(e.data.procedureDate),
                e.data.procedure,
                e.data.reference,
                compactParticipation(e),
                book.doctor(e.data.supervisorId)?.name ?? '',
                e.currentSignature == null
                    ? 'Not signed (v${e.revision})'
                    : '${e.currentSignature!.signerName}\nVersion ${e.revision}',
              ],
          ],
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerStyle: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellAlignments: {
            0: pw.Alignment.topLeft,
            1: pw.Alignment.topLeft,
            2: pw.Alignment.topLeft,
            3: pw.Alignment.topLeft,
            4: pw.Alignment.topLeft,
            5: pw.Alignment.topLeft,
          },
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          includeDetails
              ? 'Entry details follow.'
              : 'Summary export: participant names, notes, copied fields and signature images are in entry details. Choose “Include entry details” to include them.',
          style: const pw.TextStyle(fontSize: 8),
        ),
        if (includeDetails)
          for (final e in sorted) ...[
            pw.NewPage(),
            pw.Text(
              '${readableDate(e.data.procedureDate)} · ${e.data.procedure} · v${e.revision}',
              style: pw.TextStyle(fontSize: 14),
            ),
            ..._paragraphs('Participation', names(e)),
            if (e.data.supervisorId.isNotEmpty)
              ..._paragraphs(
                'Named supervisor',
                book.doctor(e.data.supervisorId)?.name ?? '',
              ),
            ..._paragraphs('Facility', e.data.facility),
            ..._paragraphs('Case reference', e.data.reference),
            ..._paragraphs('Outcome / notes', e.data.notes),
            for (final f in e.data.fields) ..._paragraphs(f.label, f.value),
            ..._paragraphs('Report author/signatory', e.data.reportAuthor),
            if (e.currentSignature != null) ...[
              pw.Text(
                'Signature recorded: ${e.currentSignature!.signerName} · ${e.currentSignature!.recordedAt.toLocal()} · Version ${e.revision}',
              ),
              pw.Image(
                pw.MemoryImage(
                  Uint8List.fromList(_signatureBytes(e.currentSignature!)),
                ),
                height: 64,
              ),
            ],
          ],
      ],
    ),
  );
  return doc.save();
}

List<pw.Widget> _paragraphs(String label, String value) {
  if (value.isEmpty) return [];
  // Bounded paragraphs allow long notes to flow across MultiPage boundaries.
  final runes = value.runes.toList();
  return [
    pw.SizedBox(height: 8),
    pw.Text(
      label,
      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
    ),
    for (var i = 0; i < runes.length; i += 800)
      pw.Text(
        String.fromCharCodes(
          runes.sublist(i, i + 800 > runes.length ? runes.length : i + 800),
        ),
        style: const pw.TextStyle(fontSize: 9),
      ),
  ];
}

List<int> _signatureBytes(LogSignature signature) =>
    base64Decode(signature.pngBase64);
