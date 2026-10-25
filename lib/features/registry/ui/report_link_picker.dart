import 'package:flutter/material.dart';
import '../data/registry_repository.dart';
import '../domain/report_link_match.dart';
import '../../reports/data/reports_repository.dart';

class ReportLinkPicker extends StatefulWidget {
  const ReportLinkPicker({
    super.key,
    required this.patient,
    required this.reports,
    required this.unavailableReportIds,
  });
  final RegistryPatient patient;
  final List<ReportSummary> reports;
  final Set<String> unavailableReportIds;

  @override
  State<ReportLinkPicker> createState() => _ReportLinkPickerState();
}

class _ReportLinkPickerState extends State<ReportLinkPicker> {
  String _query = '';
  bool _searchOthers = false;

  Future<void> _confirm(ReportSummary report) async {
    final match = reportLinkMatch(widget.patient, report);
    var checked = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Link to this patient?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Registry patient',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    _identity(
                      widget.patient.name,
                      widget.patient.reference,
                      widget.patient.facility,
                    ),
                  ),
                  const Divider(height: 24),
                  Text(
                    'Selected report',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(report.title),
                  Text(
                    _identity(
                      report.subjectName,
                      report.subjectId,
                      report.facility,
                    ),
                  ),
                  Text('Report date: ${_date(report.reportDateIso)}'),
                  Text('Report reference: ${report.reportId}'),
                  const SizedBox(height: 12),
                  const Text(
                    'Check these details refer to the same patient. This only adds a link; it does not copy measurements.',
                  ),
                  if (match != ReportLinkMatch.identifier)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'I have checked this is the same patient',
                      ),
                      value: checked,
                      onChanged: (value) =>
                          setDialogState(() => checked = value ?? false),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: match == ReportLinkMatch.identifier || checked
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                child: const Text('Link report'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed == true && mounted) Navigator.pop(context, report.reportId);
  }

  @override
  Widget build(BuildContext context) {
    final query = normalizePatientText(_query);
    final reports = widget.reports.where((report) {
      if (!_searchOthers && !isSuggestedReport(widget.patient, report))
        return false;
      // The broader library is not exposed as a one-tap unfiltered list.
      if (_searchOthers && query.length < 2) return false;
      return query.isEmpty ||
          normalizePatientText(
            [
              report.subjectName,
              report.subjectId,
              report.facility,
              report.title,
              report.reportDateIso,
              report.reportId,
            ].join(' '),
          ).contains(query);
    }).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Link existing report',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  _identity(
                    widget.patient.name,
                    widget.patient.reference,
                    widget.patient.facility,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search by patient, ID, procedure or date',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Search other reports'),
                  subtitle: Text(
                    _searchOthers
                        ? 'Enter at least 2 characters. Check the patient before linking.'
                        : 'Showing suggested matches only. Names are not proof of identity.',
                  ),
                  value: _searchOthers,
                  onChanged: (value) => setState(() => _searchOthers = value),
                ),
                reports.isEmpty
                    ? Center(
                        child: Text(
                          _searchOthers
                              ? (query.length < 2
                                    ? 'Enter a search to find another report.'
                                    : 'No reports match your search.')
                              : 'No suggested reports. Check the patient details or use Search other reports.',
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: reports.length,
                        itemBuilder: (context, index) {
                          final report = reports[index];
                          final match = reportLinkMatch(widget.patient, report);
                          final otherPatient = widget.unavailableReportIds
                              .contains(report.reportId);
                          final blocked =
                              otherPatient || match == ReportLinkMatch.conflict;
                          final label = otherPatient
                              ? 'Already linked to another patient'
                              : match == ReportLinkMatch.conflict
                              ? 'Patient ID or facility differs — correct the details first'
                              : match == ReportLinkMatch.identifier
                              ? 'Matching identifier — review before linking'
                              : match == ReportLinkMatch.name
                              ? 'Same name — verify identity'
                              : 'Patient details need verification';
                          return ListTile(
                            enabled: !blocked,
                            leading: Icon(
                              blocked
                                  ? Icons.lock_outline
                                  : Icons.description_outlined,
                            ),
                            title: Text(report.title),
                            subtitle: Text(
                              '${_identity(report.subjectName, report.subjectId, report.facility)}\nReport date: ${_date(report.reportDateIso)}\n$label',
                            ),
                            onTap: blocked ? null : () => _confirm(report),
                          );
                        },
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _identity(String name, String identifier, String facility) =>
    '${name.isEmpty ? "Name not recorded" : name}\nID: ${identifier.isEmpty ? "Not recorded" : identifier}\nFacility: ${facility.isEmpty ? "Not recorded" : facility}';

String _date(String iso) {
  final date = DateTime.tryParse(iso);
  return date == null
      ? 'Not recorded'
      : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
