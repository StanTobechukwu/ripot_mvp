import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/ids.dart';
import '../../records/domain/record_models.dart';

class RegistryPatient {
  final String id, name, reference, facility;
  final List<String> registryIds;
  final List<String> relatedReportIds;
  const RegistryPatient({
    required this.id,
    required this.name,
    this.reference = '',
    this.facility = '',
    this.registryIds = const [],
    this.relatedReportIds = const [],
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'reference': reference,
    'facility': facility,
    'registryIds': registryIds,
    'relatedReportIds': relatedReportIds,
  };
  factory RegistryPatient.fromJson(Map<String, dynamic> j) => RegistryPatient(
    id: j['id'] as String,
    name: j['name'] as String,
    reference: j['reference'] as String? ?? '',
    facility: j['facility'] as String? ?? '',
    registryIds: List<String>.from(j['registryIds'] as List? ?? []),
    relatedReportIds: List<String>.from(j['relatedReportIds'] as List? ?? []),
  );
}

class RegistryImageAttachment {
  final String id;
  final String ref;
  final String label;
  final String sourceReportId;

  const RegistryImageAttachment({
    required this.id,
    required this.ref,
    this.label = '',
    this.sourceReportId = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'ref': ref,
    'label': label,
    'sourceReportId': sourceReportId,
  };

  factory RegistryImageAttachment.fromJson(Map<String, dynamic> j) =>
      RegistryImageAttachment(
        id: (j['id'] ?? '').toString(),
        ref: (j['ref'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        sourceReportId: (j['sourceReportId'] ?? '').toString(),
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
  final List<RegistryImageAttachment> images;
  const RegistryUpdate({
    required this.id,
    required this.registryId,
    required this.patientId,
    required this.patientName,
    required this.observedAt,
    required this.recordedAt,
    required this.values,
    required this.definitions,
    this.images = const [],
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
    'images': images.map((image) => image.toJson()).toList(growable: false),
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
    values: Map<String, String>.from(j['values'] as Map? ?? const {}),
    definitions: (j['definitions'] as Map? ?? const {}).map(
      (k, v) => MapEntry(
        k as String,
        RecordFieldDef.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
    ),
    images: ((j['images'] as List?) ?? const [])
        .whereType<Map>()
        .map((image) => RegistryImageAttachment.fromJson(
              Map<String, dynamic>.from(image),
            ))
        .where((image) => image.id.isNotEmpty && image.ref.isNotEmpty)
        .toList(growable: false),
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
              relatedReportIds: p.relatedReportIds,
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
              relatedReportIds: p.relatedReportIds,
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
              relatedReportIds: p.relatedReportIds,
            )
          else
            p,
      ],
      updates: data.updates,
    );
  });

  Future<void> linkReport(String patientId, String reportId) => _change((data) {
    final id = reportId.trim();
    if (id.isEmpty) throw ArgumentError('Choose a report.');
    if (!data.patients.any((p) => p.id == patientId)) {
      throw StateError('Patient not found.');
    }
    if (data.patients.any(
      (p) => p.id != patientId && p.relatedReportIds.contains(id),
    )) {
      throw StateError('This report is already linked to another patient.');
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
              registryIds: p.registryIds,
              relatedReportIds: {...p.relatedReportIds, id}.toList(),
            )
          else
            p,
      ],
      updates: data.updates,
    );
  });

  Future<void> unlinkReport(String patientId, String reportId) => _change(
    (data) => RegistryData(
      patients: [
        for (final p in data.patients)
          if (p.id == patientId)
            RegistryPatient(
              id: p.id,
              name: p.name,
              reference: p.reference,
              facility: p.facility,
              registryIds: p.registryIds,
              relatedReportIds: p.relatedReportIds
                  .where((id) => id != reportId)
                  .toList(),
            )
          else
            p,
      ],
      updates: data.updates,
    ),
  );

