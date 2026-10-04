import 'dart:convert';
import 'dart:typed_data';

import '../../records/domain/record_models.dart';
import '../../records/data/records_repository.dart';
import '../../reports/services/media_ref.dart';
import '../../reports/services/platforms/file_loader.dart';
import '../../../core/utils/ids.dart';
import '../data/registry_repository.dart';

class RegistrySnapshot {
  final RecordRegistry registry;
  final RegistryData data;

  /// Portable image payloads keyed by Registry image ID. PDFs stay outside
  /// Registry backups, but selected Registry images travel with the backup.
  final Map<String, String> media;

  const RegistrySnapshot(this.registry, this.data, {this.media = const {}});

  Map<String, dynamic> toJson() => {
    'format': 'ripot-registry-snapshot',
    'version': 3,
    'registry': registry.toJson(),
    'patients': data.patients.map((p) => p.toJson()).toList(),
    'updates': data.updates.map((u) => u.toJson()).toList(),
    'media': media,
  };

  factory RegistrySnapshot.parse(Map<String, dynamic> json) {
    if (json['format'] != 'ripot-registry-snapshot' ||
        ![1, 2, 3].contains(json['version'])) {
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
    final media = (json['media'] as Map? ?? const {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
    return RegistrySnapshot(
      r,
      RegistryData(patients: patients, updates: updates),
      media: media,
    );
  }

  static String _mimeFor(String ref, Uint8List bytes) {
    if (ref.startsWith('data:')) {
      final end = ref.indexOf(';');
      if (end > 5) return ref.substring(5, end);
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      return 'image/webp';
    }
    if (bytes.length >= 6) {
      final header = ascii.decode(bytes.sublist(0, 6), allowInvalid: true);
      if (header == 'GIF87a' || header == 'GIF89a') return 'image/gif';
    }
    return 'image/jpeg';
  }

  static String _extensionForMime(String mime) {
    switch (mime) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      default:
        return 'jpg';
    }
  }

  static Future<RegistrySnapshot> capture(RecordRegistry registry) async {
    final all = await RegistryRepository().load();
    final patients = [
      for (final p in all.patients.where(
        (p) => p.registryIds.contains(registry.registryId),
      ))
        RegistryPatient(
          id: p.id,
          name: p.name,
          reference: p.reference,
          facility: p.facility,
          registryIds: [registry.registryId],
          relatedReportIds: p.relatedReportIds,
        ),
    ];
    final updates = all.updates
        .where((u) => u.registryId == registry.registryId)
        .toList(growable: false);
    final media = <String, String>{};
    for (final update in updates) {
      for (final image in update.images) {
        if (media.containsKey(image.id)) continue;
        final bytes = await readFileBytes(image.ref);
        if (bytes == null || bytes.isEmpty) continue;
        media[image.id] = bytesToDataUri(
          bytes,
          mimeType: _mimeFor(image.ref, bytes),
        );
      }
    }
    return RegistrySnapshot(
      registry,
      RegistryData(patients: patients, updates: updates),
      media: media,
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
      final restoredImages = <String, RegistryImageAttachment>{};
      for (final update in data.updates) {
        for (final image in update.images) {
          if (restoredImages.containsKey(image.id)) continue;
          var restoredRef = image.ref;
          final portable = media[image.id];
          if (portable != null && portable.isNotEmpty) {
            final bytes = bytesFromDataUri(portable);
            if (bytes != null && bytes.isNotEmpty) {
              final mime = _mimeFor(portable, bytes);
              restoredRef = await persistBytesAsRef(
                bytes,
                fileStem: 'registry_restore_${image.id}',
                extension: _extensionForMime(mime),
                mimeType: mime,
              );
            }
          }
          restoredImages[image.id] = RegistryImageAttachment(
            id: newId('registry_image'),
            ref: restoredRef,
            label: image.label,
            sourceReportId: image.sourceReportId,
          );
        }
      }

      final copy = RegistryData(
        patients: [
          for (final p in data.patients)
            RegistryPatient(
              id: ids[p.id]!,
              name: p.name,
              reference: p.reference,
              facility: p.facility,
              registryIds: [created.registryId],
              relatedReportIds: p.relatedReportIds,
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
              patientDetails: u.patientDetails,
              observedAt: u.observedAt,
              recordedAt: u.recordedAt,
              values: u.values,
              definitions: u.definitions.map(
                (k, f) =>
                    MapEntry(k, f.copyWith(registryId: created.registryId)),
              ),
              images: [
                for (final image in u.images)
                  if (restoredImages[image.id] case final restored?)
                    restored,
              ],
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
