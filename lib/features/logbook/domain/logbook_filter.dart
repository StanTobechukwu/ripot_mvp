import 'logbook_models.dart';

List<LogEntry> filterLogbook(
  List<LogEntry> entries, {
  String doctorId = '',
  DateTime? start,
  DateTime? end,
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  return entries.where((e) {
      if (doctorId.isNotEmpty &&
          !e.data.participants.any((p) => p.doctorId == doctorId) &&
          e.data.supervisorId != doctorId) {
        return false;
      }
      if (start != null && day(e.data.procedureDate).isBefore(day(start))) {
        return false;
      }
      if (end != null && day(e.data.procedureDate).isAfter(day(end))) {
        return false;
      }
      return q.isEmpty ||
          '${e.data.procedure} ${e.data.facility} ${e.data.reference}'
              .toLowerCase()
              .contains(q);
    }).toList()
    ..sort((a, b) => b.data.procedureDate.compareTo(a.data.procedureDate));
}
