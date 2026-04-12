import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/firebase/sync_identity.dart';
import '../../access/data/access_repository.dart';
import '../domain/models/template_doc.dart';
import '../domain/models/nodes.dart';
import '../domain/serialization/template_codec.dart';

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

  Future<void> saveTemplate(TemplateDoc t) async {
    final prefs = await _prefs;
    await prefs.setString(_key(t.templateId), jsonEncode(TemplateCodec.templateToJson(t)));
    final ids = await _readIndex();
    ids.remove(t.templateId);
    ids.insert(0, t.templateId);
    await _writeIndex(ids);
    await _syncStructureOnlyTemplate(t);
  }

  Future<TemplateDoc> loadTemplate(String templateId) async {
    final prefs = await _prefs;
    final text = prefs.getString(_key(templateId));
    if (text == null || text.trim().isEmpty) {
      throw Exception('Template not found');
    }
    return TemplateCodec.templateFromJson(jsonDecode(text) as Map<String, dynamic>);
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
    final prefs = await _prefs;
    final ids = await _readIndex();
    final out = <TemplateSummary>[];
    for (final id in ids) {
      final text = prefs.getString(_key(id));
      if (text == null || text.trim().isEmpty) continue;
      try {
        final j = jsonDecode(text) as Map<String, dynamic>;
        out.add(
          TemplateSummary(
            templateId: j['templateId'] as String,
            name: (j['name'] as String?) ?? 'Untitled Template',
            updatedAt: DateTime.parse(j['updatedAtIso'] as String),
          ),
        );
      } catch (_) {}
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<void> _syncStructureOnlyTemplate(TemplateDoc t) async {
    if (Firebase.apps.isEmpty) return;
    try {
      final access = await _accessRepository.load();
      if (!access.isPremiumLike) return;

      final structureOnly = t.copyWith(
        roots: t.roots.map((r) => r.toTemplateNode(includeContent: false)).toList(growable: false),
      );
      final identity = await SyncIdentityResolver().resolve();
      await FirebaseFirestore.instance
          .collection('ripot_template_structures')
          .doc('${identity.documentKey}_${t.templateId}')
          .set(
        {
          ...TemplateCodec.templateToJson(structureOnly),
          'templateId': t.templateId,
          'ownerType': identity.ownerType,
          'ownerId': identity.ownerId,
          'ownerInstallationId': identity.installationId,
          'authUid': identity.authUid,
          'planAtSync': access.plan.name,
          'isStructureOnly': true,
          'syncedAtIso': DateTime.now().toIso8601String(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // Cloud sync must not break local template saving.
    }
  }

  Future<void> _deleteRemoteTemplate(String templateId) async {
    if (Firebase.apps.isEmpty) return;
    try {
      final identity = await SyncIdentityResolver().resolve();
      await FirebaseFirestore.instance
          .collection('ripot_template_structures')
          .doc('${identity.documentKey}_$templateId')
          .delete();
    } catch (_) {}
  }

  Future<void> migrateCloudTemplatesToSignedInUser() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final identity = await SyncIdentityResolver().resolve();
      if (!identity.isSignedInUser || identity.authUid == null) return;

      final query = await FirebaseFirestore.instance
          .collection('ripot_template_structures')
          .where('ownerType', isEqualTo: 'local')
          .where('ownerInstallationId', isEqualTo: identity.installationId)
          .get();

      for (final doc in query.docs) {
        final data = doc.data();
        final templateId = data['templateId'] as String?;
        if (templateId == null || templateId.trim().isEmpty) continue;

        await FirebaseFirestore.instance
            .collection('ripot_template_structures')
            .doc('${identity.authUid}_$templateId')
            .set(
          {
            ...data,
            'ownerType': 'user',
            'ownerId': identity.authUid,
            'authUid': identity.authUid,
            'ownerInstallationId': identity.installationId,
            'migratedFromInstallationId': identity.installationId,
            'migratedAtIso': DateTime.now().toIso8601String(),
          },
          SetOptions(merge: true),
        );
      }
    } catch (_) {
      // Never block template usage on migration attempts.
    }
  }
}
