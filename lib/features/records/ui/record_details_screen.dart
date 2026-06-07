import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/record_models.dart';
import '../providers/records_provider.dart';

class RecordDetailsScreen extends StatefulWidget {
  final RecordEntry initialEntry;

  const RecordDetailsScreen({super.key, required this.initialEntry});

  @override
  State<RecordDetailsScreen> createState() => _RecordDetailsScreenState();
}

class _RecordDetailsScreenState extends State<RecordDetailsScreen> {
  late RecordEntry _entry;
  final _controllers = <String, TextEditingController>{};
  bool _saving = false;
  bool _procedureControllerListening = false;

  String get _currentProcedure =>
      _controllers[RecordFieldCatalog.procedure.key]?.text.trim() ??
      _entry.valueOf(RecordFieldCatalog.procedure.key);

  bool get _isExistingRecord => _entry.createdAtIso != _entry.updatedAtIso;

  @override
  void initState() {
    super.initState();
    _entry = widget.initialEntry;
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String key, String initial) {
    final displayValue = key == RecordFieldCatalog.reportId.key ? formatReportIdForDisplay(initial) : initial;
    final controller = _controllers.putIfAbsent(key, () => TextEditingController(text: displayValue));
    if (key == RecordFieldCatalog.procedure.key && !_procedureControllerListening) {
      controller.addListener(() {
        if (mounted) setState(() {});
      });
      _procedureControllerListening = true;
    }
    return controller;
  }

  void _setProcedureValue(String value) {
    final trimmed = value.trim();
    final current = _entry.valueOf(RecordFieldCatalog.procedure.key);
    if (current == trimmed && (_controllers[RecordFieldCatalog.procedure.key]?.text.trim() ?? current) == trimmed) {
      return;
    }
    final nextValues = Map<String, String>.from(_entry.values)
      ..[RecordFieldCatalog.procedure.key] = trimmed;
    _entry = _entry.copyWith(values: nextValues);
    final controller = _controllers[RecordFieldCatalog.procedure.key];
    if (controller != null && controller.text != trimmed) {
      controller.text = trimmed;
      controller.selection = TextSelection.collapsed(offset: controller.text.length);
    }
  }

  bool _fieldVisibleForCurrentProcedure(RecordFieldDef field) {
    return field.appliesToProcedure(_currentProcedure);
  }

  static final _protectedRecordKeys = <String>{
    RecordFieldCatalog.reportId.key,
    RecordFieldCatalog.reportDate.key,
  };

