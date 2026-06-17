import 'package:flutter/foundation.dart';

import '../../reports/domain/models/report_doc.dart';
import '../data/records_repository.dart';
import '../domain/record_models.dart';

class RecordsProvider extends ChangeNotifier {
  final RecordsRepository repo;

  RecordsProvider({required this.repo});

  List<RecordSummary> records = [];
  List<RecordFieldDef> allFields = [...RecordFieldCatalog.coreFields];
  List<RecordRegistry> registries = [];
  bool loading = false;
  String query = '';

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    registries = await repo.loadRegistries();
    allFields = await repo.allFields();
    records = await repo.listRecords();
    loading = false;
    notifyListeners();
  }

  List<RecordSummary> get filteredRecords {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return records;
    return records.where((r) {
      final haystack = [
        r.procedure,
        r.diagnosis,
        r.patientReference,
        r.reportDate,
        r.linkedReportId,
        ...r.values.values,
      ].join(' ').toLowerCase();
      return haystack.contains(trimmed);
    }).toList(growable: false);
  }

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  Future<RecordEntry> draftForReport(ReportDoc doc) => repo.buildDraftForReport(doc);

  Future<void> saveRecord(RecordEntry entry) async {
    await repo.saveRecord(entry);
    await refresh();
  }

  Future<void> deleteRecord(String recordEntryId) async {
    await repo.deleteRecord(recordEntryId);
    await refresh();
  }

  Future<List<String>> suggestions(
    String fieldKey,
    String query, {
    String procedure = '',
  }) async {
    final saved = await repo.searchVocabulary(fieldKey, query, procedure: procedure);
    RecordFieldDef? field;
    for (final candidate in allFields) {
      if (candidate.key == fieldKey) {
        field = candidate;
        break;
      }
    }
    final builtIn = field?.builtInSuggestions ?? const <String>[];
    final trimmed = query.trim().toLowerCase();

    // Keep manually configured suggestions first and in their configured order.
    // Previously used values are helpful, but should not override curated options.
    final seen = <String>{};
    final ordered = <String>[];

    void addIfVisible(String value) {
      final cleaned = value.trim();
      if (cleaned.isEmpty) return;
      if (trimmed.isNotEmpty && !cleaned.toLowerCase().contains(trimmed)) return;
      final key = cleaned.toLowerCase();
      if (seen.add(key)) ordered.add(cleaned);
    }

    for (final value in builtIn) {
      addIfVisible(value);
    }
    for (final value in saved) {
      addIfVisible(value);
    }

    return ordered;
  }

  Future<void> addCustomField({required String label, String hint = '', String procedureScope = ''}) async {
    await repo.saveCustomField(label: label, hint: hint, procedureScope: procedureScope);
    await refresh();
  }

  Future<void> updateCustomField({
    required String fieldKey,
    required String label,
    String hint = '',
    String procedureScope = '',
    List<String>? suggestions,
  }) async {
    await repo.updateCustomField(
      fieldKey: fieldKey,
      label: label,
      hint: hint,
      procedureScope: procedureScope,
      suggestions: suggestions,
    );
    await refresh();
  }


  Future<void> deleteCustomField(String fieldKey, {bool deleteSavedValues = false}) async {
    await repo.deleteCustomField(fieldKey, deleteSavedValues: deleteSavedValues);
    await refresh();
  }

  Future<RecordRegistry> createRegistry({required String title, String description = ''}) async {
    final registry = await repo.createRegistry(title: title, description: description);
    await refresh();
    return registry;
  }


  Future<void> updateRegistry({
    required String registryId,
    required String title,
    String description = '',
  }) async {
    await repo.updateRegistry(registryId: registryId, title: title, description: description);
    await refresh();
  }

  Future<void> addRegistryField({
    required String registryId,
    required String label,
    String hint = '',
    List<String> suggestions = const <String>[],
    String conditionalOnFieldKey = '',
    String conditionalEquals = '',
  }) async {
    await repo.addRegistryField(
      registryId: registryId,
      label: label,
      hint: hint,
      suggestions: suggestions,
      conditionalOnFieldKey: conditionalOnFieldKey,
      conditionalEquals: conditionalEquals,
    );
    await refresh();
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
    await repo.updateRegistryField(
      registryId: registryId,
      fieldKey: fieldKey,
      label: label,
      hint: hint,
      suggestions: suggestions,
      conditionalOnFieldKey: conditionalOnFieldKey,
      conditionalEquals: conditionalEquals,
    );
    await refresh();
  }

  Future<void> deleteRegistryField({
    required String registryId,
    required String fieldKey,
  }) async {
    await repo.deleteRegistryField(registryId: registryId, fieldKey: fieldKey);
    await refresh();
  }

  Future<void> deleteRegistry(String registryId) async {
    await repo.deleteRegistry(registryId);
    await refresh();
  }

  Future<RecordEntry?> assignRecordToRegistry({required String recordEntryId, required String registryId}) async {
    await repo.assignRecordToRegistry(recordEntryId: recordEntryId, registryId: registryId);
    await refresh();
    return repo.loadByRecordId(recordEntryId);
  }

  Future<RecordEntry?> removeRecordFromRegistry({required String recordEntryId, required String registryId}) async {
    await repo.removeRecordFromRegistry(recordEntryId: recordEntryId, registryId: registryId);
    await refresh();
    return repo.loadByRecordId(recordEntryId);
  }
}

