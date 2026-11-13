import 'package:flutter/material.dart';

import '../../domain/models/nodes.dart';
import '../../domain/guided_report_presentation.dart';

/// One action per collection. Guided findings keep it after the independent
/// cards so the next entry is available where the user finishes the last one.
class RepeatableFindings extends StatefulWidget {
  const RepeatableFindings({
    super.key,
    required this.section,
    required this.buildItem,
    required this.onAdd,
    required this.onRemove,
    required this.onToggle,
  });
  final SectionNode section;
  final Widget Function(SectionNode) buildItem;
  final String? Function(String) onAdd;
  final void Function(String) onRemove;
  final void Function(String) onToggle;

  @override
  State<RepeatableFindings> createState() => _RepeatableFindingsState();
}

class _RepeatableFindingsState extends State<RepeatableFindings> {
  final _itemKeys = <String, GlobalKey>{};

  void _add(String blueprint) {
    final id = widget.onAdd(blueprint);
    if (id == null || widget.section.reportRole != 'ogd.findings') return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final itemContext = _itemKeys[id]?.currentContext;
      if (itemContext == null) return;
      Scrollable.ensureVisible(
        itemContext,
        alignment: .05,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
      );
    });
  }

  String _summary(SectionNode item) {
    final fields = item.children.whereType<SectionNode>();
    final parts = <String>[];
    for (final field in fields) {
      final value = fieldValue(field);
      if (value.isEmpty) continue;
      if (field.reportRole == 'finding.location') parts.add(value);
      if (field.title == 'Size' && field.inputType == FieldInputType.numeric) {
        parts.add('$value${field.unit.isEmpty ? '' : ' ${field.unit}'}');
      }
    }
    return parts.isEmpty ? 'Open to review details' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final items = section.children.whereType<SectionNode>().toList();
    final guidedFindings = section.reportRole == 'ogd.findings';
    _itemKeys.removeWhere((id, _) => !items.any((item) => item.id == id));
    final action = FilledButton.icon(
      key: ValueKey('add-finding-${section.id}'),
      icon: const Icon(Icons.add),
      label: Text(
        guidedFindings &&
                items.isNotEmpty &&
                section.repeatableAddLabel == 'Add finding'
            ? 'Add another finding'
            : section.repeatableAddLabel,
      ),
      onPressed: () async {
        FocusManager.instance.primaryFocus?.unfocus();
        if (section.repeatableTemplates.length == 1 &&
            (section.reportRole == 'ogd.medications' ||
                section.reportRole == 'ogd.specimens')) {
          _add(section.repeatableTemplates.single.id);
          return;
        }
        final selected = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (context) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .65,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Choose ${section.title.toLowerCase()}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: section.repeatableTemplates
                          .map(
                            (type) => ListTile(
                              key: ValueKey('finding-type-${type.id}'),
                              title: Text(type.title),
                              trailing: const Icon(Icons.add),
                              onTap: () => Navigator.pop(context, type.id),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        if (selected != null && mounted) _add(selected);
      },
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!guidedFindings) action,
          if (items.isEmpty && section.reportRole != 'ogd.specimens')
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                section.reportRole == 'ogd.medications'
                    ? 'Record medications actually administered, with dose, unit and route.'
                    : 'Choose a finding to enter its details. Add separate entries for findings that differ.',
              ),
            ),
          for (final item in items)
            Card(
              key: ValueKey('finding-card-${item.id}'),
              margin: const EdgeInsets.only(top: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  key: _itemKeys.putIfAbsent(item.id, () => GlobalKey()),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            key: ValueKey('toggle-finding-${item.id}'),
                            style: TextButton.styleFrom(
                              alignment: Alignment.centerLeft,
                            ),
                            onPressed: () => widget.onToggle(item.id),
                            icon: Icon(
                              item.collapsed
                                  ? Icons.expand_more
                                  : Icons.expand_less,
                            ),
                            label: Text(
                              '${item.title} ${items.indexOf(item) + 1}',
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove ${item.title}',
                          icon: const Icon(Icons.delete_outline),
                          key: ValueKey('remove-finding-${item.id}'),
                          onPressed: () async {
                            final remove = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text('Remove ${item.title}?'),
                                content: const Text(
                                  'This removes this entry and its details only.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Keep'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Remove'),
                                  ),
                                ],
                              ),
                            );
                            if (remove == true && mounted)
                              widget.onRemove(item.id);
                          },
                        ),
                      ],
                    ),
                    if (item.collapsed && guidedFindings)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Text(
                          _summary(item),
                          key: ValueKey('finding-summary-${item.id}'),
                        ),
                      ),
                    if (!item.collapsed) widget.buildItem(item),
                  ],
                ),
              ),
            ),
          if (guidedFindings)
            Padding(padding: const EdgeInsets.only(top: 12), child: action),
        ],
      ),
    );
  }
}
