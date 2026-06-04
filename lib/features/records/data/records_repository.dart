import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/ids.dart';
import '../../../core/utils/time.dart';
import '../../reports/domain/models/report_doc.dart';
import '../../reports/domain/models/nodes.dart';
import '../domain/record_models.dart';


class RecordsMergeResult {
  final int imported;
  final int updated;
  final int duplicatesSkipped;
  final int invalidRows;

  const RecordsMergeResult({
    required this.imported,
    required this.updated,
    required this.duplicatesSkipped,
    required this.invalidRows,
  });

  int get totalChanged => imported + updated;
}

class RecordsRepository {
  static const _recordsIndexKey = 'records.index';
  static const _recordPrefix = 'records.doc.';
  static const _recordLinkPrefix = 'records.byreport.';
  static const _vocabPrefix = 'records.vocab.';
  static const _customFieldsKey = 'records.custom_fields';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  String _recordKey(String recordEntryId) => '$_recordPrefix$recordEntryId';
  String _recordLinkKey(String reportId) => '$_recordLinkPrefix$reportId';
  String _vocabKey(String fieldKey) => '$_vocabPrefix$fieldKey';

  Future<List<String>> _readIndex() async {
    final prefs = await _prefs;
    return prefs.getStringList(_recordsIndexKey) ?? <String>[];
  }

  Future<void> _writeIndex(List<String> ids) async {
    final prefs = await _prefs;
    await prefs.setStringList(_recordsIndexKey, ids);
  }

