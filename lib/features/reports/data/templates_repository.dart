import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/firebase/sync_identity.dart';
import '../../access/data/access_repository.dart';
import '../domain/models/nodes.dart';
import '../domain/models/template_doc.dart';
import '../domain/serialization/template_codec.dart';
import 'built_in_templates.dart';

class TemplateSummary {
  final String templateId;
  final String name;
  final DateTime updatedAt;

  const TemplateSummary({
    required this.templateId,
    required this.name,
    required this.updatedAt,
  });
}

class TemplatesRepository {
  TemplatesRepository({AccessRepository? accessRepository})
    : _accessRepository = accessRepository ?? AccessRepository();

  final AccessRepository _accessRepository;

  static const _indexKey = 'templates.index';
  static const _prefix = 'templates.doc.';

  // Versioned marker.
  //
  // Once this is set, deleting a starter template will NOT cause
  // it to reappear every time the user opens Ripot.
  static const _starterSeedKey = 'templates.starter_seed.v1';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  String _key(String templateId) => '$_prefix$templateId';

  Future<List<String>> _readIndex() async {
    final prefs = await _prefs;

    return prefs.getStringList(_indexKey) ?? <String>[];
  }

  Future<void> _writeIndex(List<String> ids) async {
    final prefs = await _prefs;

    await prefs.setStringList(_indexKey, ids);
  }

  Future<void> _ensureStarterTemplatesSeeded() async {
    final prefs = await _prefs;

    final alreadySeeded = prefs.getBool(_starterSeedKey) ?? false;

    if (alreadySeeded) {
      return;
    }

    final ids = await _readIndex();

    for (final template in BuiltInTemplates.all()) {
      final existing = prefs.getString(_key(template.templateId));

      if (existing != null && existing.trim().isNotEmpty) {
        if (!ids.contains(template.templateId)) {
          ids.add(template.templateId);
        }

        continue;
      }

      await prefs.setString(
        _key(template.templateId),
        jsonEncode(TemplateCodec.templateToJson(template)),
      );

      if (!ids.contains(template.templateId)) {
        ids.add(template.templateId);
      }
    }

    await _writeIndex(ids);

    await prefs.setBool(_starterSeedKey, true);
  }

  Future<void> saveTemplate(TemplateDoc template) async {
    final prefs = await _prefs;

    await prefs.setString(
      _key(template.templateId),
      jsonEncode(TemplateCodec.templateToJson(template)),
    );

    final ids = await _readIndex();

    ids.remove(template.templateId);

    ids.insert(0, template.templateId);

    await _writeIndex(ids);

    // Local persistence is the Save operation. Cloud structure sync is
    // best-effort and must never make the user wait or make Save appear stuck.
    unawaited(_syncStructureOnlyTemplate(template));
  }

  Future<TemplateDoc> loadTemplate(String templateId) async {
    await _ensureStarterTemplatesSeeded();

    final local = await _loadLocalTemplateOrNull(templateId);

    if (local != null) {
      return local;
    }

    final remote = await _loadRemoteTemplateOrNull(templateId);

    if (remote != null) {
      await _cacheTemplateLocally(remote);

      return remote;
    }

    throw Exception('Template not found');
  }

  Future<void> updateTemplateRecordFieldSettings({
    required String templateId,
    required Set<String> saveToRecordsSectionIds,
  }) async {
    final template = await loadTemplate(templateId);

    SectionNode updateSection(SectionNode section) {
      return section.copyWith(
        addToRecords: saveToRecordsSectionIds.contains(section.id),
        children: section.children
            .map((child) {
              if (child is SectionNode) {
                return updateSection(child);
              }

              return child;
            })
            .toList(growable: false),
      );
    }

    final updated = template.copyWith(
      updatedAt: DateTime.now(),
      roots: template.roots.map(updateSection).toList(growable: false),
    );

    await saveTemplate(updated);
  }

  Future<void> deleteTemplate(String templateId) async {
    final prefs = await _prefs;

    await prefs.remove(_key(templateId));

    final ids = await _readIndex();

    ids.remove(templateId);

    await _writeIndex(ids);

    await _deleteRemoteTemplate(templateId);
  }

  Future<List<TemplateSummary>> listTemplates() async {
    await _ensureStarterTemplatesSeeded();

    final local = await _listLocalTemplates();

    final remote = await _listRemoteTemplates();

    final merged = <String, TemplateSummary>{
      for (final template in local) template.templateId: template,
    };

    for (final template in remote) {
      final existing = merged[template.templateId];

      if (existing == null || template.updatedAt.isAfter(existing.updatedAt)) {
        merged[template.templateId] = template;
      }
    }

    final out = merged.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return out;
  }

