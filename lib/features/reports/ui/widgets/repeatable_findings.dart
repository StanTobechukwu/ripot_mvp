import 'package:flutter/material.dart';
import '../../domain/models/nodes.dart';

/// One prominent action, then independent cards. Choosing a type adds only
/// that type; the unused blueprints are never rendered as report fields.
class RepeatableFindings extends StatelessWidget {
  const RepeatableFindings({super.key, required this.section, required this.buildItem,
    required this.onAdd, required this.onRemove, required this.onToggle});
  final SectionNode section;
  final Widget Function(SectionNode) buildItem;
  final void Function(String) onAdd;
  final void Function(String) onRemove;
  final void Function(String) onToggle;

  @override
  Widget build(BuildContext context) {
    final items = section.children.whereType<SectionNode>().toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton.icon(
          key: ValueKey('add-finding-${section.id}'),
          icon: const Icon(Icons.add), label: Text(section.repeatableAddLabel),
          onPressed: () async {
            FocusManager.instance.primaryFocus?.unfocus();
            if (section.repeatableTemplates.length == 1 &&
                (section.reportRole == 'ogd.medications' || section.reportRole == 'ogd.specimens')) {
              onAdd(section.repeatableTemplates.single.id);
              return;
            }
            final selected = await showModalBottomSheet<String>(
              context: context, showDragHandle: true, isScrollControlled: true,
              builder: (context) => SafeArea(child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .65,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(padding: const EdgeInsets.all(16), child: Text(
                    'Choose ${section.title.toLowerCase()}', style: Theme.of(context).textTheme.titleLarge)),
                  Expanded(child: ListView(children: section.repeatableTemplates.map((type) => ListTile(
                    key: ValueKey('finding-type-${type.id}'),
                    title: Text(type.title), trailing: const Icon(Icons.add),
                    onTap: () => Navigator.pop(context, type.id),
                  )).toList())),
                ]),
              )),
            );
            if (selected != null && context.mounted) onAdd(selected);
          },
        ),
        if (items.isEmpty && section.reportRole != 'ogd.specimens') Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(section.reportRole == 'ogd.medications'
            ? 'Record medications actually administered, with dose, unit and route.'
            : 'Choose a finding to enter its details. Add separate entries for findings that differ.')),
        for (final item in items) Card(
          key: ValueKey('finding-card-${item.id}'),
          margin: const EdgeInsets.only(top: 12),
          child: Padding(padding: const EdgeInsets.all(12), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: TextButton.icon(
                  key: ValueKey('toggle-finding-${item.id}'),
                  style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                  onPressed: () => onToggle(item.id),
                  icon: Icon(item.collapsed ? Icons.expand_more : Icons.expand_less),
                  label: Text('${item.title} ${items.indexOf(item) + 1}'),
                )),
                IconButton(tooltip: 'Remove ${item.title}', icon: const Icon(Icons.delete_outline),
                  key: ValueKey('remove-finding-${item.id}'),
                  onPressed: () async {
                    final remove = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
                      title: Text('Remove ${item.title}?'), content: const Text('This removes this entry and its details only.'),
                      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove'))],
                    ));
                    if (remove == true && context.mounted) onRemove(item.id);
                  }),
              ]),
              if (!item.collapsed) buildItem(item),
            ],
          )),
        ),
      ]),
    );
  }
}
