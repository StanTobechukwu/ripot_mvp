import 'models/nodes.dart';

String fieldValue(SectionNode section) => section.children
    .whereType<ContentNode>()
    .map((n) => n.text.trim())
    .where((v) => v.isNotEmpty)
    .join('; ');

Iterable<SectionNode> _sections(Iterable<SectionNode> roots) sync* {
  for (final node in roots) {
    yield node;
    yield* _sections(node.children.whereType<SectionNode>());
  }
}

/// Filter against the original values before replacing form controls with prose.
/// Collapsing a card is presentation only and never excludes its contents.
List<SectionNode> _visible(List<SectionNode> roots) {
  final values = {for (final n in _sections(roots)) n.id: fieldValue(n)};
  SectionNode? walk(SectionNode n) {
    if (n.hasCondition) {
      final options = (values[n.conditionalParentSectionId] ?? '')
          .toLowerCase().split(';').map((v) => v.trim());
      if (!options.contains(n.conditionalEquals.trim().toLowerCase())) return null;
    }
    return n.copyWith(
      conditionalParentSectionId: '', conditionalEquals: '',
      children: [for (final child in n.children)
        if (child is SectionNode) ...[if (walk(child) case final next?) next]
        else child],
    );
  }
  return [for (final root in roots) if (walk(root) case final next?) next];
}

String _label(SectionNode n) => n.reportLabel.isEmpty ? n.title : n.reportLabel;
String _valueWithUnit(SectionNode n) {
  final value = fieldValue(n);
  if (value.isEmpty) return '';
  return n.inputType == FieldInputType.numeric && n.unit.isNotEmpty
      ? '$value ${n.unit}' : value;
}

String _fieldText(SectionNode n, {bool withLabel = true}) {
  final parts = <String>[
    if (n.showInPdf && _valueWithUnit(n).isNotEmpty) _valueWithUnit(n),
    if (n.note.trim().isNotEmpty) n.note.trim(),
  ];
  if (parts.isEmpty) return '';
  return '${withLabel && _label(n).isNotEmpty ? '${_label(n)}: ' : ''}${parts.join(' — ')}';
}

SectionNode _paragraph(String id, String title, String text) => SectionNode(
  id: id, title: title, omitWhenEmpty: true, reportRole: 'report.paragraph',
  children: [ContentNode(id: '${id}_text', text: text)],
);

List<String> _detailParts(Iterable<SectionNode> fields) {
  final out = <String>[];
  final c = fields.where((n) => n.reportRole == 'grading.prague.c').firstOrNull;
  final m = fields.where((n) => n.reportRole == 'grading.prague.m').firstOrNull;
  final validPrague = c != null && m != null && c.showInPdf && m.showInPdf &&
      _pragueValid(c, m);
  for (final field in fields) {
    if (validPrague && field.reportRole.startsWith('grading.prague.')) {
      if (field == c) {
        out.add('Prague C${_pragueNumber(c!)}M${_pragueNumber(m!)}');
      }
      if (field.note.trim().isNotEmpty) out.add('${field.title} note: ${field.note.trim()}');
      continue;
    }
    if (field.reportRole == 'finding.location') {
      if (field.note.trim().isNotEmpty) out.add('Location detail: ${field.note.trim()}');
      continue;
    }
    if (field.reportRole == 'ogd.biopsy' && fieldValue(field) == 'Yes') {
      // Recorded once in the sampling summary, with the parent finding/site.
      continue;
    }
    final own = _fieldText(field);
    if (own.isNotEmpty) out.add(own);
    out.addAll(_detailParts(field.children.whereType<SectionNode>()));
  }
  return out;
}

bool _pragueValid(SectionNode c, SectionNode m) {
  final cv = double.tryParse(fieldValue(c));
  final mv = double.tryParse(fieldValue(m));
  return cv != null && mv != null && cv.isFinite && mv.isFinite && cv >= 0 && mv >= cv;
}

String _pragueNumber(SectionNode field) {
  final number = double.parse(fieldValue(field));
  return number == number.truncateToDouble() ? number.toInt().toString() : number.toString();
}

SectionNode? _role(SectionNode n, String role) {
  for (final child in _sections(n.children.whereType<SectionNode>())) {
    if (child.reportRole == role) return child;
  }
  return null;
}