  /// Identity and static details are committed together. Dated history and
  /// enrollments keep the same patient ID and their original snapshots.
  Future<void> editPatient({
    required RegistryPatient expected,
    required String name,
    required String reference,
    required String facility,
    RegistryUpdate? details,
  }) => _change((data) {
    final current = data.patients.firstWhere(
      (p) => p.id == expected.id,
      orElse: () => throw StateError('Patient not found.'),
    );
    if (current.name != expected.name ||
        current.reference != expected.reference ||
        current.facility != expected.facility) {
      throw StateError(
        'Patient details changed. Reopen the editor and try again.',
      );
    }
    if (name.trim().isEmpty && reference.trim().isEmpty) {
      throw ArgumentError('Enter a name or patient identifier.');
    }
    final directoryChanged =
        current.reference.trim().toLowerCase() !=
            reference.trim().toLowerCase() ||
        current.facility.trim().toLowerCase() != facility.trim().toLowerCase();
    if (directoryChanged &&
        reference.trim().isNotEmpty &&
        data.patients.any(
          (p) =>
              p.id != current.id &&
              p.reference.trim().toLowerCase() ==
                  reference.trim().toLowerCase() &&
              p.facility.trim().toLowerCase() == facility.trim().toLowerCase(),
        )) {
      throw StateError(
        'This identifier and facility already belong to another patient.',
      );
    }
    if (details != null) {
      if (!details.patientDetails ||
          details.patientId != current.id ||
          !current.registryIds.contains(details.registryId) ||
          details.sourceReportId.isNotEmpty ||
          data.updates.any((u) => u.id == details.id)) {
        throw ArgumentError('Invalid patient details revision.');
      }
      _validateValues(details);
    }
    return RegistryData(
      patients: [
        for (final p in data.patients)
          if (p.id == current.id)
            RegistryPatient(
              id: p.id,
              name: name.trim(),
              reference: reference.trim(),
              facility: facility.trim(),
              registryIds: p.registryIds,
              relatedReportIds: p.relatedReportIds,
            )
          else
            p,
      ],
      updates: [...data.updates, ?details],
    );
  });

  /// Explicitly correct one saved entry; never turn an edit into a new visit,
  /// change its units, or rewrite a source report. Reject stale editors.
  Future<void> correctUpdate({
    required RegistryUpdate expected,
    required Map<String, String> values,
    required DateTime observedAt,
    List<RegistryImageAttachment>? images,
  }) => _change((data) {
    final current = data.updates.firstWhere(
      (u) =>
          u.id == expected.id &&
          u.registryId == expected.registryId &&
          u.patientId == expected.patientId,
      orElse: () => throw StateError('This entry no longer exists.'),
    );
    if (jsonEncode(current.toJson()) != jsonEncode(expected.toJson())) {
      throw StateError(
        'This entry changed. Reopen it before making a correction.',
      );
    }
    if (values.keys.any((key) => !current.values.containsKey(key))) {
      throw ArgumentError('Use a new update to add another field.');
    }
    final corrected = RegistryUpdate(
      id: current.id,
      registryId: current.registryId,
      patientId: current.patientId,
      patientName: current.patientName,
      observedAt: current.patientDetails ? current.observedAt : observedAt,
      recordedAt: current.recordedAt,
      patientDetails: current.patientDetails,
      sourceReportId: current.sourceReportId,
      values: values,
      definitions: current.definitions,
      images: images ?? current.images,
    );
    _validateValues(corrected);
    return RegistryData(
      patients: data.patients,
      updates: [
        for (final u in data.updates)
          if (u.id == current.id) corrected else u,
      ],
    );
  });

  static void _validateValues(RegistryUpdate update) {
    if (update.values.isEmpty && update.images.isEmpty) {
      throw ArgumentError('Enter at least one value or add an image.');
    }
    for (final entry in update.values.entries) {
      final def = update.definitions[entry.key];
      if (def == null) throw ArgumentError('Missing field definition.');
      if (update.patientDetails != def.patientDetail) {
        throw ArgumentError(
          'Patient details and dated values must be saved separately.',
        );
      }
      if (update.patientDetails && entry.value.trim().isEmpty) continue;
      final number = double.tryParse(entry.value);
      if (def.inputType == RecordInputType.numeric &&
          (number == null || !number.isFinite)) {
        throw ArgumentError('${def.label} must be a number.');
      }
    }
  }

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
    if (data.updates.any((u) => u.id == update.id)) return data;
    if (update.sourceReportId.isNotEmpty &&
        (data.patients.any(
              (p) =>
                  p.id != update.patientId &&
                  p.relatedReportIds.contains(update.sourceReportId),
            ) ||
            data.updates.any(
              (u) =>
                  u.patientId != update.patientId &&
                  u.sourceReportId == update.sourceReportId,
            ))) {
      throw StateError(
        'This report is already linked to another patient.',
      );
    }
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
    _validateValues(update);
    final linkedPatients = update.sourceReportId.isEmpty
        ? data.patients
        : [
            for (final p in data.patients)
              if (p.id == update.patientId)
                RegistryPatient(
                  id: p.id,
                  name: p.name,
                  reference: p.reference,
                  facility: p.facility,
                  registryIds: p.registryIds,
                  relatedReportIds: {
                    ...p.relatedReportIds,
                    update.sourceReportId,
                  }.toList(),
                )
              else
                p,
          ];
    return RegistryData(
      patients: linkedPatients,
      updates: [...data.updates, update],
    );
  });
}