  Future<List<TemplateSummary>> _listLocalTemplates() async {
    final prefs = await _prefs;
    final ids = await _readIndex();

    final out = <TemplateSummary>[];

    for (final id in ids) {
      final text = prefs.getString(_key(id));

      if (text == null || text.trim().isEmpty) {
        continue;
      }

      try {
        final json = jsonDecode(text) as Map<String, dynamic>;

        out.add(
          TemplateSummary(
            templateId: json['templateId'] as String,
            name: (json['name'] as String?) ?? 'Untitled Template',
            updatedAt:
                DateTime.tryParse(json['updatedAtIso'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
      } catch (_) {}
    }

    return out;
  }

  Future<List<TemplateSummary>> _listRemoteTemplates() async {
    if (Firebase.apps.isEmpty) {
      return const [];
    }

    try {
      final identity = await SyncIdentityResolver().resolve();

      final query = await FirebaseFirestore.instance
          .collection('ripot_template_structures')
          .where('ownerType', isEqualTo: identity.ownerType)
          .where('ownerId', isEqualTo: identity.ownerId)
          .get();

      return query.docs.map((doc) {
        final data = doc.data();

        return TemplateSummary(
          templateId: data['templateId'] as String? ?? doc.id,
          name: (data['name'] as String?) ?? 'Untitled Template',
          updatedAt:
              DateTime.tryParse(data['updatedAtIso'] as String? ?? '') ??
              DateTime.tryParse(data['syncedAtIso'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<TemplateDoc?> _loadLocalTemplateOrNull(String templateId) async {
    final prefs = await _prefs;

    final text = prefs.getString(_key(templateId));

    if (text == null || text.trim().isEmpty) {
      return null;
    }

    return TemplateCodec.templateFromJson(
      jsonDecode(text) as Map<String, dynamic>,
    );
  }

  Future<TemplateDoc?> _loadRemoteTemplateOrNull(String templateId) async {
    if (Firebase.apps.isEmpty) {
      return null;
    }

    try {
      final identity = await SyncIdentityResolver().resolve();

      final query = await FirebaseFirestore.instance
          .collection('ripot_template_structures')
          .where('ownerType', isEqualTo: identity.ownerType)
          .where('ownerId', isEqualTo: identity.ownerId)
          .where('templateId', isEqualTo: templateId)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        return null;
      }

      final data = query.docs.first.data();

      return TemplateCodec.templateFromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheTemplateLocally(TemplateDoc template) async {
    final prefs = await _prefs;

    await prefs.setString(
      _key(template.templateId),
      jsonEncode(TemplateCodec.templateToJson(template)),
    );

    final ids = await _readIndex();

    ids.remove(template.templateId);

    ids.insert(0, template.templateId);

    await _writeIndex(ids);
  }

  Future<void> _syncStructureOnlyTemplate(TemplateDoc template) async {
    if (Firebase.apps.isEmpty) {
      return;
    }

    try {
      final access = await _accessRepository.load();

      if (!access.isPremiumLike) {
        return;
      }

      final structureOnly = template.copyWith(
        roots: template.roots
            .map((root) => root.toTemplateNode(includeContent: false))
            .toList(growable: false),
      );

      final identity = await SyncIdentityResolver().resolve();

      await FirebaseFirestore.instance
          .collection('ripot_template_structures')
          .doc('${identity.documentKey}_${template.templateId}')
          .set({
            ...TemplateCodec.templateToJson(structureOnly),
            'templateId': template.templateId,
            'ownerType': identity.ownerType,
            'ownerId': identity.ownerId,
            'ownerInstallationId': identity.installationId,
            'authUid': identity.authUid,
            'planAtSync': access.plan.name,
            'isStructureOnly': true,
            'syncedAtIso': DateTime.now().toIso8601String(),
          }, SetOptions(merge: true));
    } catch (_) {
      // Cloud sync must never block
      // local template saving.
    }
  }

  Future<void> _deleteRemoteTemplate(String templateId) async {
    if (Firebase.apps.isEmpty) {
      return;
    }

    try {
      final identity = await SyncIdentityResolver().resolve();

      await FirebaseFirestore.instance
          .collection('ripot_template_structures')
          .doc('${identity.documentKey}_$templateId')
          .delete();
    } catch (_) {}
  }

  Future<void> migrateCloudTemplatesToSignedInUser() async {
    if (Firebase.apps.isEmpty) {
      return;
    }

    try {
      final identity = await SyncIdentityResolver().resolve();

      if (!identity.isSignedInUser || identity.authUid == null) {
        return;
      }

      final query = await FirebaseFirestore.instance
          .collection('ripot_template_structures')
          .where('ownerType', isEqualTo: 'local')
          .where('ownerInstallationId', isEqualTo: identity.installationId)
          .get();

      for (final doc in query.docs) {
        final data = doc.data();

        final templateId = data['templateId'] as String?;

        if (templateId == null || templateId.trim().isEmpty) {
          continue;
        }

        await FirebaseFirestore.instance
            .collection('ripot_template_structures')
            .doc('${identity.authUid}_$templateId')
            .set({
              ...data,
              'ownerType': 'user',
              'ownerId': identity.authUid,
              'authUid': identity.authUid,
              'ownerInstallationId': identity.installationId,
              'migratedFromInstallationId': identity.installationId,
              'migratedAtIso': DateTime.now().toIso8601String(),
            }, SetOptions(merge: true));
      }
    } catch (_) {
      // Never block template usage
      // on migration attempts.
    }
  }
}
