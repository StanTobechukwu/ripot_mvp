import 'package:flutter/foundation.dart';
import '../data/reports_repository.dart';

class ReportsListProvider extends ChangeNotifier {
  final ReportsRepository repo;

  ReportsListProvider({required this.repo});

  List<ReportSummary> reports = [];
  bool loading = false;

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    reports = await repo.listReports();
    loading = false;
    notifyListeners();
  }

  Future<void> delete(String reportId) async {
    await repo.deleteReport(reportId);
    await refresh();
  }
}
