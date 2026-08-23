import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/ids.dart';
import '../../../core/utils/time.dart';
import '../../reports/domain/models/report_doc.dart';
import '../../reports/domain/models/nodes.dart';
import '../domain/record_models.dart';



class _RecordBuildData {
  const _RecordBuildData({required this.values, required this.labels, required this.sources});

  final Map<String, String> values;
  final Map<String, String> labels;
  final Map<String, String> sources;
}

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
  static const _registriesKey = 'records.registries';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  String _recordKey(String recordEntryId) => '$_recordPrefix$recordEntryId';
  String _recordLinkKey(String reportId) => '$_recordLinkPrefix$reportId';
  String _vocabKey(String fieldKey) => '$_vocabPrefix$fieldKey';

  String _scopedVocabKey(String fieldKey, String procedure) {
    final normalizedProcedure = procedure.trim().toLowerCase();
    if (normalizedProcedure.isEmpty) return _vocabKey(fieldKey);
    final safeProcedure = normalizedProcedure
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_\$'), '');
    return '$_vocabPrefix${fieldKey.trim()}::${safeProcedure.isEmpty ? 'general' : safeProcedure}';
  }

  Future<List<String>> _readIndex() async {
    final prefs = await _prefs;
    return prefs.getStringList(_recordsIndexKey) ?? <String>[];
  }

  Future<void> _writeIndex(List<String> ids) async {
    final prefs = await _prefs;
    await prefs.setStringList(_recordsIndexKey, ids);
  }

  Future<List<RecordRegistry>> loadRegistries() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_registriesKey);
    if (raw == null || raw.trim().isEmpty) return <RecordRegistry>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => RecordRegistry.fromJson((e as Map).cast<String, dynamic>()))
          .where((registry) => registry.registryId.trim().isNotEmpty && registry.title.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return <RecordRegistry>[];
    }
  }

  Future<void> _saveRegistries(List<RecordRegistry> registries) async {
    final prefs = await _prefs;
    await prefs.setString(
      _registriesKey,
      jsonEncode(registries.map((e) => e.toJson()).toList(growable: false)),
    );
  }

  Future<RecordRegistry> createRegistry({required String title, String description = ''}) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw ArgumentError('Registry title is required.');
    }
    final registries = await loadRegistries();
    final registry = RecordRegistry(
      registryId: newId('reg'),
      title: trimmedTitle,
      description: description.trim(),
      createdAtIso: DateTime.now().toIso8601String(),
    );
    await _saveRegistries([...registries, registry]);
    return registry;
  }


  Future<void> updateRegistry({
    required String registryId,
    required String title,
    String description = '',
  }) async {
    final trimmedRegistryId = registryId.trim();
    final trimmedTitle = title.trim();
    if (trimmedRegistryId.isEmpty || trimmedTitle.isEmpty) return;
    final registries = await loadRegistries();
    final updated = registries.map((registry) {
      if (registry.registryId != trimmedRegistryId) return registry;
      return registry.copyWith(
        title: trimmedTitle,
        description: description.trim(),
      );
    }).toList(growable: false);
    await _saveRegistries(updated);
  }

  Future<void> addRegistryField({
    required String registryId,
    required String label,
    String hint = '',
    List<String> suggestions = const <String>[],
    String conditionalOnFieldKey = '',
    String conditionalEquals = '',
  }) async {
    final trimmedLabel = label.trim();
    final trimmedRegistryId = registryId.trim();
    if (trimmedRegistryId.isEmpty || trimmedLabel.isEmpty) return;
    final registries = await loadRegistries();
    final updated = <RecordRegistry>[];
    for (final registry in registries) {
      if (registry.registryId != trimmedRegistryId) {
        updated.add(registry);
        continue;
      }
      final baseSlug = _slug(trimmedLabel);
      final existingSameConcept = registry.fields.any((field) =>
          field.label.trim().toLowerCase() == trimmedLabel.toLowerCase());
      if (existingSameConcept) {
        updated.add(registry);
        continue;
      }
      final existingKeys = {
        ...RecordFieldCatalog.coreFields.map((e) => e.key),
        ...registry.fields.map((e) => e.key),
      };
      var key = 'registry_${trimmedRegistryId}_$baseSlug';
      var n = 2;
      while (existingKeys.contains(key)) {
        key = 'registry_${trimmedRegistryId}_${baseSlug}_$n';
        n += 1;
      }
      final cleanedSuggestions = suggestions
          .map((e) => _normalizeVocabularyValue(e))
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false);
      updated.add(registry.copyWith(fields: [
        ...registry.fields,
        RecordFieldDef(
          key: key,
          label: trimmedLabel,
          hint: hint.trim().isEmpty ? 'Registry field' : hint.trim(),
          builtInSuggestions: cleanedSuggestions,
          isSystem: false,
          registryId: trimmedRegistryId,
          conditionalOnFieldKey: conditionalOnFieldKey.trim(),
          conditionalEquals: conditionalEquals.trim(),
        ),
      ]));
    }
    await _saveRegistries(updated);
  }


  Future<void> updateRegistryField({
    required String registryId,
    required String fieldKey,
    required String label,
    String hint = '',
    List<String> suggestions = const <String>[],
    String conditionalOnFieldKey = '',
    String conditionalEquals = '',
  }) async {
    final trimmedRegistryId = registryId.trim();
    final trimmedFieldKey = fieldKey.trim();
    final trimmedLabel = label.trim();
    if (trimmedRegistryId.isEmpty || trimmedFieldKey.isEmpty || trimmedLabel.isEmpty) return;
    final cleanedSuggestions = suggestions
        .map((e) => _normalizeVocabularyValue(e))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final registries = await loadRegistries();
    final updated = registries.map((registry) {
      if (registry.registryId != trimmedRegistryId) return registry;
      final nextFields = registry.fields.map((field) {
        if (field.key != trimmedFieldKey) return field;
        return field.copyWith(
          label: trimmedLabel,
          hint: hint.trim().isEmpty ? field.hint : hint.trim(),
          builtInSuggestions: cleanedSuggestions,
          conditionalOnFieldKey: conditionalOnFieldKey.trim(),
          conditionalEquals: conditionalEquals.trim(),
        );
      }).toList(growable: false);
      return registry.copyWith(fields: nextFields);
    }).toList(growable: false);
    await _saveRegistries(updated);
  }

  Future<void> deleteRegistryField({
    required String registryId,
    required String fieldKey,
  }) async {
    final trimmedRegistryId = registryId.trim();
    final trimmedFieldKey = fieldKey.trim();
    if (trimmedRegistryId.isEmpty || trimmedFieldKey.isEmpty) return;
    final registries = await loadRegistries();
    final updated = registries.map((registry) {
      if (registry.registryId != trimmedRegistryId) return registry;
      return registry.copyWith(
        fields: registry.fields.where((field) => field.key != trimmedFieldKey).toList(growable: false),
      );
    }).toList(growable: false);
    await _saveRegistries(updated);
  }


  Future<void> deleteRegistry(String registryId) async {
    final trimmedRegistryId = registryId.trim();
    if (trimmedRegistryId.isEmpty) return;
    final registries = await loadRegistries();
    final updatedRegistries = registries.where((r) => r.registryId != trimmedRegistryId).toList(growable: false);
    await _saveRegistries(updatedRegistries);

    final prefs = await _prefs;
    final ids = await _readIndex();
    for (final id in ids) {
      final raw = prefs.getString(_recordKey(id));
      if (raw == null || raw.trim().isEmpty) continue;
      try {
        final entry = RecordEntry.decode(raw);
        if (!entry.registryIds.contains(trimmedRegistryId)) continue;
        final updatedEntry = entry.copyWith(
          updatedAtIso: DateTime.now().toIso8601String(),
          registryIds: entry.registryIds.where((rid) => rid != trimmedRegistryId).toList(growable: false),
        );
        await prefs.setString(_recordKey(id), updatedEntry.encode());
      } catch (_) {}
    }
  }

  Future<void> assignRecordToRegistry({required String recordEntryId, required String registryId}) async {
    final trimmedRegistryId = registryId.trim();
    if (trimmedRegistryId.isEmpty) return;
    final existing = await loadByRecordId(recordEntryId);
    if (existing == null) return;
    if (existing.registryIds.contains(trimmedRegistryId)) return;
    await saveRecord(existing.copyWith(
      updatedAtIso: DateTime.now().toIso8601String(),
      registryIds: [...existing.registryIds, trimmedRegistryId],
    ));
  }

  Future<void> removeRecordFromRegistry({required String recordEntryId, required String registryId}) async {
    final existing = await loadByRecordId(recordEntryId);
    if (existing == null) return;
    final nextRegistries = existing.registryIds.where((id) => id != registryId).toList(growable: false);
    await saveRecord(existing.copyWith(
      updatedAtIso: DateTime.now().toIso8601String(),
      registryIds: nextRegistries,
    ));
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
    final existingFields = [...RecordFieldCatalog.coreFields, ...current];
    final existingSameConcept = existingFields.any((field) =>
        field.key.trim().toLowerCase() == key.toLowerCase() ||
        field.label.trim().toLowerCase() == trimmedLabel.toLowerCase());
    if (existingSameConcept) return;
    final existingKeys = existingFields.map((e) => e.key).toSet();
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


  Future<void> updateCustomField({
    required String fieldKey,
    required String label,
    String hint = '',
    String procedureScope = '',
    List<String>? suggestions,
  }) async {
    final trimmedKey = fieldKey.trim();
    final trimmedLabel = label.trim();
    if (trimmedKey.isEmpty || trimmedLabel.isEmpty) return;
    final current = await loadCustomFields();
    final updated = current.map((field) {
      if (field.key != trimmedKey) return field;
      return field.copyWith(
        label: trimmedLabel,
        hint: hint.trim().isEmpty ? field.hint : hint.trim(),
        procedureScope: procedureScope.trim(),
        builtInSuggestions: suggestions ?? field.builtInSuggestions,
      );
    }).toList(growable: false);
    final prefs = await _prefs;
    await prefs.setString(_customFieldsKey, jsonEncode(updated.map((e) => e.toJson()).toList(growable: false)));

    final ids = await _readIndex();
    for (final id in ids) {
      final raw = prefs.getString(_recordKey(id));
      if (raw == null || raw.trim().isEmpty) continue;
      try {
        final entry = RecordEntry.decode(raw);
        if (!entry.values.containsKey(trimmedKey) && !entry.fieldLabels.containsKey(trimmedKey)) continue;
        final labels = Map<String, String>.from(entry.fieldLabels)..[trimmedKey] = trimmedLabel;
        final updatedEntry = entry.copyWith(
          updatedAtIso: DateTime.now().toIso8601String(),
          fieldLabels: labels,
        );
        await prefs.setString(_recordKey(id), updatedEntry.encode());
      } catch (_) {
        // Keep corrupt or legacy records untouched.
      }
    }
  }


  Future<void> deleteCustomField(String fieldKey, {bool deleteSavedValues = false}) async {
    final trimmedKey = fieldKey.trim();
    if (trimmedKey.isEmpty) return;

    final current = await loadCustomFields();
    final updatedFields = current.where((f) => f.key != trimmedKey).toList(growable: false);
    final prefs = await _prefs;
    await prefs.setString(_customFieldsKey, jsonEncode(updatedFields.map((e) => e.toJson()).toList(growable: false)));
    await prefs.remove(_vocabKey(trimmedKey));

    if (!deleteSavedValues) return;

    final ids = await _readIndex();
    for (final id in ids) {
      final raw = prefs.getString(_recordKey(id));
      if (raw == null || raw.trim().isEmpty) continue;
      try {
        final entry = RecordEntry.decode(raw);
        if (!entry.values.containsKey(trimmedKey)) continue;
        final values = Map<String, String>.from(entry.values)..remove(trimmedKey);
        final labels = Map<String, String>.from(entry.fieldLabels)..remove(trimmedKey);
        final updatedEntry = entry.copyWith(
          updatedAtIso: DateTime.now().toIso8601String(),
          values: values,
          fieldLabels: labels,
        );
        await prefs.setString(_recordKey(id), updatedEntry.encode());
      } catch (_) {}
    }
  }

  Future<List<RecordFieldDef>> allFields() async {
    final registries = await loadRegistries();
    return [
      ...RecordFieldCatalog.coreFields,
      ...await loadCustomFields(),
      ...registries.expand((registry) => registry.fields),
    ];
  }

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
            fieldLabels: entry.fieldLabels,
            fieldSources: entry.fieldSources,
            registryIds: entry.registryIds,
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

    final procedure = entry.valueOf(RecordFieldCatalog.procedure.key);
    final fields = await allFields();
    final fieldByKey = {for (final field in fields) field.key: field};
    for (final item in entry.values.entries) {
      if (item.key == RecordFieldCatalog.reportId.key ||
          item.key == RecordFieldCatalog.reportDate.key) {
        continue;
      }
      final value = item.value.trim();
      if (value.isEmpty) continue;
      final field = fieldByKey[item.key];
      // Do not learn patient names, free-form custom values, or registry values as persistent suggestions.
      // Suggestions should come from built-ins, procedure/report-type vocabulary, or short list-like clinical fields.
      if (field?.isRegistryField == true) continue;
      final label = entry.fieldLabels[item.key] ?? field?.label;
      final shouldLearn = item.key == RecordFieldCatalog.procedure.key ||
          (field?.builtInSuggestions.isNotEmpty == true) ||
          _isListLikeVocabularyField(item.key, label: label);
      if (!shouldLearn) continue;
      try {
        await saveVocabularyValue(
          item.key,
          value,
          label: label,
          procedure: item.key == RecordFieldCatalog.procedure.key ? '' : procedure,
        );
      } catch (_) {
        // Vocabulary learning is only a convenience feature. It must not block
        // record saving or package recovery when an old/odd user-entered value
        // cannot be split or normalised safely.
      }
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

  Future<List<String>> searchVocabulary(
    String fieldKey,
    String query, {
    String procedure = '',
  }) async {
    final prefs = await _prefs;
    final scopedSaved = prefs.getStringList(_scopedVocabKey(fieldKey, procedure)) ?? <String>[];
    // Compatibility fallback: older versions saved suggestions globally by field key.
    // Show them only when no procedure-specific suggestions exist yet.
    final legacySaved = scopedSaved.isEmpty
        ? (prefs.getStringList(_vocabKey(fieldKey)) ?? <String>[])
        : const <String>[];
    final builtIn = (RecordFieldCatalog.byKey(fieldKey)?.builtInSuggestions ?? const <String>[]);
    final cleanedSaved = <String>{};
    for (final item in [...scopedSaved, ...legacySaved]) {
      cleanedSaved.addAll(_vocabularyCandidatesFor(fieldKey, item));
    }
    final merged = <String>{...builtIn, ...cleanedSaved}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return merged;
    return merged.where((v) => v.toLowerCase().contains(trimmed)).toList(growable: false);
  }

  Future<void> saveVocabularyValue(
    String fieldKey,
    String value, {
    String? label,
    String procedure = '',
  }) async {
    final candidates = _vocabularyCandidatesFor(fieldKey, value, label: label);
    if (candidates.isEmpty) return;

    final prefs = await _prefs;
    final key = _scopedVocabKey(fieldKey, procedure);
    final existing = prefs.getStringList(key) ?? <String>[];

    for (final candidate in candidates.reversed) {
      existing.removeWhere((e) => _sameVocabularyValue(e, candidate));
      existing.insert(0, candidate);
    }

    final capped = existing.take(100).toList(growable: false);
    await prefs.setStringList(key, capped);
  }

  List<String> _vocabularyCandidatesFor(String fieldKey, String value, {String? label}) {
    final trimmed = _normalizeVocabularyValue(value);
    if (trimmed.isEmpty) return const <String>[];

    // List-like fields may be entered as comma-separated text, semicolon lists,
    // new lines, bullets, or numbered lists. Keep the full value in the saved
    // record, but learn the individual short entries as future suggestions.
    final shouldSplit = _isListLikeVocabularyField(fieldKey, label: label) &&
        trimmed.contains(RegExp(r'[,;\n\r]|(?:^|\s)\d+[\.)]\s+|(?:^|\s)[•\-]\s+'));
    final rawCandidates = shouldSplit
        ? _splitListLikeVocabulary(trimmed)
        : <String>[trimmed];

    final out = <String>[];
    final seen = <String>{};
    for (final candidate in rawCandidates) {
      if (candidate.isEmpty) continue;
      // Suggestions should stay short and reusable. Long sentence-like values
      // can remain in Records, but should not clutter future suggestions.
      if (_wordCount(candidate) > 6) continue;
      final key = candidate.toLowerCase();
      if (seen.add(key)) out.add(candidate);
    }
    return out;
  }

  List<String> _splitListLikeVocabulary(String value) {
    // Keep this parser deliberately defensive. This code can run while importing
    // old records packages, so a formatting cleanup bug must never block records
    // recovery. Dart on some runtimes can reject inline regex flags such as (?m),
    // so use the RegExp multiLine option instead.
    try {
      final normalized = value
          .replaceAll(RegExp(r'\r\n?'), '\n')
          .replaceAll(RegExp(r'^\s*\d+[\.)]\s+', multiLine: true), '')
          .replaceAll(RegExp(r'^\s*[•\-]\s+', multiLine: true), '');
      return normalized
          .split(RegExp(r'[,;\n]+|\s+\d+[\.)]\s+|\s+[•\-]\s+'))
          .map(_normalizeVocabularyValue)
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      final fallback = _normalizeVocabularyValue(value);
      return fallback.isEmpty ? const <String>[] : <String>[fallback];
    }
  }

  bool _isListLikeVocabularyField(String fieldKey, {String? label}) {
    final key = '${fieldKey.trim()} ${label ?? ''}'.toLowerCase();
    return key.contains('indication') ||
        key.contains('diagnosis') ||
        key.contains('diagnoses') ||
        key.contains('finding') ||
        key.contains('symptom') ||
        key.contains('complaint') ||
        key.contains('comorbid') ||
        key.contains('medication') ||
        key.contains('impression');
  }

  String _normalizeVocabularyValue(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[,;\s]+|[,;\s]+$'), '');
  }

  bool _sameVocabularyValue(String a, String b) {
    return _normalizeVocabularyValue(a).toLowerCase() ==
        _normalizeVocabularyValue(b).toLowerCase();
  }

  int _wordCount(String value) {
    return RegExp(r"[A-Za-z0-9%+\-/]+", unicode: true).allMatches(value).length;
  }


  String buildRipotCsv({required List<RecordSummary> records, required List<RecordFieldDef> fields}) {
    final dynamicKeys = <String>[];
    for (final row in records) {
      for (final key in row.values.keys) {
        if (!dynamicKeys.contains(key)) dynamicKeys.add(key);
      }
    }
    final orderedKeys = [
      ...RecordFieldCatalog.exportDefaultKeys,
      ...fields.where((f) => !RecordFieldCatalog.exportDefaultKeys.contains(f.key)).map((f) => f.key),
      ...dynamicKeys,
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
      'ripotRegistryIds',
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
        row.registryIds.join(';'),
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
      final registryIds = (map['ripotRegistryIds'] ?? '')
          .split(RegExp(r'[;,]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      final incoming = RecordEntry(
        recordEntryId: recordId,
        linkedReportId: linkedReportId.isEmpty ? recordId : linkedReportId,
        createdAtIso: createdAtIso,
        updatedAtIso: updatedAt.toIso8601String(),
        values: values,
        registryIds: registryIds,
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
    final now = nowIso();
    final derived = _recordValuesForReport(doc);
    final existing = await loadByReportId(doc.reportId);

    if (existing != null) {
      final mergedValues = Map<String, String>.from(existing.values);
      final mergedLabels = Map<String, String>.from(existing.fieldLabels);
      final mergedSources = Map<String, String>.from(existing.fieldSources);

      // Refresh system/template-derived values from the current report so newly
      // ticked Add-to-Records sections appear when editing an existing record.
      // Manual custom fields that do not conflict with these keys are preserved.
      for (final entry in derived.values.entries) {
        if (entry.value.trim().isEmpty) continue;
        mergedValues[entry.key] = entry.value;
      }
      for (final entry in derived.labels.entries) {
        if (entry.value.trim().isEmpty) continue;
        mergedLabels[entry.key] = entry.value;
      }
      for (final entry in derived.sources.entries) {
        if (entry.value.trim().isEmpty) continue;
        mergedSources[entry.key] = entry.value;
      }

      return existing.copyWith(values: mergedValues, fieldLabels: mergedLabels, fieldSources: mergedSources);
    }

    return RecordEntry(
      recordEntryId: newId('rec'),
      linkedReportId: doc.reportId,
      createdAtIso: now,
      updatedAtIso: now,
      values: derived.values,
      fieldLabels: derived.labels,
      fieldSources: derived.sources,
    );
  }

  _RecordBuildData _recordValuesForReport(ReportDoc doc) {
    final values = <String, String>{
      RecordFieldCatalog.reportId.key: doc.reportId,
      RecordFieldCatalog.reportDate.key: _inferDate(doc),
      RecordFieldCatalog.procedure.key: _inferProcedure(doc),
      RecordFieldCatalog.doctor.key: _inferDoctor(doc),
    };
    final labels = <String, String>{
      RecordFieldCatalog.reportId.key: RecordFieldCatalog.reportId.label,
      RecordFieldCatalog.reportDate.key: RecordFieldCatalog.reportDate.label,
      RecordFieldCatalog.procedure.key: RecordFieldCatalog.procedure.label,
      RecordFieldCatalog.doctor.key: RecordFieldCatalog.doctor.label,
    };
    final sources = <String, String>{
      RecordFieldCatalog.reportId.key: 'template',
      RecordFieldCatalog.reportDate.key: 'template',
      RecordFieldCatalog.procedure.key: 'template',
      RecordFieldCatalog.doctor.key: 'template',
    };

    // Subject Info is inherently record-like, so every filled Subject Info field
    // is copied automatically using the user's visible field title.
    if (doc.subjectInfoDef.enabled) {
      for (final field in doc.subjectInfoDef.orderedFields) {
        final value = doc.subjectInfo.valueOf(field.key).trim();
        if (value.isEmpty) continue;

        final key = _recordKeyForSubjectField(field.key, field.title);
        values[key] = value;
        labels[key] = field.title.trim().isEmpty ? key : field.title.trim();
        sources[key] = 'template';

        // Keep core summary keys populated without forcing their default labels
        // into the Record Details UI.
        if (field.key == 'subjectName') {
          values[RecordFieldCatalog.subjectName.key] = value;
          labels[RecordFieldCatalog.subjectName.key] = field.title.trim().isEmpty
              ? RecordFieldCatalog.subjectName.label
              : field.title.trim();
          sources[RecordFieldCatalog.subjectName.key] = 'template';
        } else if (field.key == 'subjectId') {
          values[RecordFieldCatalog.patientReference.key] = value;
          labels[RecordFieldCatalog.patientReference.key] = field.title.trim().isEmpty
              ? RecordFieldCatalog.patientReference.label
              : field.title.trim();
          sources[RecordFieldCatalog.patientReference.key] = 'template';
        }
      }
    }

    // Explicit template/outline mappings are trusted. Old guessing is not used
    // once the user has chosen Add to Records on sections.
    for (final root in doc.roots) {
      _collectExplicitRecordFields(root, values, labels, sources, doc.roots);
    }

    return _RecordBuildData(values: values, labels: labels, sources: sources);
  }

  String _recordKeyForSubjectField(String fieldKey, String title) {
    if (fieldKey == 'subjectName') return RecordFieldCatalog.subjectName.key;
    if (fieldKey == 'subjectId') return RecordFieldCatalog.patientReference.key;

    final normalized = title.trim().toLowerCase();
    if (normalized == 'age') return RecordFieldCatalog.age.key;
    if (normalized == 'sex' || normalized == 'gender') return RecordFieldCatalog.gender.key;

    return 'subject_${fieldKey.trim().isEmpty ? _slug(title) : fieldKey}';
  }

  String _recordKeyForSectionTitle(SectionNode section) {
    final normalized = section.title.trim().toLowerCase();
    if (normalized == 'procedure' || normalized == 'report type') {
      return RecordFieldCatalog.procedure.key;
    }
    if (normalized == 'indication' || normalized == 'indications') {
      return RecordFieldCatalog.indication.key;
    }
    if (normalized == 'diagnosis' || normalized == 'diagnoses' || normalized == 'impression') {
      return RecordFieldCatalog.diagnosis.key;
    }
    if (normalized == 'biopsy' || normalized == 'biopsy taken') {
      return RecordFieldCatalog.biopsyTaken.key;
    }
    if (normalized == 'histology' || normalized == 'histology result' || normalized == 'pathology' || normalized == 'pathology result') {
      return RecordFieldCatalog.histologyResult.key;
    }
    if (normalized == 'intervention' || normalized == 'therapy' || normalized == 'intervention therapy' || normalized == 'intervention / therapy') {
      return RecordFieldCatalog.intervention.key;
    }
    if (normalized == 'complication' || normalized == 'complications') {
      return RecordFieldCatalog.complications.key;
    }
    if (normalized == 'recommendation' || normalized == 'recommendations') {
      return RecordFieldCatalog.recommendations.key;
    }
    if (normalized == 'facility' || normalized == 'hospital' || normalized == 'centre' || normalized == 'center') {
      return RecordFieldCatalog.facility.key;
    }
    if (normalized == 'doctor' || normalized == 'operator' || normalized == 'consultant' || normalized == 'endoscopist') {
      return RecordFieldCatalog.doctor.key;
    }
    // Default to the clean slug so a future template field can link/merge
    // with an existing custom record field that used the same label.
    return _slug(section.title);
  }

  String _slug(String value) {
    final slug = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return slug.isEmpty ? newId('field') : slug;
  }


  SectionNode? _findSectionById(List<SectionNode> roots, String id) {
    for (final section in roots) {
      if (section.id == id) return section;
      final found = _findSectionById(section.children.whereType<SectionNode>().toList(growable: false), id);
      if (found != null) return found;
    }
    return null;
  }

  bool _sectionConditionAllows(SectionNode section, List<SectionNode> roots) {
    if (!section.hasCondition) return true;
    final parent = _findSectionById(roots, section.conditionalParentSectionId);
    if (parent == null) return true;
    final parentValue = _firstNonEmptyContent(parent).trim().toLowerCase();
    final expected = section.conditionalEquals.trim().toLowerCase();
    return expected.isEmpty || parentValue == expected;
  }

  void _collectExplicitRecordFields(
    SectionNode section,
    Map<String, String> values,
    Map<String, String> labels,
    Map<String, String> sources,
    List<SectionNode> roots,
  ) {
    if (!_sectionConditionAllows(section, roots)) return;
    if (section.addToRecords) {
      final key = _recordKeyForSectionTitle(section);
      final value = _firstNonEmptyContent(section).trim();
      // A template-selected field should be available in Record Details even
      // when the report section has not been filled yet. Empty values are kept
      // out of table suggestions/columns by the UI and vocabulary logic.
      values[key] = value;
      labels[key] = section.title.trim().isEmpty ? key : section.title.trim();
      sources[key] = 'template';
    }

    for (final child in section.children) {
      if (child is SectionNode) {
        _collectExplicitRecordFields(child, values, labels, sources, roots);
      }
    }
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
