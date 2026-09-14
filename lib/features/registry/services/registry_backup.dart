import '../../records/domain/record_models.dart';
import '../../records/data/records_repository.dart';
import '../../../core/utils/ids.dart';
import '../data/registry_repository.dart';

class RegistrySnapshot {
  final RecordRegistry registry;
  final RegistryData data;
  const RegistrySnapshot(this.registry, this.data);
  Map<String, dynamic> toJson() => {
    'format': 'ripot-registry-snapshot',
    'version': 1,
    'registry': registry.toJson(),
    'patients': data.patients.map((p) => p.toJson()).toList(),
    'updates': data.updates.map((u) => u.toJson()).toList(),
  };

  factory RegistrySnapshot.parse(Map<String, dynamic> json) {
    if (json['format'] != 'ripot-registry-snapshot' || json['version'] != 1) {
      throw const FormatException('Unsupported Registry backup');
    }
    final r = RecordRegistry.fromJson(
      Map<String, dynamic>.from(json['registry'] as Map),
    );
    final patients = (json['patients'] as List)
        .map(
          (p) => RegistryPatient.fromJson(Map<String, dynamic>.from(p as Map)),
        )
        .toList();
    final updates = (json['updates'] as List)
        .map(
          (u) => RegistryUpdate.fromJson(Map<String, dynamic>.from(u as Map)),
        )
        .toList();
    if (r.registryId.isEmpty ||
        r.title.trim().isEmpty ||
        patients.any(
          (p) => p.id.isEmpty || !p.registryIds.contains(r.registryId),
        ) ||
        patients.map((p) => p.id).toSet().length != patients.length ||
        updates.map((u) => u.id).toSet().length != updates.length ||
        r.fields.map((f) => f.key).toSet().length != r.fields.length ||
        updates.any(
          (u) =>
              u.id.isEmpty ||
              u.registryId != r.registryId ||
              !patients.any((p) => p.id == u.patientId) ||
              u.values.keys.any((k) => !u.definitions.containsKey(k)),
        )) {
      throw const FormatException(
        'Registry backup has invalid links or duplicate identifiers',
      );
    }
    return RegistrySnapshot(
      r,
      RegistryData(patients: patients, updates: updates),
    );
  }

  static Future<RegistrySnapshot> capture(RecordRegistry registry) async {
    final all = await RegistryRepository().load();
    return RegistrySnapshot(
      registry,
      RegistryData(
        patients: [
          for (final p in all.patients.where(
            (p) => p.registryIds.contains(registry.registryId),
          ))
            RegistryPatient(
              id: p.id,
              name: p.name,
              reference: p.reference,
              facility: p.facility,
              registryIds: [registry.registryId],
            ),
        ],
        updates: all.updates
            .where((u) => u.registryId == registry.registryId)
            .toList(),
      ),
    );
  }

  Future<RecordRegistry> restoreCopy(RecordsRepository records) async {
    // Validate again before any write, including direct service callers.
    RegistrySnapshot.parse(toJson());
    final created = await records.createRegistry(
      title: '${registry.title} (restored)',
      description: registry.description,
    );
    try {
      final fields = [
        for (final f in registry.fields)
          f.copyWith(registryId: created.registryId),
      ];
      await records.saveRegistryFields(created.registryId, fields);
      final ids = {for (final p in data.patients) p.id: newId('patient')};
      final copy = RegistryData(
        patients: [
          for (final p in data.patients)
            RegistryPatient(
              id: ids[p.id]!,
              name: p.name,
              reference: p.reference,
              facility: p.facility,
              registryIds: [created.registryId],
            ),
        ],
        updates: [
          for (final u in data.updates)
            RegistryUpdate(
              id: newId('observation'),
              registryId: created.registryId,
              patientId: ids[u.patientId]!,
              patientName: u.patientName,
              sourceReportId: u.sourceReportId,
              observedAt: u.observedAt,
              recordedAt: u.recordedAt,
              values: u.values,
              definitions: u.definitions.map(
                (k, f) =>
                    MapEntry(k, f.copyWith(registryId: created.registryId)),
              ),
            ),
        ],
      );
      await RegistryRepository().importCopy(copy);
      return created.copyWith(fields: fields);
    } catch (_) {
      await records.deleteRegistry(created.registryId);
      rethrow;
    }
  }
}
