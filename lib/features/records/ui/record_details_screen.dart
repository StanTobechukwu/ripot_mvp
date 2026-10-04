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
  bool _editReportValues = false;
  final _listeningControllerKeys = <String>{};

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
    final displayValue = key == RecordFieldCatalog.reportId.key
        ? formatReportIdForDisplay(initial)
        : initial;
    final controller = _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: displayValue),
    );
    if (_listeningControllerKeys.add(key)) {
      controller.addListener(() {
        if (mounted) setState(() {});
      });
    }
    return controller;
  }

  bool _fieldVisibleForCurrentProcedure(RecordFieldDef field) {
    return field.appliesToProcedure(_currentProcedure);
  }

  bool _conditionAllowsField(RecordFieldDef field) {
    final parentKey = field.conditionalOnFieldKey.trim();
    final expected = field.conditionalEquals.trim();
    if (parentKey.isEmpty || expected.isEmpty) return true;
    // Do not hide already-entered data.
    if (_entry.valueOf(field.key).isNotEmpty ||
        (_controllers[field.key]?.text.trim().isNotEmpty == true)) {
      return true;
    }
    final current = (_controllers[parentKey]?.text.trim().isNotEmpty == true)
        ? _controllers[parentKey]!.text.trim()
        : _entry.valueOf(parentKey);
    return current.toLowerCase() == expected.toLowerCase();
  }

  static final _protectedRecordKeys = <String>{
    RecordFieldCatalog.reportId.key,
    RecordFieldCatalog.reportDate.key,
  };

  bool _isSubjectRecordKey(String key) {
    return key == RecordFieldCatalog.subjectName.key ||
        key == RecordFieldCatalog.patientReference.key ||
        key == RecordFieldCatalog.age.key ||
        key == RecordFieldCatalog.gender.key ||
        key.startsWith('subject_');
  }

  bool _isTemplateDerivedRecordField(String key) {
    final source = _entry.fieldSources[key]?.trim().toLowerCase() ?? '';
    if (source == 'template') return true;
    // Backward compatibility for older records created before fieldSources existed:
    // fields copied from a report template normally arrive with a label override
    // but no custom field definition. Treat those as template-derived so they are
    // not mislabeled as general fields.
    return _entry.fieldLabels.containsKey(key) && !_isSubjectRecordKey(key);
  }

  int _fieldSortRank(RecordFieldDef field) {
    final key = field.key;
    if (key == RecordFieldCatalog.reportId.key) return 0;
    if (key == RecordFieldCatalog.reportDate.key) return 1;
    if (_isSubjectRecordKey(key)) return 2;
    if (key == RecordFieldCatalog.procedure.key) return 3;
    if (key == RecordFieldCatalog.facility.key) return 4;
    if (!field.isSystem && field.isGlobal) return 5;
    if (!field.isSystem && !field.isGlobal && !field.isRegistryField) return 6;
    if (field.isRegistryField) return 7;
    if (key == RecordFieldCatalog.doctor.key) return 9;
    return 8;
  }

  List<RecordFieldDef> _fieldsForEntry(List<RecordFieldDef> baseFields) {
    final byKey = <String, RecordFieldDef>{};

    for (final field in baseFields) {
      final snapshot = _entry.fieldDefinitions[field.key];
      final isProtected = _protectedRecordKeys.contains(field.key);
      final hasValue = _entry.values.containsKey(field.key);
      // New Registry measurements are entered as dated patient updates.
      // Keep any old flattened values visible, but don't duplicate that form here.
      if (field.isRegistryField && !hasValue) continue;
      final isUserAddedRecordField = !field.isSystem;
      final isRegistryFieldForThisRecord =
          field.isRegistryField &&
          field.appliesToRegistries(_entry.registryIds);
      final isAlwaysAvailableSystemField =
          field.key == RecordFieldCatalog.facility.key;
      // Keep Record Details focused. Show protected system fields always.
      // Facility is also shown early because it is important for filtering/export.
      // Show user-added fields because this is the place to complete optional
      // all-report-type / Procedure-Report-Type fields. Hide other unused factory
      // fields so the main details screen does not feel like a blank form.
      if (field.isRegistryField &&
          !field.appliesToRegistries(_entry.registryIds))
        continue;
      if (!isProtected &&
          !hasValue &&
          !isUserAddedRecordField &&
          !isRegistryFieldForThisRecord &&
          !isAlwaysAvailableSystemField)
        continue;

      final labelOverride = _entry.fieldLabels[field.key]?.trim();
      final templateDerived = _isTemplateDerivedRecordField(field.key);
      byKey[field.key] = RecordFieldDef(
        key: field.key,
        label: labelOverride?.isNotEmpty == true ? labelOverride! : field.label,
        hint: field.hint,
        builtInSuggestions: field.builtInSuggestions,
        isSystem: field.isSystem || templateDerived,
        procedureScope: templateDerived ? '' : field.procedureScope,
        registryId: templateDerived ? '' : field.registryId,
        conditionalOnFieldKey: field.conditionalOnFieldKey,
        conditionalEquals: field.conditionalEquals,
        inputType: snapshot?.inputType ?? field.inputType,
        options: snapshot?.options ?? field.options,
        unit: snapshot?.unit ?? field.unit,
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
        isSystem:
            _isSubjectRecordKey(key) || _isTemplateDerivedRecordField(key),
        inputType:
            _entry.fieldDefinitions[key]?.inputType ?? RecordInputType.freeText,
        options: _entry.fieldDefinitions[key]?.options ?? const <String>[],
        unit: _entry.fieldDefinitions[key]?.unit ?? '',
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

  bool _isCopiedFromReport(RecordFieldDef field) {
    return _entry.fieldSources[field.key] == 'template' ||
        _isSubjectRecordKey(field.key) ||
        field.key == RecordFieldCatalog.reportId.key ||
        field.key == RecordFieldCatalog.reportDate.key;
  }

  Future<void> _addProcedureField() async {
    final procedure = _currentProcedure.trim();
    if (procedure.isEmpty) return;

    final labelController = TextEditingController();
    final optionsController = TextEditingController();
    final unitController = TextEditingController();
    var inputType = RecordInputType.freeText;

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocalState) => AlertDialog(
          title: Text('Add field for $procedure'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Prefer structured fields (Yes/No, choice or numeric) when possible. '
                  'Use narrative text only when the information cannot be represented reliably as structured data.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: labelController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Field name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<RecordInputType>(
                  initialValue: inputType,
                  decoration: const InputDecoration(
                    labelText: 'Input type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: RecordInputType.freeText,
                      child: Text('Narrative text'),
                    ),
                    DropdownMenuItem(
                      value: RecordInputType.yesNo,
                      child: Text('Yes / No'),
                    ),
                    DropdownMenuItem(
                      value: RecordInputType.singleSelect,
                      child: Text('Single select'),
                    ),
                    DropdownMenuItem(
                      value: RecordInputType.multiSelect,
                      child: Text('Multi-select'),
                    ),
                    DropdownMenuItem(
                      value: RecordInputType.numeric,
                      child: Text('Numeric'),
                    ),
                  ],
                  onChanged: (value) => setLocalState(
                    () => inputType = value ?? RecordInputType.freeText,
                  ),
                ),
                if (inputType == RecordInputType.singleSelect ||
                    inputType == RecordInputType.multiSelect) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: optionsController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Choices',
                      hintText: 'One per line',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (inputType == RecordInputType.numeric) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: unitController,
                    decoration: const InputDecoration(
                      labelText: 'Unit (optional)',
                      hintText: 'e.g. mm, minutes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Add field'),
            ),
          ],
        ),
      ),
    );

    if (created == true && mounted && labelController.text.trim().isNotEmpty) {
      final options = optionsController.text
          .split(RegExp(r'[,;\n\r]+'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      await context.read<RecordsProvider>().addCustomField(
        label: labelController.text.trim(),
        procedureScope: procedure,
        inputType: inputType,
        options: inputType == RecordInputType.yesNo
            ? const <String>['Yes', 'No']
            : options,
        unit: unitController.text.trim(),
      );
    }

    labelController.dispose();
    optionsController.dispose();
    unitController.dispose();
  }

  Future<void> _openRecordSettings() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Record settings'),
              subtitle: Text(
                'These options change how information is collected.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_box_outlined),
              title: const Text('Add an extra Records field'),
              subtitle: Text(
                _currentProcedure.trim().isEmpty
                    ? 'Set the procedure first.'
                    : 'Available for $_currentProcedure records.',
              ),
              enabled: _currentProcedure.trim().isNotEmpty,
              onTap: _currentProcedure.trim().isEmpty
                  ? null
                  : () => Navigator.pop(sheetContext, 'field'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'field') await _addProcedureField();
  }

  Future<void> _save() async {
    if (_saving) return;
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
      final definitions = Map<String, RecordFieldDef>.from(
        _entry.fieldDefinitions,
      );
      for (final field in provider.allFields) {
        if (field.appliesToProcedure(_currentProcedure) &&
            field.appliesToRegistries(_entry.registryIds)) {
          definitions.putIfAbsent(field.key, () => field);
        }
      }
      await provider.saveRecord(
        _entry.copyWith(
          updatedAtIso: DateTime.now().toIso8601String(),
          values: values,
          originalReportValues: _entry.originalReportValues.isEmpty
              ? Map<String, String>.from(_entry.values)
              : _entry.originalReportValues,
          fieldLabels: _entry.fieldLabels,
          fieldDefinitions: definitions,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isExistingRecord ? 'Record details updated.' : 'Saved to Records.',
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecordsProvider>();
    final allFields = provider.allFields;
    final fields = _fieldsForEntry(allFields)
        .where((field) => field.appliesToRegistries(_entry.registryIds))
        .where(_fieldVisibleForCurrentProcedure)
        .where(_conditionAllowsField)
        .toList(growable: false);
    final copiedFields = fields
        .where(_isCopiedFromReport)
        .toList(growable: false);
    final additionalFields = fields
        .where((field) => !_isCopiedFromReport(field))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isExistingRecord ? 'Record details' : 'Save to Records'),
        actions: [
          IconButton(
            tooltip: 'Record settings',
            onPressed: _openRecordSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(
            _saving
                ? 'Saving...'
                : (_isExistingRecord ? 'Update record' : 'Save to Records'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Card(
            elevation: 0,
            color: Theme.of(
              context,
            ).colorScheme.secondaryContainer.withOpacity(0.45),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.library_add_check_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          copiedFields.isEmpty
                              ? 'Complete this record'
                              : 'Copied from the generated report',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Review the copied information below. Record changes do not alter the saved PDF.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (copiedFields.isNotEmpty) ...[
            Text(
              'Report information',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            for (final field in copiedFields) ...[
              _RecordValueField(
                key: ValueKey('record-field-${field.key}'),
                field: field,
                currentProcedure: _currentProcedure,
                controller: _controllerFor(
                  field.key,
                  _entry.valueOf(field.key),
                ),
                readOnly:
                    !_editReportValues ||
                    _protectedRecordKeys.contains(field.key),
              ),
              if (_entry.originalReportValues.containsKey(field.key) &&
                  _controllerFor(field.key, _entry.valueOf(field.key)).text !=
                      _entry.originalReportValues[field.key])
                Text(
                  'Original: ${_entry.originalReportValues[field.key]}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
            ],
            if (!_editReportValues)
              TextButton.icon(
                onPressed: () => setState(() => _editReportValues = true),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit record information'),
              ),
          ],
          if (additionalFields.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Additional record information',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              _currentProcedure.trim().isEmpty
                  ? 'Information used for organizing Records.'
                  : 'Extra information for $_currentProcedure records.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            for (final field in additionalFields) ...[
              _RecordValueField(
                key: ValueKey('record-field-${field.key}'),
                field: field,
                currentProcedure: _currentProcedure,
                controller: _controllerFor(
                  field.key,
                  _entry.valueOf(field.key),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }
}

class _RecordValueField extends StatefulWidget {
  final RecordFieldDef field;
  final String currentProcedure;
  final TextEditingController controller;
  final bool readOnly;

  const _RecordValueField({
    super.key,
    required this.field,
    required this.currentProcedure,
    required this.controller,
    this.readOnly = false,
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
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
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
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  static const int _maxVisibleSuggestions = 8;

  List<String> get _configuredOptions {
    final configured = widget.field.options.isNotEmpty
        ? widget.field.options
        : widget.field.builtInSuggestions;
    if (widget.field.inputType == RecordInputType.yesNo && configured.isEmpty) {
      return const <String>['Yes', 'No'];
    }
    return configured;
  }

  Widget _editableInput(ThemeData theme) {
    final decoration = InputDecoration(
      hintText: widget.field.hint,
      suffixText: widget.field.unit.trim().isEmpty ? null : widget.field.unit,
      filled: true,
      fillColor: theme.colorScheme.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );

    if (widget.field.inputType == RecordInputType.yesNo ||
        widget.field.inputType == RecordInputType.singleSelect) {
      final options = _configuredOptions;
      final current = _controller.text.trim();
      return DropdownButtonFormField<String>(
        initialValue: options.contains(current) ? current : null,
        decoration: decoration,
        isExpanded: true,
        items: options
            .map(
              (option) => DropdownMenuItem<String>(
                value: option,
                child: Text(option, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(growable: false),
        onChanged: (value) => _controller.text = value ?? '',
      );
    }

    if (widget.field.inputType == RecordInputType.multiSelect) {
      final selected = _controller.text
          .split(RegExp(r'[,;\n]+'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
      return InputDecorator(
        decoration: decoration,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _configuredOptions
              .map((option) {
                final isSelected = selected.contains(option);
                return FilterChip(
                  label: Text(option),
                  selected: isSelected,
                  onSelected: (value) {
                    final next = <String>{...selected};
                    if (value) {
                      next.add(option);
                    } else {
                      next.remove(option);
                    }
                    _controller.text = next.join('; ');
                  },
                );
              })
              .toList(growable: false),
        ),
      );
    }

    return TextField(
      controller: _controller,
      keyboardType: widget.field.inputType == RecordInputType.numeric
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      minLines: widget.field.inputType == RecordInputType.freeText ? 1 : null,
      maxLines: widget.field.inputType == RecordInputType.freeText ? 3 : 1,
      decoration: decoration.copyWith(
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.clear),
                onPressed: _controller.clear,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.field.label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        if (widget.readOnly)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              _controller.text.trim().isEmpty
                  ? 'Not recorded'
                  : '${_controller.text.trim()}${widget.field.unit.trim().isEmpty ? '' : ' ${widget.field.unit.trim()}'}',
              style: theme.textTheme.bodyLarge,
            ),
          )
        else
          _editableInput(theme),
        if (!widget.readOnly &&
            widget.field.inputType == RecordInputType.freeText) ...[
          const SizedBox(height: 10),
          FutureBuilder<List<String>>(
            future: widget.field.isRegistryField
                ? Future.value(widget.field.builtInSuggestions)
                : context.read<RecordsProvider>().suggestions(
                    widget.field.key,
                    _allowsMultipleSuggestions ? '' : _controller.text,
                    procedure:
                        widget.field.key == RecordFieldCatalog.procedure.key
                        ? ''
                        : widget.currentProcedure,
                  ),
            builder: (context, snapshot) {
              final options = snapshot.data ?? widget.field.builtInSuggestions;
              if (options.isEmpty) return const SizedBox.shrink();
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: options
                    .take(_maxVisibleSuggestions)
                    .map((option) {
                      return ActionChip(
                        label: Text(option),
                        onPressed: () => _applySuggestion(option),
                      );
                    })
                    .toList(growable: false),
              );
            },
          ),
        ],
      ],
    );
  }
}
