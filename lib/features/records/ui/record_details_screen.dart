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

  String get _currentProcedure => _entry.valueOf(RecordFieldCatalog.procedure.key);

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
    return _controllers.putIfAbsent(key, () => TextEditingController(text: displayValue));
  }

  bool _fieldVisibleForCurrentProcedure(RecordFieldDef field) {
    return field.appliesToProcedure(_currentProcedure);
  }

  Future<void> _save() async {
    if (_saving) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save final record?'),
        content: const Text(
          'This will save the report as a final record in Ripot. The saved record becomes read-only and cannot be edited later. Future changes should be added as updates or addenda, not by changing the original record.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save Record')),
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
    final provider = context.read<RecordsProvider>();
    await provider.saveRecord(
      _entry.copyWith(
        updatedAtIso: DateTime.now().toIso8601String(),
        values: values,
      ),
    );
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _deleteCustomField(RecordFieldDef field) async {
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

    _controllers.remove(field.key)?.dispose();
    final values = Map<String, String>.from(_entry.values)..remove(field.key);
    setState(() => _entry = _entry.copyWith(values: values));
    await context.read<RecordsProvider>().deleteCustomField(field.key);
  }

  Future<void> _addField() async {
    final labelController = TextEditingController();
    final hintController = TextEditingController();
    var saveAsGlobal = true;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Add new record field'),
          content: Column(
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
              if (_currentProcedure.trim().isNotEmpty) ...[
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
                  title: const Text('All procedures (general field)'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<bool>(
                  value: false,
                  groupValue: saveAsGlobal,
                  onChanged: (v) => setLocalState(() => saveAsGlobal = v ?? true),
                  title: Text('Only for $_currentProcedure'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ],
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
        final procedureScope = saveAsGlobal ? '' : _currentProcedure.trim();
        await context.read<RecordsProvider>().addCustomField(label: label, hint: hint, procedureScope: procedureScope);
      }
    }
    labelController.dispose();
    hintController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecordsProvider>();
    final allFields = provider.allFields;
    final fields = allFields.where(_fieldVisibleForCurrentProcedure).toList(growable: false);
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
                      Text('Save to Records', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Records help you keep a searchable final log in list or table form later. Once saved, the original record becomes read-only.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _currentProcedure.trim().isEmpty
                        ? 'You can add extra record fields for your unit before saving.'
                        : 'You can add extra record fields either for all procedures or specifically for $_currentProcedure.',
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
              field: field,
              controller: _controllerFor(field.key, _entry.valueOf(field.key)),
              onDelete: field.isSystem ? null : () => _deleteCustomField(field),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _save,
            icon: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Save Final Record'),
          ),
        ],
      ),
    );
  }
}

class _RecordValueField extends StatefulWidget {
  final RecordFieldDef field;
  final TextEditingController controller;
  final VoidCallback? onDelete;

  const _RecordValueField({required this.field, required this.controller, this.onDelete});

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
                child: Text(widget.field.isGlobal ? 'Custom • General' : 'Custom • Procedure', style: theme.textTheme.labelSmall),
              ),
              IconButton(
                tooltip: 'Delete custom field',
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        if (!widget.field.isGlobal) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Applies only to ${widget.field.procedureScope}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
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
          future: context.read<RecordsProvider>().suggestions(widget.field.key, _controller.text),
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
                    onPressed: () => _controller.text = option,
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
