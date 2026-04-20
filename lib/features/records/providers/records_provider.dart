import 'package:flutter/foundation.dart';

import '../../reports/domain/models/report_doc.dart';
import '../data/records_repository.dart';
import '../domain/record_models.dart';

class RecordsProvider extends ChangeNotifier {
  final RecordsRepository repo;

  RecordsProvider({required this.repo});

  List<RecordSummary> records = [];
  List<RecordFieldDef> allFields = [...RecordFieldCatalog.coreFields];
  bool loading = false;
  String query = '';

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
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

  Future<List<String>> suggestions(String fieldKey, String query) => repo.searchVocabulary(fieldKey, query);

  Future<void> addCustomField({
    required String label,
    String hint = '',
    RecordFieldLevel level = RecordFieldLevel.general,
    String? procedureValue,
  }) async {
    await repo.saveCustomField(label: label, hint: hint, level: level, procedureValue: procedureValue);
    await refresh();
  }
}
