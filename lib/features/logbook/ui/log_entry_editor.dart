import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/ui/item_actions.dart';
import '../data/logbook_repository.dart';
import '../domain/logbook_models.dart';
import 'doctor_directory.dart';

class LogEntryEditor extends StatefulWidget {
  final LogEntry? entry;
  final LogData? prefill;
  final String linkedReportId;
  const LogEntryEditor({
    super.key,
    this.entry,
    this.prefill,
    this.linkedReportId = '',
  });
  @override
  State<LogEntryEditor> createState() => _LogEntryEditorState();
}

class _LogEntryEditorState extends State<LogEntryEditor> {
  final _form = GlobalKey<FormState>();
  late TextEditingController _procedure, _facility, _reference, _notes;
  late DateTime _date;
  late List<LogParticipant> _participants;
  late String _supervisorId;
  late List<LogField> _fields;
  late String _reportAuthor;
  bool _busy = false, _dirty = false, _allowPop = false;
  @override
  void initState() {
    super.initState();
    final repo = context.read<LogbookRepository>();
    final initial =
        widget.entry?.data ??
        widget.prefill ??
        LogData(
          procedure: '',
          procedureDate: DateTime.now(),
          participants: repo.data.meId.isEmpty
              ? []
              : [LogParticipant(repo.data.meId, ProcedureRole.performer)],
        );
    _procedure = TextEditingController(text: initial.procedure);
    _facility = TextEditingController(text: initial.facility);
    _reference = TextEditingController(text: initial.reference);
    _notes = TextEditingController(text: initial.notes);
    _date = initial.procedureDate;
    _participants = [...initial.participants];
    _supervisorId = initial.supervisorId;
    _fields = [...initial.fields];
    _reportAuthor = initial.reportAuthor;
    for (final c in [_procedure, _facility, _reference, _notes]) {
      c.addListener(() => _dirty = true);
    }
  }

  @override
  void dispose() {
    for (final c in [_procedure, _facility, _reference, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_participants.isEmpty) {
      showMessage(
        context,
        'Choose the doctor whose procedure you are logging.',
      );
      return;
    }
    if (widget.entry == null) {
      final confirmed = await confirmAction(
        context,
        'Save completed procedure?',
        'This creates a logbook entry confirming that the procedure took place. Review the date and participants before saving.',
        action: 'Save log',
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final repo = context.read<LogbookRepository>();
      final data = LogData(
        procedure: _procedure.text.trim(),
        procedureDate: _date,
        facility: _facility.text.trim(),
        reference: _reference.text.trim(),
        notes: _notes.text.trim(),
        supervisorId: _supervisorId,
        participants: _participants,
        fields: _fields,
        reportAuthor: _reportAuthor,
      );
      final e = widget.entry;
      final next = e == null
          ? repo.draft(data, linkedReportId: widget.linkedReportId)
          : LogEntry(
              id: e.id,
              linkedReportId: e.linkedReportId,
              createdAt: e.createdAt,
              updatedAt: DateTime.now(),
              data: data,
            );
      await repo.saveEntry(next, expectedRevision: e?.revision);
      if (!mounted) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, next.id);
      });
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          'Could not save. If this entry changed elsewhere, reopen it. Your unsaved input is still here.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPerson() async {
    final doctor = await pickDoctor(context);
    if (doctor == null || !mounted) return;
    if (_participants.any((p) => p.doctorId == doctor.id)) {
      showMessage(
        context,
        'That doctor is already included. Change their role below.',
      );
      return;
    }
    setState(() {
      _participants.add(LogParticipant(doctor.id, ProcedureRole.performer));
      _dirty = true;
    });
  }