  void _disposeControllerLater(String key) {
    final controller = _controllers.remove(key);
    if (controller == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
  }

  bool _isSubjectRecordKey(String key) {
    return key == RecordFieldCatalog.subjectName.key ||
        key == RecordFieldCatalog.patientReference.key ||
        key == RecordFieldCatalog.age.key ||
        key == RecordFieldCatalog.gender.key ||
        key.startsWith('subject_');
  }

  int _fieldSortRank(RecordFieldDef field) {
    final key = field.key;
    if (key == RecordFieldCatalog.reportId.key) return 0;
    if (key == RecordFieldCatalog.reportDate.key) return 1;
    if (_isSubjectRecordKey(key)) return 2;
    if (key == RecordFieldCatalog.procedure.key) return 3;
    if (key == RecordFieldCatalog.facility.key) return 4;
    if (!field.isSystem && field.isGlobal) return 5;
    if (!field.isSystem && !field.isGlobal) return 6;
    if (key == RecordFieldCatalog.doctor.key) return 8;
    return 7;
  }

  List<RecordFieldDef> _fieldsForEntry(List<RecordFieldDef> baseFields) {
    final byKey = <String, RecordFieldDef>{};

    for (final field in baseFields) {
      final isProtected = _protectedRecordKeys.contains(field.key);
      final hasValue = _entry.values.containsKey(field.key);
      final isUserAddedRecordField = !field.isSystem;
      // Keep Record Details focused. Show protected system fields always.
      // Show user-added fields because this is the place to complete optional
      // all-report-type / Procedure-Report-Type fields. Hide unused factory
      // fields so the main details screen does not feel like a blank form.
      if (!isProtected && !hasValue && !isUserAddedRecordField) continue;

      final labelOverride = _entry.fieldLabels[field.key]?.trim();
      byKey[field.key] = RecordFieldDef(
        key: field.key,
        label: labelOverride?.isNotEmpty == true ? labelOverride! : field.label,
        hint: field.hint,
        builtInSuggestions: field.builtInSuggestions,
        isSystem: field.isSystem,
        procedureScope: field.procedureScope,
      );
    }

    for (final item in _entry.values.entries) {
      final key = item.key.trim();
      if (key.isEmpty || byKey.containsKey(key)) continue;
      final label = (_entry.fieldLabels[key]?.trim().isNotEmpty == true)
          ? _entry.fieldLabels[key]!.trim()
          : key;
      byKey[key] = RecordFieldDef(
        key: key,
        label: label,
        hint: 'Record value',
        isSystem: _isSubjectRecordKey(key),
      );
    }

    final out = byKey.values.toList(growable: false);
    out.sort((a, b) {
      final rank = _fieldSortRank(a).compareTo(_fieldSortRank(b));
      if (rank != 0) return rank;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return out;
  }

  void _removeFieldFromThisRecord(RecordFieldDef field) {
    if (_protectedRecordKeys.contains(field.key)) return;
    final values = Map<String, String>.from(_entry.values)..remove(field.key);
    final labels = Map<String, String>.from(_entry.fieldLabels)..remove(field.key);
    _disposeControllerLater(field.key);
    setState(() => _entry = _entry.copyWith(values: values, fieldLabels: labels));
  }

  Future<void> _save() async {
    if (_saving) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_isExistingRecord ? 'Update record details?' : 'Save to Records?'),
        content: const Text(
          'This saves searchable record details for the PDF Report. Editing these details will not change the saved PDF.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_isExistingRecord ? 'Update Record' : 'Save to Records')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    final values = Map<String, String>.from(_entry.values);
    for (final entry in _controllers.entries) {
      if (entry.key == RecordFieldCatalog.reportId.key) {
        values[entry.key] = _entry.valueOf(entry.key);
      } else {
        values[entry.key] = entry.value.text.trim();
      }
    }
    try {
      final provider = context.read<RecordsProvider>();
      await provider.saveRecord(
        _entry.copyWith(
          updatedAtIso: DateTime.now().toIso8601String(),
          values: values,
          fieldLabels: _entry.fieldLabels,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isExistingRecord ? 'Record details updated.' : 'Saved to Records.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save record details: $e')),
      );
    }
  }


  Future<void> _deleteCustomFieldDefinition(RecordFieldDef field) async {
    if (field.isSystem) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete custom field?'),
        content: Text(
          field.isGlobal
              ? 'Delete ${field.label} from general record fields? This removes it from saved records too.'
              : 'Delete ${field.label} from ${field.procedureScope} record fields? This removes it from saved records too.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _disposeControllerLater(field.key);
    final values = Map<String, String>.from(_entry.values)..remove(field.key);
    final labels = Map<String, String>.from(_entry.fieldLabels)..remove(field.key);
    setState(() => _entry = _entry.copyWith(values: values, fieldLabels: labels));
    await context.read<RecordsProvider>().deleteCustomField(field.key);
  }

  Future<void> _addField() async {
    final labelController = TextEditingController();
    final hintController = TextEditingController();
    final procedureScopeController = TextEditingController(text: _currentProcedure.trim());
    var saveAsGlobal = _currentProcedure.trim().isEmpty;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Add new record field'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              TextField(
                controller: labelController,
                decoration: const InputDecoration(labelText: 'Field label'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: hintController,
                decoration: const InputDecoration(labelText: 'Field hint (optional)'),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Apply field to',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 8),
              RadioListTile<bool>(
                value: true,
                groupValue: saveAsGlobal,
                onChanged: (v) => setLocalState(() => saveAsGlobal = v ?? true),
                title: const Text('All report types (general field)'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<bool>(
                value: false,
                groupValue: saveAsGlobal,
                onChanged: (v) => setLocalState(() => saveAsGlobal = v ?? true),
                title: Text(
                  procedureScopeController.text.trim().isEmpty
                      ? 'Only for this report type'
                      : 'Only for ${procedureScopeController.text.trim()}',
                ),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              if (!saveAsGlobal) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: procedureScopeController,
                  onChanged: (_) => setLocalState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Procedure / Report Type',
                    hintText: 'e.g. Colonoscopy or Site inspection',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: RecordFieldCatalog.procedure.builtInSuggestions.map((suggestion) {
                    final selected = procedureScopeController.text.trim().toLowerCase() == suggestion.toLowerCase();
                    return ChoiceChip(
                      label: Text(suggestion),
                      selected: selected,
                      onSelected: (_) => setLocalState(() => procedureScopeController.text = suggestion),
                    );
                  }).toList(growable: false),
                ),
              ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (created == true && mounted) {
      final label = labelController.text.trim();
      final hint = hintController.text.trim();
      if (label.isNotEmpty) {
        final procedureScope = saveAsGlobal ? '' : procedureScopeController.text.trim();
        if (!saveAsGlobal && procedureScope.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Choose or type a report type for this field.')),
            );
          }
        } else {
          if (!saveAsGlobal) {
            setState(() {
              _setProcedureValue(procedureScope);
            });
          }
          await context.read<RecordsProvider>().addCustomField(label: label, hint: hint, procedureScope: procedureScope);
        }
      }
    }
    labelController.dispose();
    hintController.dispose();
    procedureScopeController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecordsProvider>();
    final allFields = provider.allFields;
    final fields = _fieldsForEntry(allFields).where(_fieldVisibleForCurrentProcedure).toList(growable: false);
    final procedureSpecificCount = allFields.where((f) => !f.isGlobal && f.appliesToProcedure(_currentProcedure)).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Details'),
        actions: [
          IconButton(
            tooltip: 'Add field',
            onPressed: _addField,
            icon: const Icon(Icons.add_box_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.45),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.library_add_check_outlined),
                      const SizedBox(width: 10),
                      Text(_isExistingRecord ? 'Update Record Details' : 'Save to Records', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Records help you organize and find PDF Reports in list or table form. Editing record details will not change the saved PDF.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _currentProcedure.trim().isEmpty
                        ? 'You can add extra record fields for your unit before saving.'
                        : 'You can add extra record fields either for all report types or specifically for $_currentProcedure.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_currentProcedure.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ScopeChip(label: 'General fields', count: fields.where((f) => f.isGlobal).length),
                        _ScopeChip(label: '$_currentProcedure fields', count: procedureSpecificCount),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final field in fields) ...[
            _RecordValueField(
              key: ValueKey('record-field-${field.key}'),
              field: field,
              currentProcedure: _currentProcedure,
              controller: _controllerFor(field.key, _entry.valueOf(field.key)),
              onDelete: _protectedRecordKeys.contains(field.key)
                  ? null
                  : (!field.isSystem && provider.allFields.any((f) => f.key == field.key)
                      ? () => _deleteCustomFieldDefinition(field)
                      : () => _removeFieldFromThisRecord(field)),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _save,
            icon: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : (_isExistingRecord ? 'Update Record' : 'Save to Records')),
          ),
        ],
      ),
    );
  }
}

class _RecordValueField extends StatefulWidget {
  final RecordFieldDef field;
  final String currentProcedure;
  final TextEditingController controller;
  final VoidCallback? onDelete;

  const _RecordValueField({
    super.key,
    required this.field,
    required this.currentProcedure,
    required this.controller,
    this.onDelete,
  });

  @override
  State<_RecordValueField> createState() => _RecordValueFieldState();
}

class _RecordValueFieldState extends State<_RecordValueField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _allowsMultipleSuggestions {
    final key = widget.field.key.toLowerCase();
    final label = widget.field.label.toLowerCase();
    return key.contains('indication') ||
        key.contains('symptom') ||
        key.contains('finding') ||
        key.contains('diagnosis') ||
        label.contains('indication') ||
        label.contains('symptom') ||
        label.contains('finding') ||
        label.contains('diagnosis');
  }

  void _applySuggestion(String option) {
    final trimmed = option.trim();
    if (trimmed.isEmpty) return;
    if (!_allowsMultipleSuggestions) {
      _controller.text = trimmed;
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      return;
    }
    final existing = _controller.text.trim();
    if (existing.isEmpty) {
      _controller.text = trimmed;
    } else {
      final parts = existing
          .split(RegExp(r'[,;\n]+'))
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
      if (parts.contains(trimmed.toLowerCase())) return;
      _controller.text = '$existing, $trimmed';
    }
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(widget.field.label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
            if (!widget.field.isSystem) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  widget.field.isGlobal
                      ? 'Custom (General)'
                      : 'Custom (${widget.field.procedureScope.trim().isEmpty ? 'This report type' : widget.field.procedureScope.trim()})',
                  style: theme.textTheme.labelSmall,
                ),
              ),
              IconButton(
                tooltip: 'Delete field',
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: widget.field.hint,
            filled: true,
            fillColor: theme.colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: _controller.clear,
                  ),
          ),
        ),
        const SizedBox(height: 10),
        FutureBuilder<List<String>>(
          future: context.read<RecordsProvider>().suggestions(
            widget.field.key,
            _allowsMultipleSuggestions ? '' : _controller.text,
            procedure: widget.field.key == RecordFieldCatalog.procedure.key
                ? ''
                : widget.currentProcedure,
          ),
          builder: (context, snapshot) {
            final options = snapshot.data ?? widget.field.builtInSuggestions;
            if (options.isEmpty) return const SizedBox.shrink();
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.25),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.primary.withOpacity(0.18)),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: options.take(12).map((option) {
                  return ActionChip(
                    label: Text(option),
                    onPressed: () => _applySuggestion(option),
                  );
                }).toList(growable: false),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ScopeChip extends StatelessWidget {
  final String label;
  final int count;

  const _ScopeChip({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$label: $count'),
    );
  }
}
