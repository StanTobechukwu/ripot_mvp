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
  final _listeningControllerKeys = <String>{};

  String get _currentProcedure =>
      _controllers[RecordFieldCatalog.procedure.key]?.text.trim() ??
      _entry.valueOf(RecordFieldCatalog.procedure.key);

  bool get _isExistingRecord => _entry.createdAtIso != _entry.updatedAtIso;

  String _simpleFieldKey(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_\$'), '');
  }

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
    if (_listeningControllerKeys.add(key)) {
      controller.addListener(() {
        if (mounted) setState(() {});
      });
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

  bool _conditionAllowsField(RecordFieldDef field) {
    final parentKey = field.conditionalOnFieldKey.trim();
    final expected = field.conditionalEquals.trim();
    if (parentKey.isEmpty || expected.isEmpty) return true;
    // Do not hide already-entered data.
    if (_entry.valueOf(field.key).isNotEmpty || (_controllers[field.key]?.text.trim().isNotEmpty == true)) {
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

  void _disposeControllerLater(String key) {
    // Do not dispose individual controllers while Record Details is still mounted.
    // Fields can appear/disappear when registry/conditional fields change, and
    // Flutter may still have a TextField from the previous frame attached to the
    // controller. Disposing here caused intermittent:
    // "A TextEditingController was used after being disposed."
    // Keep controllers alive for the screen lifetime and dispose all in dispose().
    FocusManager.instance.primaryFocus?.unfocus();
  }

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
      final isProtected = _protectedRecordKeys.contains(field.key);
      final hasValue = _entry.values.containsKey(field.key);
      final isUserAddedRecordField = !field.isSystem;
      final isRegistryFieldForThisRecord = field.isRegistryField && field.appliesToRegistries(_entry.registryIds);
      final isAlwaysAvailableSystemField = field.key == RecordFieldCatalog.facility.key;
      // Keep Record Details focused. Show protected system fields always.
      // Facility is also shown early because it is important for filtering/export.
      // Show user-added fields because this is the place to complete optional
      // all-report-type / Procedure-Report-Type fields. Hide other unused factory
      // fields so the main details screen does not feel like a blank form.
      if (field.isRegistryField && !field.appliesToRegistries(_entry.registryIds)) continue;
      if (!isProtected && !hasValue && !isUserAddedRecordField && !isRegistryFieldForThisRecord && !isAlwaysAvailableSystemField) continue;

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
        isSystem: _isSubjectRecordKey(key) || _isTemplateDerivedRecordField(key),
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
    final sources = Map<String, String>.from(_entry.fieldSources)..remove(field.key);
    _disposeControllerLater(field.key);
    setState(() => _entry = _entry.copyWith(values: values, fieldLabels: labels, fieldSources: sources));
  }


  Future<void> _confirmHideFieldFromThisRecord(RecordFieldDef field) async {
    if (_protectedRecordKeys.contains(field.key)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hide field from this record?'),
        content: Text(
          'This will remove "${field.label}" from this record screen. Existing saved records are not deleted. If this field comes from a template, edit the Template Editor to change future report/record behavior.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Hide field')),
        ],
      ),
    );
    if (confirmed == true && mounted) _removeFieldFromThisRecord(field);
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
    if (field.isSystem || field.isRegistryField) return;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove custom field?'),
        content: Text(
          field.isGlobal
              ? 'Remove ${field.label} from general record fields? Existing saved values can be preserved.'
              : 'Remove ${field.label} from ${field.procedureScope} record fields? Existing saved values can be preserved.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, 'cancel'), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, 'hide'), child: const Text('Hide going forward')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, 'delete'), child: const Text('Delete values')),
        ],
      ),
    );
    if (action == null || action == 'cancel' || !mounted) return;

    if (action == 'delete') {
      _disposeControllerLater(field.key);
      final values = Map<String, String>.from(_entry.values)..remove(field.key);
      final labels = Map<String, String>.from(_entry.fieldLabels)..remove(field.key);
      final sources = Map<String, String>.from(_entry.fieldSources)..remove(field.key);
      setState(() => _entry = _entry.copyWith(values: values, fieldLabels: labels, fieldSources: sources));
    }
    await context.read<RecordsProvider>().deleteCustomField(
          field.key,
          deleteSavedValues: action == 'delete',
        );
  }

  Future<void> _editCustomFieldDefinition(RecordFieldDef field) async {
    if (field.isSystem || field.isRegistryField) return;
    final labelController = TextEditingController(text: field.label);
    final procedureScopeController = TextEditingController(text: field.procedureScope);
    final suggestionsController = TextEditingController(text: field.builtInSuggestions.join('\n'));
    var isProcedureField = !field.isGlobal;

    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocalState) => AlertDialog(
          title: const Text('Manage field'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Field name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Procedure-specific field'),
                  subtitle: const Text('Turn off to make it a general record field.'),
                  value: isProcedureField,
                  onChanged: (value) => setLocalState(() => isProcedureField = value),
                ),
                if (isProcedureField) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: procedureScopeController,
                    onChanged: (_) => setLocalState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Procedure / Report Type',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: suggestionsController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Manual suggestions (optional)',
                    hintText: 'One per line or comma-separated',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (updated == true && mounted && labelController.text.trim().isNotEmpty) {
      final suggestions = suggestionsController.text
          .split(RegExp(r'[,;\n\r]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      final scope = isProcedureField ? procedureScopeController.text.trim() : '';
      await context.read<RecordsProvider>().updateCustomField(
            fieldKey: field.key,
            label: labelController.text.trim(),
            procedureScope: scope,
            suggestions: suggestions,
          );
      final refreshed = await context.read<RecordsProvider>().repo.loadByRecordId(_entry.recordEntryId);
      if (!mounted) return;
      setState(() {
        if (refreshed != null) {
          _entry = refreshed;
        } else {
          final labels = Map<String, String>.from(_entry.fieldLabels)..[field.key] = labelController.text.trim();
          _entry = _entry.copyWith(fieldLabels: labels);
        }
      });
    }
  }


  Future<void> _addField() async {
    final provider = context.read<RecordsProvider>();
    final activeRegistries = provider.registries
        .where((registry) => _entry.registryIds.contains(registry.registryId))
        .toList(growable: false);

    final fieldScope = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Add field'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'general'),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.public_outlined),
              title: Text('General field'),
              subtitle: Text('Available across report types.'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'procedure'),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.category_outlined),
              title: const Text('Procedure-specific field'),
              subtitle: Text(
                _currentProcedure.trim().isEmpty
                    ? 'Choose a report type for this field.'
                    : 'Available for $_currentProcedure records.',
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: activeRegistries.isEmpty ? null : () => Navigator.pop(dialogContext, 'registry'),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              enabled: activeRegistries.isNotEmpty,
              leading: const Icon(Icons.science_outlined),
              title: const Text('Registry / Study field'),
              subtitle: Text(
                activeRegistries.isEmpty
                    ? 'Add this record to a registry first.'
                    : 'Add a field to an active registry/study.',
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (!mounted || fieldScope == null) return;

    if (fieldScope == 'registry') {
      if (activeRegistries.length == 1) {
        await _addRegistryField(activeRegistries.first);
        return;
      }
      final selected = await showDialog<RecordRegistry>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Choose registry / study'),
          children: [
            ...activeRegistries.map(
              (registry) => SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, registry),
                child: Text(registry.title),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (selected != null && mounted) await _addRegistryField(selected);
      return;
    }

    final labelController = TextEditingController();
    final procedureScopeController = TextEditingController(text: _currentProcedure.trim());
    final isProcedureField = fieldScope == 'procedure';

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(isProcedureField ? 'Add procedure field' : 'Add general field'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Field label',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                if (isProcedureField) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: procedureScopeController,
                    onChanged: (_) => setLocalState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Procedure / Report Type',
                      hintText: 'e.g. Colonoscopy or Upper GI Endoscopy',
                      border: OutlineInputBorder(),
                      isDense: true,
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
      if (label.isNotEmpty) {
        final procedureScope = isProcedureField ? procedureScopeController.text.trim() : '';
        if (isProcedureField && procedureScope.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Choose or type a report type for this field.')),
          );
        } else {
          final duplicateKey = _simpleFieldKey(label);
          final duplicate = provider.allFields.any((field) =>
              field.label.trim().toLowerCase() == label.toLowerCase() ||
              field.key.trim().toLowerCase() == duplicateKey);
          if (duplicate) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$label already exists as a record field. Use the existing field instead of creating a duplicate.')),
            );
          } else {
            if (isProcedureField) {
              setState(() => _setProcedureValue(procedureScope));
            }
            await context.read<RecordsProvider>().addCustomField(
                  label: label,
                  procedureScope: procedureScope,
                );
          }
        }
      }
    }

    labelController.dispose();
    procedureScopeController.dispose();
  }


  Future<void> _createRegistry() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create registry / study'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Registry / Study title',
                  hintText: 'e.g. H. pylori Dyspepsia Study',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Description (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Create')),
        ],
      ),
    );
    if (created == true && mounted && titleController.text.trim().isNotEmpty) {
      final provider = context.read<RecordsProvider>();
      final registry = await provider.createRegistry(
        title: titleController.text.trim(),
        description: descriptionController.text.trim(),
      );
      final updated = await provider.assignRecordToRegistry(
        recordEntryId: _entry.recordEntryId,
        registryId: registry.registryId,
      );
      if (!mounted) return;
      setState(() {
        _entry = updated ?? _entry.copyWith(
          registryIds: {..._entry.registryIds, registry.registryId}.toList(growable: false),
        );
      });
    }
    titleController.dispose();
    descriptionController.dispose();
  }

  Future<void> _assignRegistry() async {
    final provider = context.read<RecordsProvider>();
    final available = provider.registries.where((r) => !_entry.registryIds.contains(r.registryId)).toList(growable: false);
    if (available.isEmpty) {
      await _createRegistry();
      return;
    }
    final selected = await showDialog<RecordRegistry>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Add record to registry'),
        children: [
          ...available.map(
            (registry) => SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, registry),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(registry.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (registry.description.trim().isNotEmpty) Text(registry.description),
                ],
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final updated = await provider.assignRecordToRegistry(
      recordEntryId: _entry.recordEntryId,
      registryId: selected.registryId,
    );
    if (!mounted) return;
    setState(() {
      _entry = updated ?? _entry.copyWith(
        registryIds: {..._entry.registryIds, selected.registryId}.toList(growable: false),
      );
    });
  }

  Future<void> _addRegistryField(RecordRegistry registry) async {
    final labelController = TextEditingController();
    final suggestionsController = TextEditingController();
    final conditionValueController = TextEditingController();
    var useCondition = false;
    String conditionFieldKey = '';

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocalState) {
          final provider = context.read<RecordsProvider>();
          final possibleParents = provider.allFields
              .where((field) => field.appliesToRegistries(_entry.registryIds))
              .where((field) => field.key.trim().isNotEmpty)
              .toList(growable: false);
          if (conditionFieldKey.isEmpty && possibleParents.isNotEmpty) {
            conditionFieldKey = possibleParents.first.key;
          }
          return AlertDialog(
            title: Text('Add field to ${registry.title}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: labelController,
                    decoration: const InputDecoration(
                      labelText: 'Field label',
                      hintText: 'e.g. Antrum Pattern',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: suggestionsController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Suggestions (optional)',
                      hintText: 'One per line or comma-separated',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show conditionally'),
                    subtitle: const Text('Example: show Histology Result only when Biopsy Taken is Yes.'),
                    value: useCondition,
                    onChanged: (value) => setLocalState(() => useCondition = value),
                  ),
                  if (useCondition) ...[
                    DropdownButtonFormField<String>(
                      value: possibleParents.any((field) => field.key == conditionFieldKey)
                          ? conditionFieldKey
                          : (possibleParents.isEmpty ? null : possibleParents.first.key),
                      decoration: const InputDecoration(labelText: 'Depends on field'),
                      items: possibleParents
                          .map((field) => DropdownMenuItem<String>(
                                value: field.key,
                                child: Text(field.label, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(growable: false),
                      onChanged: (value) => setLocalState(() => conditionFieldKey = value ?? ''),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: conditionValueController,
                      decoration: const InputDecoration(
                        labelText: 'Show when value is',
                        hintText: 'e.g. Yes',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Add field')),
            ],
          );
        },
      ),
    );
    if (created == true && mounted && labelController.text.trim().isNotEmpty) {
      final suggestions = suggestionsController.text
          .split(RegExp(r'[,;\n\r]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      final provider = context.read<RecordsProvider>();
      await provider.addRegistryField(
        registryId: registry.registryId,
        label: labelController.text.trim(),
        hint: '',
        suggestions: suggestions,
        conditionalOnFieldKey: useCondition ? conditionFieldKey : '',
        conditionalEquals: useCondition ? conditionValueController.text.trim() : '',
      );
      final refreshed = await provider.repo.loadByRecordId(_entry.recordEntryId);
      if (!mounted) return;
      setState(() {
        if (refreshed != null) _entry = refreshed;
      });
    }
    // Do not dispose these immediately after popping the dialog. On macOS/desktop
    // Flutter can still rebuild or hit-test the just-dismissed TextFields for a
    // frame. Let GC reclaim them; this avoids intermittent disposed-controller
    // crashes in Records.
  }



  Future<void> _editRegistry(RecordRegistry registry) async {
    final titleController = TextEditingController(text: registry.title);
    final descriptionController = TextEditingController(text: registry.description);
    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit registry'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Registry name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Description (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
        ],
      ),
    );
    if (updated == true && mounted && titleController.text.trim().isNotEmpty) {
      await context.read<RecordsProvider>().updateRegistry(
            registryId: registry.registryId,
            title: titleController.text.trim(),
            description: descriptionController.text.trim(),
          );
      final refreshed = await context.read<RecordsProvider>().repo.loadByRecordId(_entry.recordEntryId);
      if (!mounted) return;
      setState(() {
        if (refreshed != null) _entry = refreshed;
      });
    }
  }

  Future<void> _editRegistryField(RecordRegistry registry, RecordFieldDef field) async {
    final labelController = TextEditingController(text: field.label);
    final suggestionsController = TextEditingController(text: field.builtInSuggestions.join('\n'));
    final conditionValueController = TextEditingController(text: field.conditionalEquals);
    var useCondition = field.conditionalOnFieldKey.trim().isNotEmpty;
    String conditionFieldKey = field.conditionalOnFieldKey;

    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocalState) {
          final provider = context.read<RecordsProvider>();
          final possibleParents = provider.allFields
              .where((candidate) => candidate.key != field.key)
              .where((candidate) => candidate.appliesToRegistries(_entry.registryIds))
              .where((candidate) => candidate.key.trim().isNotEmpty)
              .toList(growable: false);
          if (conditionFieldKey.isEmpty && possibleParents.isNotEmpty) {
            conditionFieldKey = possibleParents.first.key;
          }
          return AlertDialog(
            title: Text('Edit ${field.label}'),
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
                    controller: suggestionsController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Suggestions (optional)',
                      hintText: 'One per line or comma-separated',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show conditionally'),
                    subtitle: const Text('Show this field only when another field has a matching value.'),
                    value: useCondition,
                    onChanged: (value) => setLocalState(() => useCondition = value),
                  ),
                  if (useCondition) ...[
                    DropdownButtonFormField<String>(
                      value: possibleParents.any((candidate) => candidate.key == conditionFieldKey)
                          ? conditionFieldKey
                          : (possibleParents.isEmpty ? null : possibleParents.first.key),
                      decoration: const InputDecoration(labelText: 'Depends on field'),
                      items: possibleParents
                          .map((candidate) => DropdownMenuItem<String>(
                                value: candidate.key,
                                child: Text(candidate.label, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(growable: false),
                      onChanged: (value) => setLocalState(() => conditionFieldKey = value ?? ''),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: conditionValueController,
                      decoration: const InputDecoration(
                        labelText: 'Show when value is',
                        hintText: 'e.g. Yes',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
            ],
          );
        },
      ),
    );

    if (updated == true && mounted && labelController.text.trim().isNotEmpty) {
      final suggestions = suggestionsController.text
          .split(RegExp(r'[,;\n\r]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      await context.read<RecordsProvider>().updateRegistryField(
            registryId: registry.registryId,
            fieldKey: field.key,
            label: labelController.text.trim(),
            hint: field.hint,
            suggestions: suggestions,
            conditionalOnFieldKey: useCondition ? conditionFieldKey : '',
            conditionalEquals: useCondition ? conditionValueController.text.trim() : '',
          );
      final refreshed = await context.read<RecordsProvider>().repo.loadByRecordId(_entry.recordEntryId);
      if (!mounted) return;
      setState(() {
        if (refreshed != null) _entry = refreshed;
      });
    }
  }

  Future<void> _deleteRegistryField(RecordRegistry registry, RecordFieldDef field) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete registry field?'),
        content: Text(
          'Delete "${field.label}" from ${registry.title}? Existing saved values are preserved in old records, but this field will no longer show as a registry field.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<RecordsProvider>().deleteRegistryField(
          registryId: registry.registryId,
          fieldKey: field.key,
        );
    final refreshed = await context.read<RecordsProvider>().repo.loadByRecordId(_entry.recordEntryId);
    if (!mounted) return;
    setState(() {
      final base = refreshed ?? _entry;
      final values = Map<String, String>.from(base.values)..remove(field.key);
      final labels = Map<String, String>.from(base.fieldLabels)..remove(field.key);
      final sources = Map<String, String>.from(base.fieldSources)..remove(field.key);
      _entry = base.copyWith(values: values, fieldLabels: labels, fieldSources: sources);
    });
  }

  Future<void> _manageRegistries() async {
    final provider = context.read<RecordsProvider>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocalState) {
          final registries = context.watch<RecordsProvider>().registries;
          return AlertDialog(
            title: const Text('Manage registries / studies'),
            content: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.of(dialogContext).size.height * 0.65,
              child: registries.isEmpty
                  ? const Center(child: Text('No registries have been created yet.'))
                  : ListView.separated(
                      itemCount: registries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final registry = registries[index];
                        return ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(left: 8, right: 0, bottom: 8),
                          title: Text(registry.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${registry.fields.length} field${registry.fields.length == 1 ? '' : 's'}'),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Registry actions',
                            onSelected: (value) async {
                              if (value == 'rename') {
                                await _editRegistry(registry);
                                if (dialogContext.mounted) setLocalState(() {});
                              } else if (value == 'add_field') {
                                await _addRegistryField(registry);
                                if (dialogContext.mounted) setLocalState(() {});
                              } else if (value == 'delete') {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (confirmContext) => AlertDialog(
                                    title: const Text('Delete registry?'),
                                    content: Text(
                                      'Delete ${registry.title}? This removes the registry setup and removes it from records. Existing record values are preserved but will no longer show as registry fields.',
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(confirmContext, false), child: const Text('Cancel')),
                                      FilledButton(onPressed: () => Navigator.pop(confirmContext, true), child: const Text('Delete')),
                                    ],
                                  ),
                                );
                                if (confirmed != true) return;
                                await provider.deleteRegistry(registry.registryId);
                                if (!mounted) return;
                                setState(() {
                                  final removedFieldKeys = registry.fields.map((field) => field.key).toSet();
                                  final values = Map<String, String>.from(_entry.values)
                                    ..removeWhere((key, _) => removedFieldKeys.contains(key));
                                  final labels = Map<String, String>.from(_entry.fieldLabels)
                                    ..removeWhere((key, _) => removedFieldKeys.contains(key));
                                  final sources = Map<String, String>.from(_entry.fieldSources)
                                    ..removeWhere((key, _) => removedFieldKeys.contains(key));
                                  _entry = _entry.copyWith(
                                    values: values,
                                    fieldLabels: labels,
                                    fieldSources: sources,
                                    registryIds: _entry.registryIds.where((id) => id != registry.registryId).toList(growable: false),
                                  );
                                });
                                if (dialogContext.mounted) setLocalState(() {});
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'rename', child: Text('Edit registry name')),
                              PopupMenuItem(value: 'add_field', child: Text('Add registry field')),
                              PopupMenuDivider(),
                              PopupMenuItem(value: 'delete', child: Text('Delete registry')),
                            ],
                          ),
                          children: [
                            if (registry.description.trim().isNotEmpty)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(registry.description),
                                ),
                              ),
                            if (registry.fields.isEmpty)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () async {
                                    await _addRegistryField(registry);
                                    if (dialogContext.mounted) setLocalState(() {});
                                  },
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add first field'),
                                ),
                              )
                            else
                              ...registry.fields.map((field) {
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(field.label),
                                  subtitle: field.builtInSuggestions.isEmpty
                                      ? (field.conditionalOnFieldKey.trim().isEmpty ? null : Text('Conditional: ${field.conditionalEquals}'))
                                      : Text(field.builtInSuggestions.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: PopupMenuButton<String>(
                                    tooltip: 'Field actions',
                                    onSelected: (value) async {
                                      if (value == 'edit') {
                                        await _editRegistryField(registry, field);
                                      } else if (value == 'delete') {
                                        await _deleteRegistryField(registry, field);
                                      }
                                      if (dialogContext.mounted) setLocalState(() {});
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'edit', child: Text('Edit field')),
                                      PopupMenuItem(value: 'delete', child: Text('Delete field')),
                                    ],
                                  ),
                                );
                              }),
                          ],
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _removeRegistry(RecordRegistry registry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove from registry?'),
        content: Text('This record will no longer be part of ${registry.title}. Saved registry field values are preserved unless you clear them manually.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final updated = await context.read<RecordsProvider>().removeRecordFromRegistry(
      recordEntryId: _entry.recordEntryId,
      registryId: registry.registryId,
    );
    if (!mounted) return;
    setState(() {
      _entry = updated ?? _entry.copyWith(
        registryIds: _entry.registryIds.where((id) => id != registry.registryId).toList(growable: false),
      );
    });
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
          _RegistryCard(
            registries: provider.registries,
            entryRegistryIds: _entry.registryIds,
            onAddRegistry: _assignRegistry,
            onCreateRegistry: _createRegistry,
            onAddField: _addRegistryField,
            onRemoveRegistry: _removeRegistry,
            onManageRegistries: _manageRegistries,
          ),
          const SizedBox(height: 16),
          for (final field in fields) ...[
            _RecordValueField(
              key: ValueKey('record-field-${field.key}'),
              field: field,
              currentProcedure: _currentProcedure,
              controller: _controllerFor(field.key, _entry.valueOf(field.key)),
              onManage: _protectedRecordKeys.contains(field.key)
                  ? null
                  : (field.isRegistryField
                      ? _manageRegistries
                      : (!field.isSystem && provider.allFields.any((f) => f.key == field.key)
                          ? () => _editCustomFieldDefinition(field)
                          : null)),
              onDelete: _protectedRecordKeys.contains(field.key)
                  ? null
                  : (!field.isSystem && !field.isRegistryField && provider.allFields.any((f) => f.key == field.key)
                      ? () => _deleteCustomFieldDefinition(field)
                      : () => _confirmHideFieldFromThisRecord(field)),
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
  final VoidCallback? onManage;
  final VoidCallback? onDelete;

  const _RecordValueField({
    super.key,
    required this.field,
    required this.currentProcedure,
    required this.controller,
    this.onManage,
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

  bool get _showSourceLabel => !widget.field.key.startsWith('section_');

  String get _sourceLabel {
    if (widget.field.isRegistryField) return 'registry';
    if (!widget.field.isSystem && widget.field.isGlobal) return 'general';
    if (!widget.field.isSystem) return 'procedure';
    return 'template';
  }

  static const int _maxVisibleSuggestions = 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.field.label,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (_showSourceLabel) ...[
                    const SizedBox(height: 2),
                    Text(
                      _sourceLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.1,
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.58),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.onManage != null || widget.onDelete != null)
              PopupMenuButton<String>(
                tooltip: 'Manage field',
                onSelected: (value) {
                  if (value == 'manage') widget.onManage?.call();
                  if (value == 'delete') widget.onDelete?.call();
                },
                itemBuilder: (_) => [
                  if (widget.onManage != null)
                    const PopupMenuItem(value: 'manage', child: Text('Manage field')),
                  if (widget.onDelete != null)
                    const PopupMenuItem(value: 'delete', child: Text('Delete / hide field')),
                ],
              ),
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
          future: widget.field.isRegistryField
              ? Future.value(widget.field.builtInSuggestions)
              : context.read<RecordsProvider>().suggestions(
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
                children: options.take(_maxVisibleSuggestions).map((option) {
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



class _RegistryCard extends StatelessWidget {
  final List<RecordRegistry> registries;
  final List<String> entryRegistryIds;
  final VoidCallback onAddRegistry;
  final VoidCallback onCreateRegistry;
  final Future<void> Function(RecordRegistry registry) onAddField;
  final Future<void> Function(RecordRegistry registry) onRemoveRegistry;
  final VoidCallback onManageRegistries;

  const _RegistryCard({
    required this.registries,
    required this.entryRegistryIds,
    required this.onAddRegistry,
    required this.onCreateRegistry,
    required this.onAddField,
    required this.onRemoveRegistry,
    required this.onManageRegistries,
  });

  Future<void> _openRegistryOptions(BuildContext context, List<RecordRegistry> active) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final maxHeight = MediaQuery.of(sheetContext).size.height * 0.82;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Registry / Study options',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Optional research or audit fields. Registry data does not change the saved PDF.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.playlist_add_outlined),
                    title: const Text('Add this record to registry'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onAddRegistry();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: const Text('Create new registry'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onCreateRegistry();
                    },
                  ),
                  if (active.isNotEmpty) ...[
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Text('Active registries', style: theme.textTheme.labelLarge),
                    ),
                    for (final registry in active)
                      ListTile(
                        leading: const Icon(Icons.science_outlined),
                        title: Text(registry.title),
                        subtitle: Text('${registry.fields.length} field${registry.fields.length == 1 ? '' : 's'}'),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: 'Add registry field',
                              icon: const Icon(Icons.add_box_outlined),
                              onPressed: () {
                                Navigator.pop(sheetContext);
                                onAddField(registry);
                              },
                            ),
                            IconButton(
                              tooltip: 'Remove from this record',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                Navigator.pop(sheetContext);
                                onRemoveRegistry(registry);
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('Manage registries'),
                    subtitle: const Text('Edit names, add/edit fields, delete test registries.'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onManageRegistries();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = registries.where((registry) => entryRegistryIds.contains(registry.registryId)).toList(growable: false);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openRegistryOptions(context, active),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Icon(Icons.science_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Registry / Study',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    if (active.isEmpty)
                      Text(
                        'Not assigned',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: active.map((registry) {
                          return Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(registry.title, overflow: TextOverflow.ellipsis),
                            avatar: const Icon(Icons.check, size: 16),
                          );
                        }).toList(growable: false),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _openRegistryOptions(context, active),
                child: const Text('Options'),
              ),
            ],
          ),
        ),
      ),
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
