import 'models/nodes.dart';

/// Rendering-only grouping: saved entries retain their identity and entry order.
/// Each finding remains separate even when several share one anatomical site.
List<SectionNode> findingsInAnatomicalOrder(List<SectionNode> roots) {
  SectionNode arrange(SectionNode section) {
    if (!section.isRepeatable) return section.copyWith(children: section.children.map((n) => n is SectionNode ? arrange(n) : n).toList());
    final entries = section.children.whereType<SectionNode>().toList();
    if (entries.isEmpty) return section;
    final groups = <String, List<SectionNode>>{};
    final ranks = <String, int>{};
    for (final item in entries) {
      final locations = item.children.whereType<SectionNode>().where((c) => c.title == 'Location');
      // Non-anatomical collections such as specimen containers retain entry order.
      if (locations.isEmpty) return section;
      final location = locations.first;
      final value = location.children.whereType<ContentNode>().map((c) => c.text.trim()).where((v) => v.isNotEmpty).join('; ');
      final site = value.isEmpty ? 'Location not recorded' : value;
      groups.putIfAbsent(site, () => []).add(item);
      final index = location.options.indexOf(value);
      ranks[site] = index < 0 ? 999 : index;
    }
    final sites = groups.keys.toList()..sort((a,b) => ranks[a]!.compareTo(ranks[b]!));
    return section.copyWith(repeatableTemplates: const [], children: [
      for (var i = 0; i < sites.length; i++) SectionNode(
        id: '${section.id}_site_$i', title: sites[i], omitWhenEmpty: true,
        children: groups[sites[i]]!,
      ),
    ]);
  }
  return roots.map(arrange).toList();
}
