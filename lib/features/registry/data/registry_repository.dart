import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/ids.dart';
import '../../records/domain/record_models.dart';

class RegistryPatient {
  final String id, name, reference, facility;
  final List<String> registryIds;
  const RegistryPatient({
    required this.id,
    required this.name,
    this.reference = '',
    this.facility = '',
    this.registryIds = const [],
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'reference': reference,
    'facility': facility,
    'registryIds': registryIds,
  };
  factory RegistryPatient.fromJson(Map<String, dynamic> j) => RegistryPatient(
    id: j['id'] as String,
    name: j['name'] as String,
    reference: j['reference'] as String? ?? '',
    facility: j['facility'] as String? ?? '',
    registryIds: List<String>.from(j['registryIds'] as List? ?? []),
  );
}

/// Each update keeps its own definitions, units and patient identity snapshot.
/// Changing a field or a patient's display name cannot rewrite old entries.
class RegistryUpdate {
  final String id, registryId, patientId, patientName, sourceReportId;
  final DateTime observedAt, recordedAt;
  final bool patientDetails;
  final Map<String, String> values;
  final Map<String, RecordFieldDef> definitions;
  const RegistryUpdate({
    required this.id,
    required this.registryId,
    required this.patientId,
    required this.patientName,
    required this.observedAt,
    required this.recordedAt,
    required this.values,
    required this.definitions,
    this.sourceReportId = '',
    this.patientDetails = false,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'registryId': registryId,
    'patientId': patientId,
    'patientName': patientName,
    'sourceReportId': sourceReportId,
    'patientDetails': patientDetails,
    'observedAt': observedAt.toIso8601String(),
    'recordedAt': recordedAt.toIso8601String(),
    'values': values,
    'definitions': definitions.map((k, v) => MapEntry(k, v.toJson())),
  };
  factory RegistryUpdate.fromJson(Map<String, dynamic> j) => RegistryUpdate(
    id: j['id'] as String,
    registryId: j['registryId'] as String,
    patientId: j['patientId'] as String,
    patientName: j['patientName'] as String,
    sourceReportId: j['sourceReportId'] as String? ?? '',
    patientDetails: j['patientDetails'] == true,
    observedAt: DateTime.parse(j['observedAt'] as String),
    recordedAt: DateTime.parse(j['recordedAt'] as String),
    values: Map<String, String>.from(j['values'] as Map),
    definitions: (j['definitions'] as Map).map(
      (k, v) => MapEntry(
        k as String,
        RecordFieldDef.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
    ),
  );
}

class RegistryData {
  final List<RegistryPatient> patients;
  final List<RegistryUpdate> updates;
  const RegistryData({this.patients = const [], this.updates = const []});
}

class RegistryRepository {
  static const storageKey = 'registry.longitudinal.v1';
  static Future<void>? _queue;

  Future<void> deleteUpdate(String registryId, String updateId) => _change(
    (data) => RegistryData(
      patients: data.patients,
      updates: data.updates
          .where((u) => !(u.registryId == registryId && u.id == updateId))
          .toList(),
    ),
  );

  Future<void> removePatient(String registryId, String patientId) => _change(
    (data) => RegistryData(
      patients: [
        for (final p in data.patients)
          if (p.id != patientId)
            p
          else if (p.registryIds.any((id) => id != registryId))
            RegistryPatient(
              id: p.id,
              name: p.name,
              reference: p.reference,
              facility: p.facility,
              registryIds: p.registryIds
                  .where((id) => id != registryId)
                  .toList(),
            ),
      ],
      updates: data.updates
          .where(
            (u) => !(u.registryId == registryId && u.patientId == patientId),
          )
          .toList(),
    ),
  );

  /// Import only newly generated identities; existing records cannot be replaced.
  Future<void> importCopy(RegistryData copy) => _change((data) {
    if (copy.patients.any((p) => data.patients.any((old) => old.id == p.id)) ||
        copy.updates.any((u) => data.updates.any((old) => old.id == u.id))) {
      throw StateError('Restore identifiers conflict. Try restoring again.');
    }
    return RegistryData(
      patients: [...data.patients, ...copy.patients],
      updates: [...data.updates, ...copy.updates],
    );
  });

  Future<RegistryData> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(storageKey);
    if (raw == null) return const RegistryData();
    final j = jsonDecode(raw) as Map<String, dynamic>;
    if (![1, 2].contains(j['version'])) {
      throw const FormatException('Unsupported Registry data version');
    }
    return RegistryData(
      patients: (j['patients'] as List)
          .map(
            (p) =>
                RegistryPatient.fromJson(Map<String, dynamic>.from(p as Map)),
          )
          .toList(),
      updates: (j['updates'] as List)
          .map(
            (p) => RegistryUpdate.fromJson(Map<String, dynamic>.from(p as Map)),
          )
          .toList(),
    );
  }

  Future<void> _change(RegistryData Function(RegistryData) edit) {
    final previous = _queue;
    final finished = Completer<void>();
    _queue = finished.future;
    return (() async {
      if (previous != null) await previous;
      try {
        final data = edit(await load());
        final ok = await (await SharedPreferences.getInstance()).setString(
          storageKey,
          jsonEncode({
            'version': 2,
            'patients': data.patients.map((p) => p.toJson()).toList(),
            'updates': data.updates.map((u) => u.toJson()).toList(),
          }),
        );
        if (!ok) throw StateError('Registry could not be saved.');
      } finally {
        if (identical(_queue, finished.future)) _queue = null;
        finished.complete();
      }
    })();
  }

  Future<RegistryPatient> addPatient({
    required String name,
    String reference = '',
    String facility = '',
    required String registryId,
  }) async {
    if (name.trim().isEmpty && reference.trim().isEmpty) {
      throw ArgumentError('Enter a name or patient identifier.');
    }
    final patient = RegistryPatient(
      id: newId('patient'),
      name: name.trim(),
      reference: reference.trim(),
      facility: facility.trim(),
      registryIds: [registryId],
    );
    await _change((data) {
      if (reference.trim().isNotEmpty &&
          data.patients.any(
            (p) =>
                p.reference.toLowerCase() == reference.trim().toLowerCase() &&
                p.facility.toLowerCase() == facility.trim().toLowerCase(),
          )) {
        throw StateError(
          'This identifier and facility already exist. Select that patient.',
        );
      }
      return RegistryData(
        patients: [...data.patients, patient],
        updates: data.updates,
      );
    });
    return patient;
  }

  Future<void> renamePatient(String patientId, String name) => _change((data) {
    if (name.trim().isEmpty) throw ArgumentError('Enter a name.');
    if (!data.patients.any((p) => p.id == patientId)) {
      throw StateError('Patient not found.');
    }
    return RegistryData(
      patients: [
        for (final p in data.patients)
          if (p.id == patientId)
            RegistryPatient(
              id: p.id,
              name: name.trim(),
              reference: p.reference,
              facility: p.facility,
              registryIds: p.registryIds,
            )
          else
            p,
      ],
      updates: data.updates,
    );
  });

  Future<void> enroll(String patientId, String registryId) => _change((data) {
    if (!data.patients.any((p) => p.id == patientId)) {
      throw StateError('Patient not found.');
    }
    return RegistryData(
      patients: [
        for (final p in data.patients)
          if (p.id == patientId)
            RegistryPatient(
              id: p.id,
              name: p.name,
              reference: p.reference,
              facility: p.facility,
              registryIds: {...p.registryIds, registryId}.toList(),
            )
          else
            p,
      ],
      updates: data.updates,
    );
  });

  Future<void> addUpdate(
    RegistryUpdate update, {
    RegistryPatient? newPatient,
  }) => _change((original) {
    var data = original;
    if (newPatient != null) {
      if (newPatient.name.trim().isEmpty &&
          newPatient.reference.trim().isEmpty) {
        throw ArgumentError('Enter a name or patient identifier.');
      }
      if (data.patients.any(
        (p) =>
            p.id == newPatient.id ||
            (newPatient.reference.isNotEmpty &&
                p.reference.toLowerCase() ==
                    newPatient.reference.toLowerCase() &&
                p.facility.toLowerCase() == newPatient.facility.toLowerCase()),
      )) {
        throw StateError(
          'Patient already exists. Select the existing patient.',
        );
      }
      data = RegistryData(
        patients: [...data.patients, newPatient],
        updates: data.updates,
      );
    }
    if (!data.patients.any(
      (p) =>
          p.id == update.patientId && p.registryIds.contains(update.registryId),
    )) {
      throw StateError('Select a patient enrolled in this registry.');
    }
    if (update.values.isEmpty) throw ArgumentError('Enter at least one value.');
    if (data.updates.any((u) => u.id == update.id)) return data;
    if (update.sourceReportId.isNotEmpty &&
        data.updates.any(
          (u) =>
              u.registryId == update.registryId &&
              u.sourceReportId == update.sourceReportId,
        )) {
      throw StateError(
        'This report is already in this registry. Open the patient history.',
      );
    }
    for (final entry in update.values.entries) {
      final def = update.definitions[entry.key];
      if (def == null) throw ArgumentError('Missing field definition.');
      final number = double.tryParse(entry.value);
      if (update.patientDetails != def.patientDetail) {
        throw ArgumentError("Patient details and dated values must be saved separately.");
      }
      if (update.patientDetails && entry.value.trim().isEmpty) continue;
      if (def.inputType == RecordInputType.numeric &&
          (number == null || !number.isFinite)) {
        throw ArgumentError('${def.label} must be a number.');
      }
    }
    return RegistryData(
      patients: data.patients,
      updates: [...data.updates, update],
    );
  });
}
