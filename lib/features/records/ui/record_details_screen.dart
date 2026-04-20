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

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final values = <String, String>{};
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

  Future<void> _addField() async {
    final labelController = TextEditingController();
    final hintController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (created == true && mounted) {
      final label = labelController.text.trim();
      final hint = hintController.text.trim();
      if (label.isNotEmpty) {
        await context.read<RecordsProvider>().addCustomField(label: label, hint: hint);
      }
    }
    labelController.dispose();
    hintController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecordsProvider>();
    final fields = provider.allFields;

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
                    'This step is optional. Records help you keep a searchable log in list or table form later without changing the report itself.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'You can also add extra record fields for your unit or specialty.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final field in fields) ...[
            _RecordValueField(field: field, controller: _controllerFor(field.key, _entry.valueOf(field.key))),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _save,
            icon: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Save to Records'),
          ),
        ],
      ),
    );
  }
}

class _RecordValueField extends StatefulWidget {
  final RecordFieldDef field;
  final TextEditingController controller;

  const _RecordValueField({required this.field, required this.controller});

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
            if (!widget.field.isSystem)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('Custom', style: theme.textTheme.labelSmall),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Suggestions',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: options.take(8).map((s) {
                      final selected = _controller.text.trim().toLowerCase() == s.trim().toLowerCase();
                      return ActionChip(
                        backgroundColor: selected ? theme.colorScheme.primary.withOpacity(0.14) : theme.colorScheme.surface,
                        side: BorderSide(
                          color: selected ? theme.colorScheme.primary.withOpacity(0.45) : theme.dividerColor.withOpacity(0.45),
                        ),
                        label: Text(s),
                        onPressed: () => _controller.text = s,
                      );
                    }).toList(growable: false),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