String _samplingText(SectionNode n) {
  final details = <String>[];
  for (final role in ['biopsy.count', 'biopsy.type', 'biopsy.container', 'biopsy.note']) {
    final field = _role(n, role);
    if (field == null) continue;
    final text = _fieldText(field, withLabel: role != 'biopsy.note');
    if (text.isNotEmpty) details.add(text);
  }
  if (n.note.trim().isNotEmpty) details.add(n.note.trim());
  return details.isEmpty ? 'Biopsy taken; details not recorded' : details.join('; ');
}

/// The form and PDF use the same read-only summary. Data stays on its original
/// finding or standalone biopsy entry; no duplicated patient values are saved.
List<SectionNode> guidedSamplingSummary(List<SectionNode> roots) =>
    _samplingFromVisible(_visible(roots));

List<SectionNode> _samplingFromVisible(List<SectionNode> roots) {
  final result = <SectionNode>[];
  for (final region in _sections(roots).where((n) => n.reportRole == 'ogd.region')) {
    final collections = region.children.whereType<SectionNode>()
        .where((n) => n.reportRole == 'ogd.findings');
    for (final collection in collections) {
      final entries = collection.children.whereType<SectionNode>().toList();
      final counts = <String, int>{};
      for (final entry in entries) {
        final ordinal = counts.update(entry.title, (n) => n + 1, ifAbsent: () => 1);
        final biopsy = _role(entry, 'ogd.biopsy');
        if (biopsy == null || fieldValue(biopsy) != 'Yes') continue;
        final location = _role(entry, 'finding.location');
        final site = location == null ? '' : fieldValue(location);
        final repeated = entries.where((n) => n.title == entry.title).length > 1;
        final finding = '${entry.title}${repeated ? ' $ordinal' : ''}';
        final label = [region.title, if (site.isNotEmpty) site, finding].join(' — ');
        result.add(_paragraph('${entry.id}_sampling', label,
          [if (location?.note.trim().isNotEmpty == true) 'Site detail: ${location!.note.trim()}',
            _samplingText(biopsy)].join('; ')));
      }
    }
  }
  for (final entry in _sections(roots).where((n) => n.reportRole == 'ogd.specimen')) {
    final region = _role(entry, 'biopsy.region');
    final site = _role(entry, 'biopsy.site');
    final regionText = region == null ? '' : _fieldText(region, withLabel: false);
    final siteText = site == null ? '' : _fieldText(site, withLabel: false);
    final hasContent = _sections([entry]).any((n) => fieldValue(n).isNotEmpty || n.note.trim().isNotEmpty);
    if (!hasContent) continue;
    final label = [if (regionText.isNotEmpty) regionText, if (siteText.isNotEmpty) siteText].join(' — ');
    result.add(_paragraph('${entry.id}_sampling', label.isEmpty ? 'Site not recorded' : label, _samplingText(entry)));
  }
  return result;
}

/// Prompt before export; drafts can still be saved at any stage.
List<String> guidedReportWarnings(List<SectionNode> roots) {
  final result = <String>[];
  final visible = _visible(roots);
  for (final region in _sections(visible).where((n) => n.reportRole == 'ogd.region')) {
    final assessment = _role(region, 'ogd.assessment');
    final findings = _role(region, 'ogd.findings');
    if (assessment != null && fieldValue(assessment) == 'Abnormal' &&
        (findings == null || findings.children.whereType<SectionNode>().isEmpty)) {
      result.add('${region.title}: add a finding or record the limitation.');
    }
  }
  for (final entry in _sections(visible).where((n) => n.reportRole == 'ogd.finding')) {
    final c = _role(entry, 'grading.prague.c');
    final m = _role(entry, 'grading.prague.m');
    if (c == null || m == null || (fieldValue(c).isEmpty && fieldValue(m).isEmpty)) continue;
    if (!_pragueValid(c, m)) {
      result.add('${entry.title}: check Prague C and M. Enter both measurements in cm, '
          'with C at least 0 and M at least C. Unconfirmed measurements remain separate in the report.');
    }
  }
  return result;
}

