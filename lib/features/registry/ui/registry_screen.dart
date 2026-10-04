import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/utils/ids.dart';
import '../../access/providers/access_provider.dart';
import '../../access/ui/premium_prompt.dart';
import '../../records/data/records_repository.dart';
import '../../records/domain/record_models.dart';
import '../data/registry_repository.dart';
import '../domain/registry_table.dart';
import 'registry_tools.dart';
import '../../reports/data/reports_repository.dart';
import '../../reports/ui/saved_pdf_viewer_screen.dart';
import '../../reports/services/image_services.dart';
import '../../reports/services/media_ref.dart';

// Keep caller-owned controllers alive until the outgoing dialog is unmounted.
Future<T?> _registryDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
  );
  final result = await navigator.push(route);
  await route.completed;
  return result;
}

Future<void> openRegistry(BuildContext context, {RecordEntry? source}) async {
  if (!context.read<AccessProvider>().safeState.canUseRecords) {
    final unlocked = await showPremiumFeatureSheet(context, PremiumFeature.registry);
    if (!unlocked || !context.mounted) return;
  }
  await Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => RegistryScreen(source: source)),
  );
}

String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
String _patientLabel(RegistryPatient p) =>
    p.name.isEmpty ? p.reference : p.name;
void _error(BuildContext context, Object error) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(error.toString())));

Future<void> _editRegistryCell(
  BuildContext context,
  RecordRegistry registry,
  RegistryPatient patient,
  List<RegistryUpdate> updates,
  RegistryTableCell cell,
) async {
  await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    clipBehavior: Clip.antiAlias,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (c) => SizedBox(
      height: MediaQuery.sizeOf(c).height * .9,
      child: RegistryUpdateScreen(
        registry: registry,
        patient: patient,
        previousUpdates: updates,
        patientDetails: cell.field.patientDetail,
        correction: cell.correction ? cell.update : null,
        quickEntry: true,
        initialFieldKey: cell.field.key,
      ),
    ),
  );
}

class RegistryScreen extends StatefulWidget {
  final RecordEntry? source;
  const RegistryScreen({super.key, this.source});
  @override
  State<RegistryScreen> createState() => _RegistryScreenState();
}

class _RegistryScreenState extends State<RegistryScreen> {
  List<RecordRegistry>? _registries;
  String? _failure;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await context.read<RecordsRepository>().loadRegistries();
      if (mounted) {
        setState(() {
          _registries = items;
          _failure = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _failure = e.toString());
    }
  }

  Future<void> _create() async {
    final title = await _askText(context, 'Create registry', 'Registry name');
    if (title == null || !mounted || !context.mounted) return;
    try {
      final item = await context.read<RecordsRepository>().createRegistry(
        title: title,
      );
      if (!mounted || !context.mounted) return;
      await _open(item);
      await _load();
    } catch (e) {
      if (mounted && context.mounted) _error(context, e);
    }
  }

  Future<void> _open(RecordRegistry registry) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            RegistryPatientsScreen(registry: registry, source: widget.source),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.source == null ? 'Registry' : 'Add to Registry'),
      actions: [
        IconButton(
          tooltip: 'Restore Registry backup',
          icon: const Icon(Icons.restore),
          onPressed: () async {
            final registry = await registryRestore(context);
            if (!mounted) return;
            await _load();
            if (registry != null && mounted) await _open(registry);
          },
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _create,
      icon: const Icon(Icons.add),
      label: const Text('New registry'),
    ),
    body: _failure != null
        ? Center(child: Text(_failure!))
        : _registries == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              const Text(
                'Follow patients over time. Add information directly or from a report.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Registry stays on this device or browser. Create an encrypted backup regularly; restore it with Restore above. Follow your organisation’s policy for patient data.',
              ),
              const SizedBox(height: 16),
              if (_registries!.isEmpty)
                const Text('Create a registry to add your first patient.'),
              for (final r in _registries!)
                Card(
                  child: ListTile(
                    title: Text(r.title),
                    subtitle: Text(
                      r.description.isEmpty
                          ? 'Patients and dated updates'
                          : r.description,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(r),
                  ),
                ),
            ],
          ),
  );
}

class RegistryPatientsScreen extends StatefulWidget {
  final RecordRegistry registry;
  final RecordEntry? source;
  const RegistryPatientsScreen({
    super.key,
    required this.registry,
    this.source,
  });
  @override
  State<RegistryPatientsScreen> createState() => _RegistryPatientsScreenState();
}

class _RegistryPatientsScreenState extends State<RegistryPatientsScreen> {
  bool _allUpdates = false;
  bool _table = false;
  final _repo = RegistryRepository();
  RegistryData _data = const RegistryData();
  late RecordRegistry _registry;
  bool _loading = true;
  String _query = '';
  String? _failure;
  List<RecordEntry> _legacy = [];
  @override
  void initState() {
    super.initState();
    _registry = widget.registry;
    _load();
  }

