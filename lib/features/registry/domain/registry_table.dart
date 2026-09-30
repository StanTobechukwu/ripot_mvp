import '../data/registry_repository.dart';
import '../../records/domain/record_models.dart';

class RegistryTableCell {
  final String patientId;
  final RecordFieldDef field;
  final RegistryUpdate? update;
  final bool correction;
  const RegistryTableCell({
    required this.patientId,
    required this.field,
    required this.update,
    required this.correction,
  });
}

class RegistryTableData {
  final List<String> headers;
  final List<List<String>> rows;
  final List<String> patientIds;
  final List<RecordFieldDef?> fields;
  final List<bool> currentFields;
  final List<List<RegistryUpdate?>> cellUpdates;
  final bool history;
  const RegistryTableData(
    this.headers,
    this.rows,
    this.patientIds, {
    this.fields = const [],
    this.currentFields = const [],
    this.cellUpdates = const [],
    this.history = false,
  });

  RegistryTableCell? editableCell(int row, int column) {
    if (column >= fields.length || fields[column] == null) return null;
    final field = fields[column]!;
    final update = cellUpdates[row][column];
    final correction = history || !currentFields[column];
    // Unknown historical units/types must never be inferred from today's field.
    if (correction &&
        (update == null ||
            !update.values.keys.every(update.definitions.containsKey))) {
      return null;
    }
    return RegistryTableCell(
      patientId: patientIds[row],
      field: field,
      update: update,
      correction: correction,
    );
  }

  static String date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  // Labels/groups can change without hiding a value. Units, type and scope
  // remain separate: matching names are never evidence of unit conversion.
  static String fieldIdentity(RecordFieldDef f) => [
    f.key,
    f.unit,
    f.inputType.name,
    f.patientDetail.toString(),
  ].join('\u0000');

  static RecordFieldDef _definition(RegistryUpdate u, String key) =>
      u.definitions[key] ??
      RecordFieldDef(
        key: key,
        label: key,
        hint: '',
        patientDetail: u.patientDetails,
      );
  static String _savedIdentity(RegistryUpdate u, String key) =>
      '${u.definitions[key] == null ? 'unknown\u0000' : ''}${fieldIdentity(_definition(u, key))}';

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
      defs[fieldIdentity(f)] = f;
    }
    for (final u in updates) {
      for (final key in u.values.keys) {
        defs.putIfAbsent(_savedIdentity(u, key), () => _definition(u, key));
      }
    }
    final columns = defs.entries.toList()
      ..sort((a, b) {
        final group = a.value.groupName.compareTo(b.value.groupName);
        if (group != 0) return group;
        final label = a.value.label.compareTo(b.value.label);
        return label != 0 ? label : a.key.compareTo(b.key);
      });
    final current = registry.fields.map(fieldIdentity).toSet();
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
          if (c.key.startsWith('unknown\u0000'))
            'Original field settings unavailable',
          if (!current.contains(c.key) && !c.key.startsWith('unknown\u0000'))
            'Earlier field settings',
        ].where((s) => s.isNotEmpty).join('\n'),
    ];
    String value(
      RegistryUpdate u,
      MapEntry<String, RecordFieldDef> c,
      bool dated,
    ) {
      final raw = u.values[c.value.key];
      if (raw == null || raw.trim().isEmpty) return '';
      if (_savedIdentity(u, c.value.key) != c.key) return '';
      return dated ? '$raw\n${date(u.observedAt)}' : raw;
    }

    RegistryUpdate? latest(String id, MapEntry<String, RecordFieldDef> c) {
      final candidates = updates
          .where(
            (u) =>
                u.patientId == id &&
                u.values.containsKey(c.value.key) &&
                _savedIdentity(u, c.value.key) == c.key,
          )
          .toList();
      if (c.value.patientDetail) {
        candidates.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
        // An explicitly cleared patient detail must not resurrect an older value.
        return candidates.isEmpty ? null : candidates.first;
      }
      for (final u in candidates) {
        if (value(u, c, true).isNotEmpty) return u;
      }
      return null;
    }

    final rows = <List<String>>[];
    final ids = <String>[];
    final sources = <List<RegistryUpdate?>>[];
    final offset = history ? 7 : 4;
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
        sources.add([
          ...List<RegistryUpdate?>.filled(offset, null),
          for (final c in columns)
            if (u.values.containsKey(c.value.key) &&
                _savedIdentity(u, c.value.key) == c.key)
              u
            else
              null,
        ]);
      }
    } else {
      for (final p in patients) {
        final latestUpdates = [for (final c in columns) latest(p.id, c)];
        rows.add([
          p.name,
          p.reference,
          p.facility,
          p.id,
          for (var i = 0; i < columns.length; i++)
            latestUpdates[i] == null
                ? ''
                : value(
                    latestUpdates[i]!,
                    columns[i],
                    !columns[i].value.patientDetail,
                  ),
        ]);
        ids.add(p.id);
        sources.add([
          ...List<RegistryUpdate?>.filled(offset, null),
          ...latestUpdates,
        ]);
      }
    }
    return RegistryTableData(
      headers,
      rows,
      ids,
      history: history,
      fields: [
        ...List<RecordFieldDef?>.filled(offset, null),
        ...columns.map((c) => c.value),
      ],
      currentFields: [
        ...List<bool>.filled(offset, false),
        ...columns.map((c) => current.contains(c.key)),
      ],
      cellUpdates: sources,
    );
  }

  String toCsv() {
    String cell(String s) {
      // Prevent spreadsheet formula execution in user-entered text.
      if (RegExp(r'^\s*[=+@-]').hasMatch(s) ||
          s.startsWith('\t') ||
          s.startsWith('\r')) {
        s = "'$s";
      }
      return '"${s.replaceAll('"', '""')}"';
    }

    return '\uFEFF${[headers, ...rows].map((r) => r.map(cell).join(',')).join('\r\n')}';
  }
}