  Future<List<RecordFieldDef>> loadCustomFields() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_customFieldsKey);
    if (raw == null || raw.trim().isEmpty) return <RecordFieldDef>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => RecordFieldDef.fromJson((e as Map).cast<String, dynamic>()))
          .where((field) => field.key.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return <RecordFieldDef>[];
    }
  }

  Future<void> saveCustomField({required String label, String hint = '', String procedureScope = ''}) async {
    final trimmedLabel = label.trim();
    if (trimmedLabel.isEmpty) return;
    final current = await loadCustomFields();
    final slug = trimmedLabel
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    var key = slug.isEmpty ? newId('field') : slug;
    final existingKeys = {...RecordFieldCatalog.coreFields.map((e) => e.key), ...current.map((e) => e.key)};
    var n = 2;
    final baseKey = key;
    while (existingKeys.contains(key)) {
      key = '${baseKey}_$n';
      n += 1;
    }
    final updated = [
      ...current,
      RecordFieldDef(
        key: key,
        label: trimmedLabel,
        hint: hint.trim().isEmpty ? 'Extra record field' : hint.trim(),
        isSystem: false,
        procedureScope: procedureScope.trim(),
      ),
    ];
    final prefs = await _prefs;
    await prefs.setString(_customFieldsKey, jsonEncode(updated.map((e) => e.toJson()).toList(growable: false)));
  }


  Future<void> deleteCustomField(String fieldKey) async {
    final trimmedKey = fieldKey.trim();
    if (trimmedKey.isEmpty) return;

    final current = await loadCustomFields();
    final updatedFields = current.where((f) => f.key != trimmedKey).toList(growable: false);
    final prefs = await _prefs;
    await prefs.setString(_customFieldsKey, jsonEncode(updatedFields.map((e) => e.toJson()).toList(growable: false)));
    await prefs.remove(_vocabKey(trimmedKey));

    final ids = await _readIndex();
    for (final id in ids) {
      final raw = prefs.getString(_recordKey(id));
      if (raw == null || raw.trim().isEmpty) continue;
      try {
        final entry = RecordEntry.decode(raw);
        if (!entry.values.containsKey(trimmedKey)) continue;
        final values = Map<String, String>.from(entry.values)..remove(trimmedKey);
        final updatedEntry = entry.copyWith(
          updatedAtIso: DateTime.now().toIso8601String(),
          values: values,
        );
        await prefs.setString(_recordKey(id), updatedEntry.encode());
      } catch (_) {}
    }
  }

  Future<List<RecordFieldDef>> allFields() async => [...RecordFieldCatalog.coreFields, ...await loadCustomFields()];

  Future<List<RecordSummary>> listRecords() async {
    final prefs = await _prefs;
    final ids = await _readIndex();
    final out = <RecordSummary>[];

    for (final id in ids) {
      final raw = prefs.getString(_recordKey(id));
      if (raw == null || raw.trim().isEmpty) continue;
      try {
        final entry = RecordEntry.decode(raw);
        out.add(
          RecordSummary(
            recordEntryId: entry.recordEntryId,
            linkedReportId: entry.linkedReportId,
            procedure: entry.valueOf(RecordFieldCatalog.procedure.key),
            diagnosis: entry.valueOf(RecordFieldCatalog.diagnosis.key),
            reportDate: entry.valueOf(RecordFieldCatalog.reportDate.key),
            patientReference: entry.valueOf(RecordFieldCatalog.patientReference.key),
            updatedAt: DateTime.tryParse(entry.updatedAtIso) ?? DateTime.now(),
            values: entry.values,
          ),
        );
      } catch (_) {}
    }

    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<RecordEntry?> loadByRecordId(String recordEntryId) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_recordKey(recordEntryId));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return RecordEntry.decode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<RecordEntry?> loadByReportId(String reportId) async {
    final prefs = await _prefs;
    final recordId = prefs.getString(_recordLinkKey(reportId));
    if (recordId == null || recordId.isEmpty) return null;
    return loadByRecordId(recordId);
  }

  Future<void> saveRecord(RecordEntry entry) async {
    final prefs = await _prefs;
    await prefs.setString(_recordKey(entry.recordEntryId), entry.encode());
    await prefs.setString(_recordLinkKey(entry.linkedReportId), entry.recordEntryId);

    final ids = await _readIndex();
    ids.remove(entry.recordEntryId);
    ids.insert(0, entry.recordEntryId);
    await _writeIndex(ids);

    final allFieldsList = await allFields();
    for (final field in allFieldsList) {
      final value = entry.valueOf(field.key);
      if (value.isEmpty) continue;
      await saveVocabularyValue(field.key, value);
    }
  }

  Future<void> deleteRecord(String recordEntryId) async {
    final prefs = await _prefs;
    final existing = await loadByRecordId(recordEntryId);
    await prefs.remove(_recordKey(recordEntryId));
    if (existing != null) {
      await prefs.remove(_recordLinkKey(existing.linkedReportId));
    }
    final ids = await _readIndex();
    ids.remove(recordEntryId);
    await _writeIndex(ids);
  }

  Future<List<String>> searchVocabulary(String fieldKey, String query) async {
    final prefs = await _prefs;
    final saved = prefs.getStringList(_vocabKey(fieldKey)) ?? <String>[];
    final builtIn = (RecordFieldCatalog.byKey(fieldKey)?.builtInSuggestions ?? const <String>[]);
    final merged = <String>{...builtIn, ...saved}.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return merged;
    return merged.where((v) => v.toLowerCase().contains(trimmed)).toList(growable: false);
  }

  Future<void> saveVocabularyValue(String fieldKey, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final prefs = await _prefs;
    final existing = prefs.getStringList(_vocabKey(fieldKey)) ?? <String>[];
    existing.removeWhere((e) => e.toLowerCase() == trimmed.toLowerCase());
    existing.insert(0, trimmed);
    final capped = existing.take(100).toList(growable: false);
    await prefs.setStringList(_vocabKey(fieldKey), capped);
  }


  String buildRipotCsv({required List<RecordSummary> records, required List<RecordFieldDef> fields}) {
    final orderedKeys = [
      ...RecordFieldCatalog.exportDefaultKeys,
      ...fields.where((f) => !RecordFieldCatalog.exportDefaultKeys.contains(f.key)).map((f) => f.key),
    ];
    final fieldKeys = <String>[];
    for (final key in orderedKeys) {
      if (!fieldKeys.contains(key)) fieldKeys.add(key);
    }

    String esc(String value) => '"${value.replaceAll('"', '""')}"';
    final buffer = StringBuffer();
    final headers = <String>[
      'ripotExportVersion',
      'ripotRecordId',
      'ripotLinkedReportId',
      'ripotCreatedAtIso',
      'ripotUpdatedAtIso',
      ...fieldKeys,
    ];
    buffer.writeln(headers.map(esc).join(','));
    for (final row in records) {
      final entryValues = row.values;
      final cells = <String>[
        '1',
        row.recordEntryId,
        row.linkedReportId,
        '',
        row.updatedAt.toIso8601String(),
        ...fieldKeys.map((key) => key == RecordFieldCatalog.reportDate.key ? _csvDate(entryValues[key] ?? '') : (entryValues[key] ?? '')),
      ];
      buffer.writeln(cells.map(esc).join(','));
    }
    return buffer.toString();
  }

  Future<RecordsMergeResult> mergeRipotCsv(String csvText) async {
    final rows = _parseCsv(csvText);
    if (rows.isEmpty) {
      throw const FormatException('The selected file is empty.');
    }
    final headers = rows.first.map((e) => e.trim()).toList(growable: false);
    final hasMarker = headers.contains('ripotExportVersion') && headers.contains('ripotRecordId');
    if (!hasMarker) {
      throw const FormatException('This file does not look like a Ripot records export. Please select a CSV exported from Ripot.');
    }

    var imported = 0;
    var updated = 0;
    var duplicatesSkipped = 0;
    var invalidRows = 0;

    for (final row in rows.skip(1)) {
      final map = <String, String>{};
      for (var i = 0; i < headers.length; i += 1) {
        map[headers[i]] = i < row.length ? row[i] : '';
      }
      final recordId = (map['ripotRecordId'] ?? '').trim();
      if (recordId.isEmpty) {
        invalidRows += 1;
        continue;
      }
      final linkedReportId = (map['ripotLinkedReportId'] ?? map[RecordFieldCatalog.reportId.key] ?? '').trim();
      final importedUpdatedAt = (map['ripotUpdatedAtIso'] ?? '').trim();
      final updatedAt = DateTime.tryParse(importedUpdatedAt) ?? DateTime.now();
      final createdAtIso = (map['ripotCreatedAtIso'] ?? '').trim().isNotEmpty
          ? (map['ripotCreatedAtIso'] ?? '').trim()
          : updatedAt.toIso8601String();
      final values = <String, String>{};
      for (final header in headers) {
        if (header.startsWith('ripot')) continue;
        values[header] = (map[header] ?? '').trim();
      }
      if ((values[RecordFieldCatalog.reportId.key] ?? '').trim().isEmpty && linkedReportId.isNotEmpty) {
        values[RecordFieldCatalog.reportId.key] = linkedReportId;
      }
      final incoming = RecordEntry(
        recordEntryId: recordId,
        linkedReportId: linkedReportId.isEmpty ? recordId : linkedReportId,
        createdAtIso: createdAtIso,
        updatedAtIso: updatedAt.toIso8601String(),
        values: values,
      );

      final existing = await loadByRecordId(recordId);
      if (existing == null) {
        await saveRecord(incoming);
        imported += 1;
      } else {
        final existingUpdatedAt = DateTime.tryParse(existing.updatedAtIso) ?? DateTime.fromMillisecondsSinceEpoch(0);
        if (updatedAt.isAfter(existingUpdatedAt)) {
          await saveRecord(incoming.copyWith(createdAtIso: existing.createdAtIso.isNotEmpty ? existing.createdAtIso : incoming.createdAtIso));
          updated += 1;
        } else {
          duplicatesSkipped += 1;
        }
      }
    }

    return RecordsMergeResult(
      imported: imported,
      updated: updated,
      duplicatesSkipped: duplicatesSkipped,
      invalidRows: invalidRows,
    );
  }

  String _csvDate(String value) {
    final parsed = DateTime.tryParse(value.trim());
    if (parsed == null) return value.trim();
    return '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }

  List<List<String>> _parseCsv(String text) {
    final rows = <List<String>>[];
    final currentRow = <String>[];
    final current = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i += 1) {
      final char = text[i];
      if (char == '"') {
        if (inQuotes && i + 1 < text.length && text[i + 1] == '"') {
          current.write('"');
          i += 1;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        currentRow.add(current.toString());
        current.clear();
      } else if ((char == '\n' || char == '\r') && !inQuotes) {
        if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') i += 1;
        currentRow.add(current.toString());
        current.clear();
        if (currentRow.any((cell) => cell.trim().isNotEmpty)) {
          rows.add(List<String>.from(currentRow));
        }
        currentRow.clear();
      } else {
        current.write(char);
      }
    }
    currentRow.add(current.toString());
    if (currentRow.any((cell) => cell.trim().isNotEmpty)) {
      rows.add(List<String>.from(currentRow));
    }
    return rows;
  }

  Future<RecordEntry> buildDraftForReport(ReportDoc doc) async {
    final existing = await loadByReportId(doc.reportId);
    if (existing != null) return existing;

    final now = nowIso();
    final created = RecordEntry(
      recordEntryId: newId('rec'),
      linkedReportId: doc.reportId,
      createdAtIso: now,
      updatedAtIso: now,
      values: {
        RecordFieldCatalog.reportId.key: doc.reportId,
        RecordFieldCatalog.reportDate.key: _inferDate(doc),
        RecordFieldCatalog.subjectName.key: _inferSubjectName(doc),
        RecordFieldCatalog.patientReference.key: _inferSubjectId(doc),
        RecordFieldCatalog.procedure.key: _inferProcedure(doc),
        RecordFieldCatalog.diagnosis.key: _inferDiagnosis(doc),
        RecordFieldCatalog.doctor.key: _inferDoctor(doc),
      },
    );
    return created;
  }

  String _inferDate(ReportDoc doc) {
    final rawDate = doc.reportDateIso.trim().isNotEmpty ? doc.reportDateIso : doc.updatedAtIso;
    final date = rawDate.isNotEmpty ? DateTime.tryParse(rawDate) : null;
    if (date == null) return '';
    return date.toIso8601String().split('T').first;
  }

  String _inferSubjectName(ReportDoc doc) => doc.subjectInfo.valueOf('subjectName');

  String _inferSubjectId(ReportDoc doc) => doc.subjectInfo.valueOf('subjectId');

  String _inferProcedure(ReportDoc doc) {
    final title = doc.reportTitle.trim();
    if (title.isNotEmpty) return title;
    for (final root in doc.roots) {
      final rootTitle = root.title.trim();
      if (rootTitle.isNotEmpty) return rootTitle;
    }
    return '';
  }

  String _inferDiagnosis(ReportDoc doc) {
    for (final root in doc.roots) {
      final found = _firstNonEmptyContent(root);
      if (found.isNotEmpty) return found;
    }
    return '';
  }

  String _firstNonEmptyContent(SectionNode section) {
    for (final child in section.children) {
      if (child is ContentNode) {
        final text = child.text.trim();
        if (text.isNotEmpty) return text;
      } else if (child is SectionNode) {
        final nested = _firstNonEmptyContent(child);
        if (nested.isNotEmpty) return nested;
      }
    }
    return '';
  }

  String _inferDoctor(ReportDoc doc) {
    final name = doc.signature.name.trim();
    if (name.isNotEmpty) return name;
    return '';
  }
}