  Future<void> _load() async {
    try {
      final records = context.read<RecordsRepository>();
      final data = await _repo.load();
      final registries = await records.loadRegistries();
      final summaries = await records.listRecords();
      final legacy = <RecordEntry>[];
      for (final summary in summaries) {
        if (!summary.registryIds.contains(_registry.registryId)) continue;
        if (data.updates.any(
          (u) =>
              u.registryId == _registry.registryId &&
              u.sourceReportId == summary.linkedReportId,
        )) {
          continue;
        }
        final entry = await records.loadByRecordId(summary.recordEntryId);
        if (entry != null) legacy.add(entry);
      }
      if (mounted) {
        setState(() {
          _data = data;
          _legacy = legacy;
          _registry = registries.firstWhere(
            (r) => r.registryId == _registry.registryId,
          );
          _loading = false;
          _failure = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _failure = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _openPatient(
    RegistryPatient p, {
    RecordEntry? source,
    bool createPatient = false,
  }) async {
    final incoming = source ?? widget.source;
    if (incoming != null &&
        _data.updates.any(
          (u) =>
              u.registryId == _registry.registryId &&
              u.sourceReportId == incoming.linkedReportId &&
              u.patientId != p.id,
        )) {
      _error(
        context,
        'This report is already linked to another patient in this registry.',
      );
      return;
    }
    if (incoming != null &&
        !_data.updates.any(
          (u) =>
              u.registryId == _registry.registryId &&
              u.sourceReportId == incoming.linkedReportId,
        )) {
      final confirmed = await _registryDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Confirm patient'),
          content: Text(
            'Add information to ${_patientLabel(p)}'
            '${p.reference.isEmpty ? '' : ' · ${p.reference}'}'
            '${p.facility.isEmpty ? '' : ' · ${p.facility}'}? Check that this is the patient in the report.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Review values'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || !context.mounted) return;
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => RegistryUpdateScreen(
            registry: _registry,
            patient: p,
            source: incoming,
            createPatient: createPatient,
          ),
        ),
      );
      if (saved != true || !mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report values added to Registry.')),
      );
    }
    if (!mounted || !context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RegistryPatientScreen(
          registry: _registry,
          patient: p,
          source: null,
        ),
      ),
    );
    await _load();
  }

  Future<void> _addPatient({RecordEntry? source}) async {
    final incoming = source ?? widget.source;
    final name = TextEditingController(
      text: incoming?.valueOf(RecordFieldCatalog.subjectName.key),
    );
    final reference = TextEditingController(
      text: incoming?.valueOf(RecordFieldCatalog.patientReference.key),
    );
    final facility = TextEditingController(
      text: incoming?.valueOf(RecordFieldCatalog.facility.key),
    );
    final form = GlobalKey<FormState>();
    final existing = _data.patients
        .where((p) => !p.registryIds.contains(_registry.registryId))
        .toList();
    final choice = await _registryDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add patient'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (existing.isNotEmpty)
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Use an existing patient',
                      ),
                      items: [
                        for (final p in existing)
                          DropdownMenuItem(
                            value: p.id,
                            child: Text(
                              '${_patientLabel(p)} · ${p.reference} · ${p.facility}',
                            ),
                          ),
                      ],
                      onChanged: (id) => Navigator.pop(c, id),
                    ),
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Name (optional with identifier)',
                    ),
                    validator: (_) =>
                        name.text.trim().isEmpty &&
                            reference.text.trim().isEmpty
                        ? 'Enter a name or identifier'
                        : null,
                  ),
                  TextFormField(
                    controller: reference,
                    decoration: const InputDecoration(
                      labelText: 'Patient identifier',
                    ),
                  ),
                  TextFormField(
                    controller: facility,
                    decoration: const InputDecoration(labelText: 'Facility'),
                  ),
                  const Text(
                    'Names alone do not link patients. Select an existing patient when appropriate.',
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(c, 'new');
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    try {
      if (choice == null) return;
      RegistryPatient patient;
      if (choice == 'new') {
        if (incoming != null) {
          patient = RegistryPatient(
            id: newId('patient'),
            name: name.text.trim(),
            reference: reference.text.trim(),
            facility: facility.text.trim(),
            registryIds: [_registry.registryId],
          );
        } else {
          patient = await _repo.addPatient(
            name: name.text,
            reference: reference.text,
            facility: facility.text,
            registryId: _registry.registryId,
          );
        }
      } else {
        await _repo.enroll(choice, _registry.registryId);
        patient = _data.patients.firstWhere((p) => p.id == choice);
      }
      await _load();
      if (mounted) {
        await _openPatient(
          patient,
          source: incoming,
          createPatient: choice == 'new' && incoming != null,
        );
      }
    } catch (e) {
      if (mounted && context.mounted) _error(context, e);
    } finally {
      name.dispose();
      reference.dispose();
      facility.dispose();
    }
  }

  Future<void> _renameRegistry() async {
    final title = await _askText(
      context,
      'Rename registry',
      'Registry name',
      initial: _registry.title,
      action: 'Save',
    );
    if (title == null || !mounted) return;
    try {
      await context.read<RecordsRepository>().updateRegistry(
        registryId: _registry.registryId,
        title: title,
        description: _registry.description,
      );
      if (mounted) await _load();
    } catch (e) {
      if (mounted) _error(context, e);
    }
  }

  bool _editingCell = false;
  Future<void> _editCell(RegistryTableCell cell) async {
    if (_editingCell) return;
    _editingCell = true;
    try {
      await _editRegistryCell(
        context,
        _registry,
        _data.patients.firstWhere((p) => p.id == cell.patientId),
        _data.updates
            .where(
              (u) =>
                  u.registryId == _registry.registryId &&
                  u.patientId == cell.patientId,
            )
            .toList(),
        cell,
      );
      if (mounted) await _load();
    } finally {
      _editingCell = false;
    }
  }

  Future<void> _editField({RecordFieldDef? field, bool add = false}) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RegistryFieldsScreen(
          registry: _registry,
          initialFieldKey: field?.key,
          addOnOpen: add,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _showAddMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person_add_outlined),
                title: const Text('Add patient'),
                onTap: () => Navigator.pop(c, 'patient'),
              ),
              ListTile(
                leading: const Icon(Icons.view_column_outlined),
                title: const Text('Add field'),
                subtitle: const Text('A patient detail or dated measurement'),
                onTap: () => Navigator.pop(c, 'field'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'patient') await _addPatient();
    if (action == 'field') await _editField(add: true);
  }

  Widget _controlPair(Widget first, Widget second) => LayoutBuilder(
    builder: (context, constraints) {
      final wideText = MediaQuery.textScalerOf(context).scale(14) > 20;
      if (constraints.maxWidth < 300 || wideText) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 8), second],
        );
      }
      return Row(
        children: [
          Expanded(child: first),
          const SizedBox(width: 8),
          Expanded(child: second),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final patients = _data.patients.where(
      (p) =>
          p.registryIds.contains(_registry.registryId) &&
          '${p.name} ${p.reference} ${p.facility}'.toLowerCase().contains(
            _query.toLowerCase(),
          ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _registry.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Export / Backup',
            icon: const Icon(Icons.download_outlined),
            onPressed: _loading || _failure != null
                ? null
                : () async {
                    final choice = await showModalBottomSheet<String>(
                      context: context,
                      showDragHandle: true,
                      builder: (sheetContext) => SafeArea(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: const Icon(Icons.table_chart_outlined),
                                title: const Text('CSV for Excel'),
                                subtitle: const Text(
                                  'Current search results and selected latest/all updates view.',
                                ),
                                onTap: () => Navigator.pop(sheetContext, 'csv'),
                              ),
                              ListTile(
                                leading: const Icon(Icons.backup_outlined),
                                title: const Text('Encrypted registry backup'),
                                subtitle: const Text(
                                  'Entire registry, fields and history. Requires a passphrase. Does not include report PDFs.',
                                ),
                                onTap: () =>
                                    Navigator.pop(sheetContext, 'backup'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                    if (!mounted || !context.mounted) return;
                    if (choice == 'csv') {
                      await registryExport(
                        context,
                        RegistryTableData.build(
                          _registry,
                          RegistryData(
                            patients: patients.toList(),
                            updates: _data.updates,
                          ),
                          allUpdates: _allUpdates,
                        ),
                      );
                    } else if (choice == 'backup') {
                      await registryBackup(context, _registry);
                    }
                  },
          ),
          PopupMenuButton<String>(
            tooltip: 'Registry options',
            onSelected: (action) async {
              if (action == 'rename') await _renameRegistry();
              if (!mounted || !context.mounted) return;
              if (action == 'fields') {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => RegistryFieldsScreen(registry: _registry),
                  ),
                );
                if (mounted) await _load();
              }
              if (action == 'restore' && context.mounted) {
                final restored = await registryRestore(context);
                if (!mounted) return;
                await _load();
                if (restored != null && mounted && context.mounted) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          RegistryPatientsScreen(registry: restored),
                    ),
                  );
                  if (mounted) await _load();
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'fields', child: Text('Registry fields')),
              PopupMenuItem(value: 'rename', child: Text('Rename registry')),
              PopupMenuItem(value: 'restore', child: Text('Restore backup')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _failure != null
            ? null
            : widget.source == null
            ? _showAddMenu
            : () => _addPatient(),
        icon: const Icon(Icons.add),
        label: Text(
          widget.source == null ? 'Add' : 'Create patient from report',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failure != null
          ? Center(child: Text(_failure!))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                if (widget.source != null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Use an existing patient below, or choose Create patient from report. Then review and save the values to finish importing.',
                    ),
                  ),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search name, identifier or facility',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      children: [
                        _controlPair(
                          OutlinedButton.icon(
                            icon: Icon(
                              _table
                                  ? Icons.view_list
                                  : Icons.table_chart_outlined,
                            ),
                            label: Text(_table ? 'List view' : 'Table view'),
                            onPressed: () => setState(() => _table = !_table),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.history),
                            label: Text(
                              _allUpdates ? 'Latest values' : 'All updates',
                            ),
                            onPressed: () => setState(() {
                              _allUpdates = !_allUpdates;
                              _table = true;
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _table
                      ? (_allUpdates
                            ? 'Showing all updates'
                            : 'Showing latest values')
                      : 'Showing patients',
                ),
                const SizedBox(height: 12),
                if (patients.isEmpty)
                  const Text('No patients found. Add a patient to begin.'),
                if (_table)
                  RegistryTableView(
                    data: RegistryTableData.build(
                      _registry,
                      RegistryData(
                        patients: patients.toList(),
                        updates: _data.updates,
                      ),
                      allUpdates: _allUpdates,
                    ),
                    onPatient: (id) => _openPatient(
                      _data.patients.firstWhere((p) => p.id == id),
                    ),
                    onCell: widget.source == null ? _editCell : null,
                    onField: widget.source == null
                        ? (field) => _editField(field: field)
                        : null,
                  ),
                if (!_table)
                  for (final p in patients)
                    Card(
                      child: ListTile(
                        title: Text(_patientLabel(p)),
                        subtitle: Text(
                          [
                            p.reference,
                            p.facility,
                          ].where((s) => s.isNotEmpty).join(' · '),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openPatient(p),
                      ),
                    ),
                if (_legacy.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Text(
                      'Existing records — confirm patient to add to history',
                    ),
                  ),
                for (final e in _legacy)
                  ListTile(
                    title: Text(e.valueOf(RecordFieldCatalog.subjectName.key)),
                    subtitle: Text(
                      e.valueOf(RecordFieldCatalog.patientReference.key),
                    ),
                    trailing: const Icon(Icons.person_search),
                    onTap: () async {
                      final selected = await _registryDialog<RegistryPatient>(
                        context: context,
                        builder: (c) => SimpleDialog(
                          title: const Text('Select patient'),
                          children: [
                            for (final p in _data.patients.where(
                              (p) =>
                                  p.registryIds.contains(_registry.registryId),
                            ))
                              SimpleDialogOption(
                                onPressed: () => Navigator.pop(c, p),
                                child: Text(
                                  '${_patientLabel(p)} · ${p.reference} · ${p.facility}',
                                ),
                              ),
                            SimpleDialogOption(
                              onPressed: () => Navigator.pop(c),
                              child: const Text('Cancel'),
                            ),
                          ],
                        ),
                      );
                      if (selected != null && mounted) {
                        await _openPatient(selected, source: e);
                      } else if (mounted && _data.patients.isEmpty) {
                        await _addPatient(source: e);
                      }
                    },
                  ),
              ],
            ),
    );
  }
}

class RegistryPatientScreen extends StatefulWidget {
  final RecordRegistry registry;
  final RegistryPatient patient;
  final RecordEntry? source;
  const RegistryPatientScreen({
    super.key,
    required this.registry,
    required this.patient,
    this.source,
  });
  @override
  State<RegistryPatientScreen> createState() => _RegistryPatientScreenState();
}

class _RegistryPatientScreenState extends State<RegistryPatientScreen> {
  bool _table = false;
  final _repo = RegistryRepository();
  List<RegistryUpdate> _updates = [];
  late RegistryPatient _patient;
  late RecordRegistry _registry;
  bool _editingCell = false;
  String? _failure;
  List<ReportSummary> _allReports = const [];
  List<ReportSummary> _relatedReports = const [];
  @override
  void initState() {
    super.initState();
    _patient = widget.patient;
    _registry = widget.registry;
    _load().then((_) {
      if (mounted &&
          widget.source != null &&
          !_updates.any(
            (u) => u.sourceReportId == widget.source!.linkedReportId,
          )) {
        _add(source: widget.source);
      }
    });
  }

  Future<void> _load() async {
    try {
      final registries = await context
          .read<RecordsRepository>()
          .loadRegistries();
      final data = await _repo.load();
      final reports = await context.read<ReportsRepository>().listReports();
      _registry = registries.firstWhere(
        (r) => r.registryId == widget.registry.registryId,
        orElse: () => widget.registry,
      );
      _patient = data.patients.firstWhere(
        (p) => p.id == _patient.id,
        orElse: () => _patient,
      );
      if (mounted) {
        final updates =
            data.updates
                .where(
                  (u) =>
                      u.patientId == _patient.id &&
                      u.registryId == widget.registry.registryId,
                )
                .toList()
              ..sort((a, b) {
                final date = b.observedAt.compareTo(a.observedAt);
                return date == 0
                    ? b.recordedAt.compareTo(a.recordedAt)
                    : date;
              });
        final relatedIds = <String>{
          ..._patient.relatedReportIds,
          for (final update in updates)
            if (update.sourceReportId.isNotEmpty) update.sourceReportId,
        };
        setState(() {
          _updates = updates;
          _allReports = reports;
          _relatedReports = reports
              .where((report) => relatedIds.contains(report.reportId))
              .toList(growable: false);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _failure = e.toString());
    }
  }

  Future<void> _add({RecordEntry? source, bool patientDetails = false}) async {
    final registries = await context.read<RecordsRepository>().loadRegistries();
    if (!mounted || !context.mounted) return;
    final registry = registries.firstWhere(
      (r) => r.registryId == widget.registry.registryId,
      orElse: () => widget.registry,
    );
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RegistryUpdateScreen(
          registry: registry,
          patient: _patient,
          source: source,
          patientDetails: patientDetails,
          editPatient: patientDetails,
          previousUpdates: _updates,
        ),
      ),
    );
    await _load();
  }

  Future<void> _showUpdateMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add_chart),
                title: const Text('Add dated update'),
                subtitle: const Text('Record new measurements and findings'),
                onTap: () => Navigator.pop(c, 'dated'),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Edit patient details'),
                subtitle: const Text(
                  'Name, identifier and details entered once',
                ),
                onTap: () => Navigator.pop(c, 'details'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    await _add(patientDetails: action == 'details');
  }

  Future<void> _correct(RegistryUpdate update) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RegistryUpdateScreen(
          registry: _registry,
          patient: _patient,
          patientDetails: update.patientDetails,
          correction: update,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _editCell(RegistryTableCell cell) async {
    if (_editingCell) return;
    _editingCell = true;
    try {
      await _editRegistryCell(context, _registry, _patient, _updates, cell);
      if (mounted) await _load();
    } finally {
      _editingCell = false;
    }
  }

  Future<void> _linkReport() async {
    final linked = <String>{
      ..._patient.relatedReportIds,
      for (final update in _updates)
        if (update.sourceReportId.isNotEmpty) update.sourceReportId,
    };
    final candidates = _allReports
        .where((report) => report.hasPdf && !linked.contains(report.reportId))
        .toList(growable: false);
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other finalized reports are available to link.')),
      );
      return;
    }
    final reportId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .65,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              const ListTile(
                title: Text('Link existing report'),
                subtitle: Text(
                  'Choose a report that belongs to this patient. Ripot will not link reports automatically by name alone.',
                ),
              ),
              for (final report in candidates)
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(report.title),
                  subtitle: Text(report.subtitle),
                  onTap: () => Navigator.pop(sheetContext, report.reportId),
                ),
            ],
          ),
        ),
      ),
    );
    if (reportId == null || !mounted) return;
    try {
      await _repo.linkReport(_patient.id, reportId);
      await _load();
    } catch (e) {
      if (mounted) _error(context, e);
    }
  }

  Future<void> _unlinkReport(String reportId) async {
    try {
      await _repo.unlinkReport(_patient.id, reportId);
      await _load();
    } catch (e) {
      if (mounted) _error(context, e);
    }
  }

  Future<void> _openRegistryImage(RegistryImageAttachment image) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              child: RefImage(
                image.ref,
                fit: BoxFit.contain,
                width: double.infinity,
                height: MediaQuery.sizeOf(dialogContext).height * .75,
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _remove() async {
    final data = await _repo.load();
    if (!mounted) return;
    final count = data.updates
        .where(
          (u) =>
              u.registryId == widget.registry.registryId &&
              u.patientId == _patient.id,
        )
        .length;
    final yes = await registryConfirm(
      context,
      'Remove ${_patientLabel(_patient)}?',
      'Remove this patient from ${widget.registry.title} and delete their $count updates in this registry? This cannot be undone. Other registries and source reports are kept.',
      'Remove patient',
    );
    if (!yes || !mounted) return;
    try {
      await _repo.removePatient(widget.registry.registryId, _patient.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _error(context, e);
    }
  }

  Future<void> _deleteUpdate(RegistryUpdate update) async {
    final yes = await registryConfirm(
      context,
      update.patientDetails
          ? 'Delete patient details revision?'
          : 'Delete dated update?',
      update.patientDetails
          ? 'Delete this patient details revision? Earlier values may become current again. This cannot be undone. Other entries are kept.'
          : 'Delete the update for ${_patientLabel(_patient)} observed on ${_date(update.observedAt)}? This cannot be undone. The patient, other updates and source report are kept.',
      'Delete update',
    );
    if (!yes || !mounted) return;
    try {
      await _repo.deleteUpdate(widget.registry.registryId, update.id);
      await _load();
    } catch (e) {
      if (mounted) _error(context, e);
    }
  }

  Future<void> _openSource(String reportId) async {
    try {
      final repo = context.read<ReportsRepository>();
      final bytes = await repo.loadPdfBytesForReport(reportId);
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        _error(
          context,
          'The source report PDF is not available on this device.',
        );
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => SavedPdfViewerScreen(
            title: 'Source report',
            pdfFileName: '$reportId.pdf',
            pdfBytesFuture: Future.value(bytes),
          ),
        ),
      );
    } catch (e) {
      if (mounted) _error(context, e);
    }
  }

  List<Widget> _patientDetailsSummary() {
    final revisions = _updates.where((u) => u.patientDetails).toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    final seen = <String>{};
    final widgets = <Widget>[];
    for (final revision in revisions) {
      for (final entry in revision.values.entries) {
        if (!seen.add(entry.key)) continue;
        if (entry.value.isEmpty) continue;
        final definition = revision.definitions[entry.key];
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${definition?.label ?? entry.key}: ${entry.value} ${definition?.unit ?? ''}'
                  .trim(),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        _patientLabel(_patient),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Patient options',
          onSelected: (action) async {
            if (action == 'link') await _linkReport();
            if (action == 'remove') await _remove();
            if (action == 'export' && mounted && context.mounted) {
              await registryExport(
                context,
                RegistryTableData.build(
                  _registry,
                  RegistryData(patients: [_patient], updates: _updates),
                  patientId: _patient.id,
                ),
              );
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'link', child: Text('Link existing report')),
            PopupMenuItem(value: 'export', child: Text('Export CSV')),
            PopupMenuItem(
              value: 'remove',
              child: Text('Remove patient from registry'),
            ),
          ],
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _showUpdateMenu,
      icon: const Icon(Icons.add),
      label: const Text('Update'),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_patient.reference.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Patient identifier: ${_patient.reference}'),
                ),
              if (_patient.facility.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Facility: ${_patient.facility}'),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Registry: ${widget.registry.title}'),
              ),
              ..._patientDetailsSummary(),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: Icon(_table ? Icons.view_list : Icons.table_chart_outlined),
              label: Text(_table ? 'List view' : 'History table'),
              onPressed: () => setState(() => _table = !_table),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Related reports',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _linkReport,
                      icon: const Icon(Icons.link),
                      label: const Text('Link report'),
                    ),
                  ],
                ),
                if (_relatedReports.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('No reports linked to this patient yet.'),
                  )
                else
                  for (final report in _relatedReports)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.description_outlined),
                      title: Text(report.title),
                      subtitle: Text(report.subtitle),
                      onTap: () => _openSource(report.reportId),
                      trailing: _updates.any(
                        (update) => update.sourceReportId == report.reportId,
                      )
                          ? const Tooltip(
                              message: 'Linked by a Registry update',
                              child: Icon(Icons.link),
                            )
                          : PopupMenuButton<String>(
                              tooltip: 'Related report options',
                              onSelected: (action) async {
                                if (action == 'unlink') {
                                  await _unlinkReport(report.reportId);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'unlink',
                                  child: Text('Unlink report'),
                                ),
                              ],
                            ),
                    ),
              ],
            ),
          ),
        ),
        if (_failure != null) Text(_failure!),
        if (_updates.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No updates yet. Each new entry preserves the previous values.',
            ),
          ),
        if (_table)
          RegistryTableView(
            data: RegistryTableData.build(
              _registry,
              RegistryData(patients: [_patient], updates: _updates),
              patientId: _patient.id,
            ),
            onCell: _editCell,
          ),
        if (!_table)
          for (final u in _updates)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            u.patientDetails
                                ? 'Patient details · ${_date(u.recordedAt)}'
                                : _date(u.observedAt),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Entry options',
                          onSelected: (action) async {
                            if (action == 'correct') await _correct(u);
                            if (action == 'delete') await _deleteUpdate(u);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'correct',
                              enabled: u.values.keys.every(
                                u.definitions.containsKey,
                              ),
                              child: const Text('Correct this entry'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete this entry'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Text(
                      u.sourceReportId.isEmpty
                          ? 'Entered in Registry'
                          : 'From ${formatReportIdForDisplay(u.sourceReportId)}',
                    ),
                    if (u.sourceReportId.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => _openSource(u.sourceReportId),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Open source report'),
                      ),
                    if (u.images.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 82,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: u.images.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, index) {
                            final image = u.images[index];
                            return InkWell(
                              onTap: () => _openRegistryImage(image),
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: 96,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: RefImage(
                                        image.ref,
                                        width: 82,
                                        height: 64,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    if (image.label.trim().isNotEmpty)
                                      Text(
                                        image.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    for (final group
                        in u.values.keys
                            .map((k) => u.definitions[k]?.groupName ?? '')
                            .toSet()) ...[
                      if (group.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            group,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      for (final v in u.values.entries.where(
                        (v) => (u.definitions[v.key]?.groupName ?? '') == group,
                      ))
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${u.definitions[v.key]?.label ?? v.key}: ${v.value} ${u.definitions[v.key]?.unit ?? ''}',
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
      ],
    ),
  );
}

class RegistryUpdateScreen extends StatefulWidget {
  final RecordRegistry registry;
  final RegistryPatient patient;
  final RecordEntry? source;
  final bool createPatient;
  final bool patientDetails;
  final List<RegistryUpdate> previousUpdates;
  final bool editPatient;
  final RegistryUpdate? correction;
  final bool quickEntry;
  final String? initialFieldKey;
  const RegistryUpdateScreen({
    super.key,
    required this.registry,
    required this.patient,
    this.source,
    this.createPatient = false,
    this.patientDetails = false,
    this.previousUpdates = const [],
    this.editPatient = false,
    this.correction,
    this.quickEntry = false,
    this.initialFieldKey,
  });
  @override
  State<RegistryUpdateScreen> createState() => _RegistryUpdateScreenState();
}

class _RegistryUpdateScreenState extends State<RegistryUpdateScreen> {
  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _selected = <String>{};
  late List<RecordFieldDef> _fields;
  late DateTime _observed;
  final _id = newId('observation');
  bool _saving = false;
  int _fieldIndex = 0;
  final ImageService _imageService = ImageService();
  final List<RegistryImageAttachment> _images = [];
  List<RegistryImageAttachment> _reportImages = const [];
  bool _loadingReportImages = false;
  late final TextEditingController _name, _reference, _facility;
  List<RecordFieldDef> get _visibleFields =>
      widget.quickEntry && _fields.isNotEmpty
      ? [_fields[_fieldIndex]]
      : _fields;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.patient.name);
    _reference = TextEditingController(text: widget.patient.reference);
    _facility = TextEditingController(text: widget.patient.facility);
    _observed =
        widget.correction?.observedAt ??
        DateTime.tryParse(
          widget.source?.valueOf(RecordFieldCatalog.reportDate.key) ?? '',
        ) ??
        DateTime.now();
    final defs = {for (final f in widget.registry.fields) f.key: f};
    final source = widget.source;
    if (source != null) {
      for (final e in source.values.entries) {
        if (e.value.trim().isEmpty ||
            {
              RecordFieldCatalog.reportId.key,
              RecordFieldCatalog.reportDate.key,
              RecordFieldCatalog.subjectName.key,
              RecordFieldCatalog.patientReference.key,
            }.contains(e.key)) {
          continue;
        }
        if (defs[e.key]?.patientDetail == true) continue;
        defs[e.key] =
            source.fieldDefinitions[e.key] ??
            defs[e.key] ??
            RecordFieldDef(
              key: e.key,
              label:
                  source.fieldLabels[e.key] ??
                  RecordFieldCatalog.byKey(e.key)?.label ??
                  e.key,
              hint: '',
            );
      }
    }
    _fields = defs.values
        .where((f) => f.patientDetail == widget.patientDetails)
        .toList();
    if (widget.correction != null) {
      _fields = [
        for (final key in widget.correction!.values.keys)
          if (widget.correction!.definitions[key] != null)
            widget.correction!.definitions[key]!,
      ];
    }
    final initial = _fields.indexWhere((f) => f.key == widget.initialFieldKey);
    _fieldIndex = initial < 0 ? 0 : initial;
    // The source facility belongs to this dated event, not the patient's
    // directory identity. It remains visible and editable before saving.
    if ((source?.valueOf(RecordFieldCatalog.facility.key) ?? '')
        .trim()
        .isNotEmpty) {
      _selected.add(RecordFieldCatalog.facility.key);
    }
    for (final f in _fields) {
      _controllers[f.key] = TextEditingController(
        text:
            widget.correction?.values[f.key] ??
            (widget.patientDetails
                ? _previousValue(f)
                : source?.values[f.key] ?? ''),
      );
    }
    _images.addAll(widget.correction?.images ?? const []);
    if (source != null && !widget.patientDetails) {
      _loadReportImages(source.linkedReportId);
    }
  }

  Future<void> _loadReportImages(String reportId) async {
    if (reportId.trim().isEmpty) return;
    if (mounted) setState(() => _loadingReportImages = true);
    try {
      final doc = await ReportsRepository().loadReport(reportId);
      final loaded = [
        for (final image in doc.images)
          RegistryImageAttachment(
            id: 'report_${reportId}_${image.id}',
            ref: image.filePath,
            label: image.label,
            sourceReportId: reportId,
          ),
      ];
      if (mounted) {
        setState(() {
          _reportImages = loaded;
          _loadingReportImages = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingReportImages = false);
    }
  }

  Future<void> _addImagesFromDevice() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose images'),
              onTap: () => Navigator.pop(sheetContext, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(sheetContext, 'camera'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      final refs = <String>[];
      if (choice == 'camera') {
        final ref = await _imageService.pickFromCamera();
        if (ref != null && ref.trim().isNotEmpty) refs.add(ref);
      } else {
        refs.addAll(await _imageService.pickMultiFromGallery());
      }
      if (refs.isEmpty || !mounted) return;
      setState(() {
        for (final ref in refs) {
          _images.add(
            RegistryImageAttachment(
              id: newId('registry_image'),
              ref: ref,
            ),
          );
        }
      });
    } catch (e) {
      if (mounted) _error(context, e);
    }
  }

  Future<void> _editRegistryImageLabel(
    RegistryImageAttachment image,
  ) async {
    final controller = TextEditingController(text: image.label);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Image caption'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(
            labelText: 'Caption (optional)',
            hintText: 'e.g. Ulcer at week 4',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final label = controller.text.trim();
    controller.dispose();
    if (saved != true || !mounted) return;
    setState(() {
      final index = _images.indexWhere((item) => item.id == image.id);
      if (index < 0) return;
      _images[index] = RegistryImageAttachment(
        id: image.id,
        ref: image.ref,
        label: label,
        sourceReportId: image.sourceReportId,
      );
    });
  }

  String _previousValue(RecordFieldDef field) {
    final history =
        widget.previousUpdates
            .where(
              (u) =>
                  u.patientDetails &&
                  u.values.containsKey(field.key) &&
                  u.definitions[field.key] != null &&
                  RegistryTableData.fieldIdentity(u.definitions[field.key]!) ==
                      RegistryTableData.fieldIdentity(field),
            )
            .toList()
          ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return history.isEmpty ? '' : history.first.values[field.key] ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _reference.dispose();
    _facility.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final values = {
      for (final f in _fields)
        if ((widget.source == null ||
                _selected.contains(f.key) ||
                !widget.source!.values.containsKey(f.key)) &&
            (widget.patientDetails ||
                _controllers[f.key]!.text.trim().isNotEmpty) &&
            (!widget.patientDetails ||
                widget.correction != null ||
                _controllers[f.key]!.text.trim() != _previousValue(f)))
          f.key: _controllers[f.key]!.text.trim(),
    };
    if (values.isEmpty &&
        widget.patientDetails &&
        widget.correction == null &&
        !widget.editPatient) {
      Navigator.pop(context, true);
      return;
    }
    if (values.isEmpty && _images.isEmpty && !widget.editPatient) {
      _error(context, 'Enter a value or add an image.');
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = RegistryRepository();
      final update = RegistryUpdate(
        id: _id,
        patientDetails: widget.patientDetails,
        registryId: widget.registry.registryId,
        patientId: widget.patient.id,
        patientName: widget.editPatient
            ? (_name.text.trim().isEmpty
                  ? _reference.text.trim()
                  : _name.text.trim())
            : _patientLabel(widget.patient),
        observedAt: _observed,
        recordedAt: DateTime.now(),
        values: values,
        definitions: {
          for (final f in _fields)
            if (values.containsKey(f.key)) f.key: f,
        },
        images: List<RegistryImageAttachment>.from(_images),
        sourceReportId: widget.source?.linkedReportId ?? '',
      );
      if (widget.correction != null) {
        await repo.correctUpdate(
          expected: widget.correction!,
          values: values,
          observedAt: _observed,
          images: List<RegistryImageAttachment>.from(_images),
        );
      } else if (widget.editPatient) {
        await repo.editPatient(
          expected: widget.patient,
          name: _name.text,
          reference: _reference.text,
          facility: _facility.text,
          details: values.isEmpty ? null : update,
        );
      } else {
        await repo.addUpdate(
          update,
          newPatient: widget.createPatient ? widget.patient : null,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _error(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.correction != null
            ? 'Correct this entry'
            : widget.patientDetails
            ? 'Patient details'
            : 'Add dated update',
      ),
    ),
    bottomNavigationBar: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed:
              _saving ||
                  (_fields.isEmpty && _images.isEmpty && !widget.editPatient)
              ? null
              : _save,
          child: Text(
            _saving
                ? 'Saving…'
                : widget.correction != null
                ? 'Save correction'
                : widget.patientDetails
                ? 'Save patient details'
                : 'Save update',
          ),
        ),
      ),
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!widget.editPatient)
            Text(
              _patientLabel(widget.patient),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          if (widget.correction != null)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Correcting a saved entry, not adding a new observation. Original field settings and other entries are kept. The source report is unchanged.',
              ),
            ),
          if (widget.patientDetails && widget.correction == null)
            const Text(
              'Enter once and edit when needed. Previous versions remain in history.',
            ),
          if (widget.editPatient) ...[
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('patient-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Patient name'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty && _reference.text.trim().isEmpty
                  ? 'Enter a name or patient identifier'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const ValueKey('patient-reference'),
              controller: _reference,
              decoration: const InputDecoration(
                labelText: 'Patient identifier',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const ValueKey('patient-facility'),
              controller: _facility,
              decoration: const InputDecoration(labelText: 'Facility'),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Name, identifier and facility apply wherever this patient is enrolled. Saved entries keep their original snapshots.',
              ),
            ),
          ],
          if (!widget.patientDetails)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date of observation'),
              subtitle: Text(_date(_observed)),
              trailing: const Icon(Icons.calendar_month),
              onTap: _saving
                  ? null
                  : () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _observed,
                        firstDate: DateTime(1900),
                        lastDate: _observed.isAfter(DateTime.now())
                            ? _observed
                            : DateTime.now(),
                      );
                      if (d != null && mounted) setState(() => _observed = d);
                    },
            ),
          if (widget.source != null)
            const Text(
              'Choose the dated report values to include. Patient details are edited separately on the patient page. Saving does not change the report or Records.',
            ),
          if (!widget.patientDetails) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Images',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: _saving ? null : _addImagesFromDevice,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Add images'),
                ),
              ],
            ),
            if (_loadingReportImages)
              const LinearProgressIndicator()
            else if (_reportImages.isNotEmpty) ...[
              const Text(
                'Select any images from the source report that should appear with this dated Registry update.',
              ),
              const SizedBox(height: 8),
              for (final reportImage in _reportImages)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: RefImage(
                      reportImage.ref,
                      width: 54,
                      height: 54,
                      fit: BoxFit.cover,
                    ),
                  ),
                  title: Text(
                    reportImage.label.trim().isEmpty
                        ? 'Report image'
                        : reportImage.label,
                  ),
                  subtitle: const Text('From source report'),
                  value: _images.any((image) => image.id == reportImage.id),
                  onChanged: _saving
                      ? null
                      : (selected) => setState(() {
                          _images.removeWhere(
                            (image) => image.id == reportImage.id,
                          );
                          if (selected == true) _images.add(reportImage);
                        }),
                ),
            ],
            if (_images.any((image) => image.sourceReportId.isEmpty)) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 78,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _images
                      .where((image) => image.sourceReportId.isEmpty)
                      .length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, index) {
                    final direct = _images
                        .where((image) => image.sourceReportId.isEmpty)
                        .toList(growable: false)[index];
                    return SizedBox(
                      width: 96,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            top: 0,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: RefImage(
                                direct.ref,
                                width: 78,
                                height: 78,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          if (direct.label.trim().isNotEmpty)
                            Positioned(
                              left: 4,
                              right: 18,
                              bottom: 2,
                              child: Text(
                                direct.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Column(
                              children: [
                                IconButton.filledTonal(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Edit caption',
                                  onPressed: _saving
                                      ? null
                                      : () => _editRegistryImageLabel(direct),
                                  icon: const Icon(Icons.edit_outlined, size: 15),
                                ),
                                IconButton.filledTonal(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Remove image',
                                  onPressed: _saving
                                      ? null
                                      : () => setState(
                                            () => _images.removeWhere(
                                              (image) => image.id == direct.id,
                                            ),
                                          ),
                                  icon: const Icon(Icons.close, size: 16),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
          if (_fields.isEmpty && widget.correction == null) ...[
            const Text(
              'Add fields and choose Patient detail or Dated measurement. Only fields for this view appear here.',
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add fields'),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        RegistryFieldsScreen(registry: widget.registry),
                  ),
                );
                if (!mounted || !context.mounted) return;
                final registries = await context
                    .read<RecordsRepository>()
                    .loadRegistries();
                if (!mounted || !context.mounted) return;
                final registry = registries.firstWhere(
                  (r) => r.registryId == widget.registry.registryId,
                );
                setState(() {
                  _fields = registry.fields
                      .where((f) => f.patientDetail == widget.patientDetails)
                      .toList();
                  for (final f in _fields) {
                    _controllers.putIfAbsent(
                      f.key,
                      () => TextEditingController(),
                    );
                  }
                });
              },
            ),
          ],
          if (widget.quickEntry && _fields.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Field ${_fieldIndex + 1} of ${_fields.length} · Save when finished',
              ),
            ),
          ],
          for (final group
              in _visibleFields.map((f) => f.groupName).toSet()) ...[
            if (group.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  group,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            for (final f in _visibleFields.where((f) => f.groupName == group))
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  children: [
                    if (widget.source?.values.containsKey(f.key) == true)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Include ${f.label}'),
                        value: _selected.contains(f.key),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(f.key);
                          } else {
                            _selected.remove(f.key);
                          }
                        }),
                      ),
                    KeyedSubtree(
                      key: ValueKey('registry-input-${f.key}'),
                      child: _input(f),
                    ),
                  ],
                ),
              ),
          ],
          if (widget.quickEntry && _fields.length > 1)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _saving || _fieldIndex == 0
                      ? null
                      : () {
                          FocusScope.of(context).unfocus();
                          if (_form.currentState!.validate()) {
                            setState(() => _fieldIndex--);
                          }
                        },
                  child: const Text('Previous field'),
                ),
                OutlinedButton(
                  onPressed: _saving || _fieldIndex == _fields.length - 1
                      ? null
                      : () {
                          FocusScope.of(context).unfocus();
                          if (_form.currentState!.validate()) {
                            setState(() => _fieldIndex++);
                          }
                        },
                  child: const Text('Next field'),
                ),
              ],
            ),
        ],
      ),
    ),
  );
  Widget _input(RecordFieldDef f) {
    final enabled =
        !_saving &&
        (widget.source?.values.containsKey(f.key) != true ||
            _selected.contains(f.key));
    if (f.inputType == RecordInputType.yesNo ||
        f.inputType == RecordInputType.singleSelect) {
      final choices = {
        if (f.inputType == RecordInputType.yesNo) ...[
          'Yes',
          'No',
        ] else
          ...f.options,
        if (_controllers[f.key]!.text.isNotEmpty) _controllers[f.key]!.text,
      };
      return DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: _controllers[f.key]!.text.isEmpty
            ? null
            : _controllers[f.key]!.text,
        decoration: InputDecoration(labelText: f.label),
        items: [
          const DropdownMenuItem(value: '', child: Text('Not recorded')),
          for (final v in choices) DropdownMenuItem(value: v, child: Text(v)),
        ],
        onChanged: enabled ? (v) => _controllers[f.key]!.text = v ?? '' : null,
      );
    }
    if (f.inputType == RecordInputType.multiSelect) {
      final selected = _controllers[f.key]!.text
          .split(';')
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toSet();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(f.label),
          Wrap(
            spacing: 8,
            children: [
              for (final option in {...f.options, ...selected})
                FilterChip(
                  label: Text(option),
                  selected: selected.contains(option),
                  onSelected: enabled
                      ? (v) => setState(() {
                          if (v) {
                            selected.add(option);
                          } else {
                            selected.remove(option);
                          }
                          _controllers[f.key]!.text = selected.join('; ');
                        })
                      : null,
                ),
            ],
          ),
        ],
      );
    }
    return TextFormField(
      controller: _controllers[f.key],
      enabled: enabled,
      decoration: InputDecoration(
        labelText: f.label,
        suffixText: f.unit.isEmpty ? null : f.unit,
      ),
      keyboardType: f.inputType == RecordInputType.numeric
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.multiline,
      minLines: 1,
      maxLines: f.inputType == RecordInputType.numeric ? 1 : 3,
      validator: (v) {
        if (!enabled ||
            (v ?? '').trim().isEmpty ||
            f.inputType != RecordInputType.numeric) {
          return null;
        }
        final n = double.tryParse(v!.trim());
        return n == null || !n.isFinite ? 'Enter a valid number' : null;
      },
    );
  }
}