/// Opt-in report projection for the new guided template. Older saved reports,
/// custom templates and their stored values are unchanged.
List<SectionNode> prepareGuidedReport(List<SectionNode> roots) {
  if (!_sections(roots).any((n) => n.reportRole.startsWith('ogd.'))) return roots;
  final visible = _visible(roots);
  final sampling = _samplingFromVisible(visible);

  List<SectionNode> transform(SectionNode n) {
    if (n.reportRole == 'ogd.sampling') {
      return sampling.isEmpty ? [] : [n.copyWith(children: sampling, repeatableTemplates: const [])];
    }
    if (n.reportRole == 'ogd.details') {
      return n.children.whereType<SectionNode>().expand(transform).toList();
    }
    if (n.reportRole == 'ogd.preparation') {
      final parts = _detailParts(n.children.whereType<SectionNode>());
      return parts.isEmpty ? [] : [_paragraph(n.id, n.title, parts.join('; '))];
    }
    if (n.reportRole == 'ogd.medication') {
      final name = _role(n, 'medication.name');
      final drug = name == null ? '' : _fieldText(name, withLabel: false);
      final dose = _role(n, 'medication.dose');
      final unit = _role(n, 'medication.unit');
      final route = _role(n, 'medication.route');
      final doseText = dose == null ? '' : _fieldText(dose, withLabel: false);
      final unitText = unit == null ? '' : _fieldText(unit, withLabel: false);
      final routeText = route == null ? '' : _fieldText(route, withLabel: false);
      final parts = <String>[
        if (doseText.isNotEmpty) [doseText, if (unitText.isNotEmpty) unitText].join(' '),
        if (doseText.isEmpty && unitText.isNotEmpty) 'Unit: $unitText',
        if (routeText.isNotEmpty) routeText,
        ..._detailParts(n.children.whereType<SectionNode>()
            .where((c) => !c.reportRole.startsWith('medication.'))),
      ];
      if (drug.isEmpty && parts.isEmpty) return [];
      return [_paragraph(n.id, drug.isEmpty ? 'Medication — name not recorded' : drug,
          parts.isEmpty ? 'Dose / route not recorded' : parts.join('; '))];
    }
    if (n.reportRole == 'ogd.findings') {
      final entries = n.children.whereType<SectionNode>().toList();
      final groups = <String, List<SectionNode>>{};
      final ranks = <String, int>{};
      final counts = <String, int>{};
      for (final entry in entries) {
        final location = _role(entry, 'finding.location');
        final value = location == null ? '' : fieldValue(location);
        final site = value.isEmpty ? 'Location not recorded' : value;
        final index = location?.options.indexOf(value) ?? -1;
        ranks[site] = index < 0 ? 999 : index;
        final ordinal = counts.update(entry.title, (v) => v + 1, ifAbsent: () => 1);
        final repeated = entries.where((e) => e.title == entry.title).length > 1;
        final label = '${entry.title}${repeated ? ' $ordinal' : ''}';
        final parts = _detailParts(entry.children.whereType<SectionNode>());
        if (entry.note.trim().isNotEmpty) parts.add(entry.note.trim());
        groups.putIfAbsent(site, () => []).add(_paragraph(entry.id, label,
          parts.isEmpty ? 'Details not recorded' : parts.join('; ')));
      }
      final sites = groups.keys.toList()..sort((a, b) => ranks[a]!.compareTo(ranks[b]!));
      return [for (var i = 0; i < sites.length; i++) SectionNode(
        id: '${n.id}_site_$i', title: sites[i], omitWhenEmpty: true, children: groups[sites[i]]!)];
    }
    if (n.reportRole == 'ogd.region') {
      final assessment = _role(n, 'ogd.assessment');
      final status = assessment == null ? '' : fieldValue(assessment);
      final children = n.children.whereType<SectionNode>()
          .where((c) => c.reportRole != 'ogd.assessment').expand(transform).toList();
      final findings = _role(n, 'ogd.findings');
      final missing = status == 'Abnormal' &&
          (findings == null || findings.children.whereType<SectionNode>().isEmpty);
      final intro = [
        if (status.isNotEmpty && status != 'Abnormal') status,
        if (missing) 'Abnormal — findings not recorded',
        if (assessment?.note.trim().isNotEmpty == true) assessment!.note.trim(),
      ].join('; ');
      return [n.copyWith(children: [
        if (intro.isNotEmpty) ContentNode(id: '${n.id}_assessment', text: intro), ...children])];
    }
    final children = <Node>[for (final child in n.children)
      if (child is SectionNode) ...transform(child) else child];
    return [n.copyWith(title: _label(n), repeatableTemplates: const [], children: children)];
  }
  return visible.expand(transform).toList();
}