  Future<void> _editField(int index) async {
    var value = _fields[index].value;
    final next = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(_fields[index].label),
        content: TextFormField(
          initialValue: value,
          minLines: 2,
          maxLines: 6,
          maxLength: 20000,
          onChanged: (v) => value = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, value.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (next != null && mounted) {
      setState(() {
        final f = _fields[index];
        _fields[index] = LogField(f.id, f.label, next);
        _dirty = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = context.watch<LogbookRepository>().data;
    return PopScope(
      canPop: _allowPop || (!_dirty && !_busy),
      onPopInvokedWithResult: (popped, _) async {
        if (popped || _busy) return;
        if (await confirmAction(
              context,
              'Discard unsaved log?',
              'Your saved entries will be kept.',
              action: 'Discard',
            ) &&
            mounted) {
          setState(() => _allowPop = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.entry != null
                ? 'Edit log'
                : widget.prefill != null
                ? 'Add report to Logbook'
                : 'Quick Log',
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
        body: SafeArea(
          child: AbsorbPointer(
            absorbing: _busy,
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_busy) const LinearProgressIndicator(),
                  if (widget.entry?.currentSignature != null)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Changes create a new version needing a fresh signature. The previously signed version is kept.',
                      ),
                    ),
                  if (widget.prefill != null)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Review the copied information before saving. You can remove subject details. Changes here do not alter the report or Records.',
                      ),
                    ),
                  TextFormField(
                    controller: _procedure,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Procedure',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter the procedure'
                        : null,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event),
                    title: Text(readableDate(_date)),
                    subtitle: const Text('Procedure date'),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (date != null && mounted) {
                        setState(() {
                          _date = date;
                          _dirty = true;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Participation',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Text(
                    'Record your role. Add other people only when useful. The report author is not automatically the performer.',
                  ),
                  for (var i = 0; i < _participants.length; i++)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    book
                                            .doctor(_participants[i].doctorId)
                                            ?.name ??
                                        'Unknown doctor',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove participant',
                                  onPressed: () => setState(() {
                                    _participants.removeAt(i);
                                    _dirty = true;
                                  }),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                            DropdownButtonFormField<ProcedureRole>(
                              key: ValueKey(
                                '${_participants[i].doctorId}:${_participants[i].role.name}',
                              ),
                              initialValue: _participants[i].role,
                              decoration: const InputDecoration(
                                labelText: 'Role',
                              ),
                              items: [
                                for (final role in ProcedureRole.values)
                                  DropdownMenuItem(
                                    value: role,
                                    child: Text(role.label),
                                  ),
                              ],
                              onChanged: (role) {
                                if (role != null) {
                                  setState(() {
                                    final p = _participants[i];
                                    _participants[i] = LogParticipant(
                                      p.doctorId,
                                      role,
                                      supervised: p.supervised,
                                    );
                                    _dirty = true;
                                  });
                                }
                              },
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Worked under supervision'),
                              value: _participants[i].supervised,
                              onChanged: (value) => setState(() {
                                final p = _participants[i];
                                _participants[i] = LogParticipant(
                                  p.doctorId,
                                  p.role,
                                  supervised: value ?? false,
                                );
                                _dirty = true;
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _addPerson,
                    icon: const Icon(Icons.person_add_alt),
                    label: Text(
                      _participants.isEmpty
                          ? 'Choose doctor'
                          : 'Add participant (optional)',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _supervisorId.isEmpty
                          ? 'Supervisor (optional)'
                          : book.doctor(_supervisorId)?.name ?? 'Supervisor',
                    ),
                    subtitle: const Text(
                      'Naming a supervisor does not record their signature.',
                    ),
                    onTap: () async {
                      final d = await pickDoctor(
                        context,
                        title: 'Choose supervisor',
                      );
                      if (d != null && mounted) {
                        setState(() {
                          _supervisorId = d.id;
                          _dirty = true;
                        });
                      }
                    },
                    trailing: _supervisorId.isEmpty
                        ? const Icon(Icons.chevron_right)
                        : IconButton(
                            tooltip: 'Clear supervisor',
                            onPressed: () => setState(() {
                              _supervisorId = '';
                              _dirty = true;
                            }),
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _facility,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'Facility / department (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  TextFormField(
                    controller: _reference,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'Case reference (optional)',
                      helperText:
                          'Use the minimum patient information you need.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  TextFormField(
                    controller: _notes,
                    minLines: 2,
                    maxLines: 6,
                    maxLength: 20000,
                    decoration: const InputDecoration(
                      labelText: 'Outcome / notes (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_fields.isNotEmpty) ...[
                    Text(
                      'Copied fields',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (var i = 0; i < _fields.length; i++)
                      Card(
                        child: ListTile(
                          title: Text(_fields[i].label),
                          subtitle: Text(
                            _fields[i].value,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _editField(i),
                          trailing: IconButton(
                            tooltip: 'Remove copied field',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() {
                              _fields.removeAt(i);
                              _dirty = true;
                            }),
                          ),
                        ),
                      ),
                  ],
                  if (_reportAuthor.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('Report author/signatory: $_reportAuthor'),
                    ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.check),
                    label: const Text('Save log'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