class RegistryFieldsScreen extends StatefulWidget {
  final RecordRegistry registry;
  final String? initialFieldKey;
  final bool addOnOpen;
  const RegistryFieldsScreen({
    super.key,
    required this.registry,
    this.initialFieldKey,
    this.addOnOpen = false,
  });
  @override
  State<RegistryFieldsScreen> createState() => _RegistryFieldsScreenState();
}

class _RegistryFieldsScreenState extends State<RegistryFieldsScreen> {
  late List<RecordFieldDef> _fields;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _fields = [...widget.registry.fields];
    if (widget.addOnOpen || widget.initialFieldKey != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        var close = false;
        if (widget.addOnOpen) {
          close = await _add();
        } else {
          final matches = _fields.where((f) => f.key == widget.initialFieldKey);
          if (matches.isNotEmpty) close = await _add(existing: matches.first);
        }
        if (close && mounted) Navigator.pop(context);
      });
    }
  }

  Future<bool> _persist(List<RecordFieldDef> fields) async {
    setState(() => _saving = true);
    try {
      await context.read<RecordsRepository>().saveRegistryFields(
        widget.registry.registryId,
        fields,
      );
      if (mounted) setState(() => _fields = fields);
      return true;
    } catch (e) {
      if (mounted && context.mounted) _error(context, e);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _add({RecordFieldDef? existing}) async {
    final label = TextEditingController(text: existing?.label),
        unit = TextEditingController(text: existing?.unit),
        group = TextEditingController(text: existing?.groupName),
        options = TextEditingController(text: existing?.options.join('\n'));
    var type = existing?.inputType ?? RecordInputType.freeText;
    var patientDetail = existing?.patientDetail ?? false;
    final existingGroups =
        _fields
            .map((field) => field.groupName.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final form = GlobalKey<FormState>();
    final accepted = await _registryDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: Text(
            existing == null ? 'Add registry field' : 'Edit registry field',
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      key: const ValueKey('registry-field-label'),
                      controller: label,
                      decoration: const InputDecoration(
                        labelText: 'Field name',
                      ),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Enter a name' : null,
                    ),
                    DropdownButtonFormField<bool>(
                      initialValue: patientDetail,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Field type',
                      ),
                      items: const [
                        DropdownMenuItem<bool>(
                          value: true,
                          child: Text('Patient detail'),
                        ),
                        DropdownMenuItem<bool>(
                          value: false,
                          child: Text('Dated measurement'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setLocal(() => patientDetail = v);
                        }
                      },
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 4),
                        child: Text(
                          patientDetail
                              ? 'Fixed information, e.g. sex or date of birth.'
                              : 'Recorded on a date and followed over time, e.g. weight or haemoglobin.',
                        ),
                      ),
                    ),
                    DropdownButtonFormField<RecordInputType>(
                      initialValue: type,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Input type',
                      ),
                      items: [
                        for (final t in RecordInputType.values)
                          DropdownMenuItem(
                            value: t,
                            child: Text(
                              const [
                                'Text',
                                'Yes / No',
                                'Single choice',
                                'Multiple choices',
                                'Number',
                              ][t.index],
                            ),
                          ),
                      ],
                      onChanged: (v) => setLocal(() => type = v!),
                    ),
                    if (type == RecordInputType.numeric)
                      TextFormField(
                        key: const ValueKey('registry-field-unit'),
                        controller: unit,
                        decoration: const InputDecoration(
                          labelText: 'Unit, e.g. g/dL',
                        ),
                      ),
                    if (type == RecordInputType.singleSelect ||
                        type == RecordInputType.multiSelect)
                      TextFormField(
                        key: const ValueKey('registry-field-options'),
                        controller: options,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Choices, one per line',
                        ),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? 'Add choices' : null,
                      ),
                    TextFormField(
                      key: const ValueKey('registry-field-group'),
                      controller: group,
                      decoration: const InputDecoration(
                        labelText: 'Group (optional)',
                        hintText: 'e.g. Full blood count',
                      ),
                    ),
                    if (existingGroups.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Use an existing group',
                          style: Theme.of(c).textTheme.labelMedium,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          children: [
                            for (final name in existingGroups)
                              ActionChip(
                                label: Text(name),
                                onPressed: () => setLocal(() {
                                  group.text = name;
                                }),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const Text(
                      'Changes apply to future entries. Changing Patient detail does not move old values; enter the current value in the new view. History keeps its original labels and units.',
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(c, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    var completed = accepted != true;
    if (accepted == true && mounted) {
      final field = RecordFieldDef(
        key: existing?.key ?? newId('registry_field'),
        label: label.text.trim(),
        hint: '',
        isSystem: false,
        registryId: widget.registry.registryId,
        inputType: type,
        patientDetail: patientDetail,
        unit: type == RecordInputType.numeric ? unit.text.trim() : '',
        groupName: group.text.trim(),
        options: options.text
            .split('\n')
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList(),
      );
      completed = await _persist([
        for (final f in _fields)
          if (f.key == field.key) field else f,
        if (existing == null) field,
      ]);
    }
    label.dispose();
    unit.dispose();
    group.dispose();
    options.dispose();
    return completed;
  }

  Widget _fieldTile(RecordFieldDef field) => ListTile(
    title: Text(field.label),
    subtitle: Text(
      [
        field.patientDetail ? 'Patient detail' : 'Dated measurement',
        field.unit,
      ].where((v) => v.isNotEmpty).join(' · '),
    ),
    onTap: _saving ? null : () => _add(existing: field),
    trailing: IconButton(
      tooltip: 'Retire field',
      icon: const Icon(Icons.archive_outlined),
      onPressed: _saving ? null : () => _retire(field),
    ),
  );

  Future<void> _retire(RecordFieldDef field) async {
    final yes = await _registryDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Retire ${field.label}?'),
        content: const Text(
          'Remove it from future entry forms. Saved history will remain unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Retire'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await _persist(_fields.where((item) => item.key != field.key).toList());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Registry fields')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Choose patient details entered once or measurements recorded over time. Leave measurements blank when they were not taken.',
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _saving ? null : () => _add(),
            icon: const Icon(Icons.add),
            label: const Text('Add field'),
          ),
        ),
        const SizedBox(height: 12),
        if (_fields.isEmpty) const Text('No fields yet. Add a field to begin.'),
        for (final groupName
            in _fields.map((field) => field.groupName.trim()).toSet())
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Text(
                    groupName.isEmpty ? 'Ungrouped fields' : groupName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final field in _fields.where(
                  (field) => field.groupName.trim() == groupName,
                ))
                  _fieldTile(field),
              ],
            ),
          ),
      ],
    ),
  );
}

Future<String?> _askText(
  BuildContext context,
  String title,
  String label, {
  String initial = '',
  String action = 'Create',
}) async {
  final controller = TextEditingController(text: initial);
  final form = GlobalKey<FormState>();
  final value = await _registryDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Form(
        key: form,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(c, controller.text.trim());
            }
          },
          child: Text(action),
        ),
      ],
    ),
  );
  controller.dispose();
  return value;
}
