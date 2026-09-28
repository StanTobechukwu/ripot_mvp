import '../data/registry_repository.dart';
import '../../records/domain/record_models.dart';

class RegistryTableData {
  final List<String> headers;
  final List<List<String>> rows;
  final List<String> patientIds;
  const RegistryTableData(this.headers, this.rows, this.patientIds);

  static String date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  // Retain different definitions/units as separate columns, never imply conversion.
  static String _identity(RecordFieldDef f) =>
      [f.key, f.label, f.unit, f.groupName, f.patientDetail.toString()].join('\u0000');

  factory RegistryTableData.build(
    RecordRegistry registry,
    RegistryData data, {
    String? patientId,
    bool allUpdates = false,
  }) {
    final history = allUpdates || patientId != null;
    final patients = data.patients
        .where(
          (p) =>
              p.registryIds.contains(registry.registryId) &&
              (patientId == null || p.id == patientId),
        )
        .toList();
    final updates =
        data.updates
            .where(
              (u) =>
                  u.registryId == registry.registryId &&
                  patients.any((p) => p.id == u.patientId),
            )
            .toList()
          ..sort((a, b) {
            final c = b.observedAt.compareTo(a.observedAt);
            return c != 0 ? c : b.recordedAt.compareTo(a.recordedAt);
          });
    final defs = <String, RecordFieldDef>{};
    for (final f in registry.fields) {
      defs[_identity(f)] = f;
    }
    for (final u in updates) {
      for (final key in u.values.keys) {
        final f =
            u.definitions[key] ??
            RecordFieldDef(key: key, label: key, hint: '');
        defs[_identity(f)] = f;
      }
    }
    final columns = defs.entries.toList()
      ..sort((a, b) {
        final group = a.value.groupName.compareTo(b.value.groupName);
        if (group != 0) return group;
        final label = a.value.label.compareTo(b.value.label);
        return label != 0 ? label : a.key.compareTo(b.key);
      });
    final headers = <String>[
      'Patient',
      'Identifier',
      'Facility',
      'Ripot patient ID',
      if (history) 'Observation date',
      if (history) 'Entry type',
      if (history) 'Source report',
      for (final c in columns)
        [
          c.value.groupName,
          '${c.value.label}${c.value.patientDetail ? ' · Patient detail' : ''}',
          if (c.value.unit.isNotEmpty) '(${c.value.unit})',
        ].where((s) => s.isNotEmpty).join('\n'),
    ];
    String value(
      RegistryUpdate u,
      MapEntry<String, RecordFieldDef> c,
      bool dated,
    ) {
      final raw = u.values[c.value.key];
      if (raw == null || raw.trim().isEmpty) return '';
      final original =
          u.definitions[c.value.key] ??
          RecordFieldDef(key: c.value.key, label: c.value.key, hint: '');
      if (_identity(original) != c.key) return '';
      return dated ? '$raw\n${date(u.observedAt)}' : raw;
    }

    String latest(String id, MapEntry<String, RecordFieldDef> c) {
      final candidates = updates.where((u) => u.patientId == id &&
        u.values.containsKey(c.value.key) &&
        u.definitions[c.value.key] != null &&
        _identity(u.definitions[c.value.key]!) == c.key).toList();
      if (c.value.patientDetail) {
        candidates.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
        // An explicitly cleared patient detail must not resurrect an older value.
        return candidates.isEmpty ? '' : value(candidates.first, c, false);
      }
      return candidates.map((u) => value(u, c, true))
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    }

    final rows = <List<String>>[];
    final ids = <String>[];
    if (history) {
      for (final u in updates) {
        final p = patients.firstWhere((p) => p.id == u.patientId);
        rows.add([
          p.name,
          p.reference,
          p.facility,
          p.id,
          date(u.observedAt),
          u.patientDetails ? 'Patient details' : 'Dated measurement',
          u.sourceReportId,
          for (final c in columns) value(u, c, false),
        ]);
        ids.add(p.id);
      }
    } else {
      for (final p in patients) {
        rows.add([
          p.name,
          p.reference,
          p.facility,
          p.id,
          for (final c in columns)
            latest(p.id, c),
        ]);
        ids.add(p.id);
      }
    }
    return RegistryTableData(headers, rows, ids);
  }

  String toCsv() {
    String cell(String s) {
      // Prevent spreadsheet formula execution in user-entered text.
      if (RegExp(r'^\s*[=+@-]').hasMatch(s) ||
          s.startsWith('\t') ||
          s.startsWith('\r'))
        s = "'$s";
      return '"${s.replaceAll('"', '""')}"';
    }

    return '\uFEFF${[headers, ...rows].map((r) => r.map(cell).join(',')).join('\r\n')}';
  }
}
