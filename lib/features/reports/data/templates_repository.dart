import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/firebase/sync_identity.dart';
import '../../../core/firebase/account_runtime.dart';
import '../../../core/firebase/account_session.dart';
import '../../../core/firebase/cloud_documents.dart';
import '../../access/data/access_repository.dart';
import '../domain/models/nodes.dart';
import '../domain/models/template_doc.dart';
import '../domain/serialization/template_codec.dart';
import 'built_in_templates.dart';

class TemplateSummary {
  bool get isBuiltIn => const {
    BuiltInTemplates.upperGiId,
    BuiltInTemplates.lowerGiId,
    BuiltInTemplates.ultrasoundId,
    BuiltInTemplates.echoId,
  }.contains(templateId);

  final String templateId;
  final String name;
  final String groupName;
  final DateTime updatedAt;

  const TemplateSummary({
    required this.templateId,
    required this.name,
    this.groupName = '',
    required this.updatedAt,
  });
}

class TemplatesRepository {
  TemplatesRepository({
    AccessRepository? accessRepository,
    AccountSession? session,
    CloudDocuments? documents,
  }) : _accessRepository =
           accessRepository ??
           AccessRepository(session: session, documents: documents),
       _sessionOverride = session,
       _documentsOverride = documents;

  final AccessRepository _accessRepository;
  final AccountSession? _sessionOverride;
  final CloudDocuments? _documentsOverride;
  AccountSession? get _session => _sessionOverride ?? AccountRuntime.session;
  CloudDocuments? get _documents =>
      _documentsOverride ?? AccountRuntime.documents;
  Future<SyncIdentity> _identity() =>
      SyncIdentityResolver(session: _session).resolve();

  static const _indexKey = 'templates.index';
  static const _prefix = 'templates.doc.';

  // Versioned marker.
  //
  // Once this is set, deleting a starter template will NOT cause
  // it to reappear every time the user opens Ripot.
  static const _starterSeedKey = 'templates.starter_seed.v1';
  static const _echoStarterSeedKey = 'templates.starter_echo.v1';

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

    if (!alreadySeeded) {
      final ids = await _readIndex();
      for (final template in BuiltInTemplates.all()) {
        final existing = prefs.getString(_key(template.templateId));
        if (existing != null && existing.trim().isNotEmpty) {
          if (!ids.contains(template.templateId)) ids.add(template.templateId);
          continue;
        }
        await prefs.setString(
          _key(template.templateId),
          jsonEncode(TemplateCodec.templateToJson(template)),
        );
        if (!ids.contains(template.templateId)) ids.add(template.templateId);
      }
      await _writeIndex(ids);
      await prefs.setBool(_starterSeedKey, true);
    }

    // Echo arrived after starter seed v1. Give existing installations this one
    // new starter exactly once, without re-seeding any starter they deleted.
    final echoAlreadySeeded = prefs.getBool(_echoStarterSeedKey) ?? false;
    if (echoAlreadySeeded) return;

    final echo = BuiltInTemplates.echocardiography2D();
    final ids = await _readIndex();
    final existing = prefs.getString(_key(echo.templateId));
    if (existing == null || existing.trim().isEmpty) {
      await prefs.setString(
        _key(echo.templateId),
        jsonEncode(TemplateCodec.templateToJson(echo)),
      );
    }
    if (!ids.contains(echo.templateId)) {
      ids.add(echo.templateId);
      await _writeIndex(ids);
    }
    await prefs.setBool(_echoStarterSeedKey, true);
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

    final uid = _session?.currentUser?.uid;
    final remote = await _loadRemoteTemplateOrNull(templateId);

    if (remote != null && uid != null && _session?.currentUser?.uid == uid) {
      await _cacheTemplateLocally(remote);

      return remote;
    }

    throw Exception('Template not found');
  }

  // Empty groups are local. Membership travels with the template schema.
  Future<List<String>> listGroups() async {
    final prefs = await _prefs;
    final names = <String>{
      ...prefs.getStringList('templates.groups.v1') ?? [],
      ...[
        for (final t in await listTemplates())
          if (t.groupName.isNotEmpty) t.groupName,
      ],
    };
    return names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Future<void> addGroup(String name) async {
    final names = await listGroups();
    if (name.trim().isEmpty) throw ArgumentError('Enter a group name');
    if (names.any((n) => n.toLowerCase() == name.trim().toLowerCase())) {
      throw StateError('A group with that name already exists');
    }
    final prefs = await _prefs;
    if (!await prefs.setStringList('templates.groups.v1', [
      ...names,
      name.trim(),
    ])) {
      throw StateError('Could not save group');
    }
  }

  Future<void> removeGroup(String name) async {
    // Move children first; deleting a group must never delete a template.
    for (final t in await listTemplates()) {
      if (t.groupName == name) {
        final doc = await loadTemplate(t.templateId);
        await saveTemplate(
          doc.copyWith(groupName: '', updatedAt: DateTime.now()),
        );
      }
    }
    final prefs = await _prefs;
    final names = (prefs.getStringList('templates.groups.v1') ?? [])
        .where((n) => n != name)
        .toList();
    if (!await prefs.setStringList('templates.groups.v1', names)) {
      throw StateError('Could not remove group');
    }
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
            groupName: (json['groupName'] as String?) ?? '',
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
    final documents = _documents;
    if (documents == null) {
      return const [];
    }

    try {
      final identity = await _identity();
      if (!identity.isSignedInUser) return const [];

      final query = await documents.query(
        'ripot_template_structures',
        equals: {'ownerType': identity.ownerType, 'ownerId': identity.ownerId},
      );
      if (_session?.currentUser?.uid != identity.authUid) return const [];

      return query.map((doc) {
        final data = doc.data;

        return TemplateSummary(
          templateId: data['templateId'] as String? ?? doc.id,
          name: (data['name'] as String?) ?? 'Untitled Template',
          groupName: (data['groupName'] as String?) ?? '',
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
    final documents = _documents;
    if (documents == null) {
      return null;
    }

    try {
      final identity = await _identity();
      if (!identity.isSignedInUser) return null;

      final query = await documents.query(
        'ripot_template_structures',
        equals: {
          'ownerType': identity.ownerType,
          'ownerId': identity.ownerId,
          'templateId': templateId,
        },
        limit: 1,
      );

      if (query.isEmpty || _session?.currentUser?.uid != identity.authUid) {
        return null;
      }

      final data = query.first.data;

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
    final documents = _documents;
    final uid = _session?.currentUser?.uid;
    if (documents == null || uid == null) {
      return;
    }

    try {
      final access = await _accessRepository.load(refreshPlay: false);

      if (!access.isPremiumLike || _session?.currentUser?.uid != uid) {
        return;
      }

      final structureOnly = template.copyWith(
        roots: template.roots
            .map((root) => root.toTemplateNode(includeContent: false))
            .toList(growable: false),
      );

      final identity = await _identity();
      if (identity.authUid != uid) return;

      await documents.merge(
        'ripot_template_structures',
        '${identity.documentKey}_${template.templateId}',
        {
          ...TemplateCodec.templateToJson(structureOnly),
          'templateId': template.templateId,
          'ownerType': identity.ownerType,
          'ownerId': identity.ownerId,
          'ownerInstallationId': identity.installationId,
          'authUid': identity.authUid,
          'planAtSync': access.plan.name,
          'isStructureOnly': true,
          'syncedAtIso': DateTime.now().toIso8601String(),
        },
      );
    } catch (_) {
      // Cloud sync must never block
      // local template saving.
    }
  }

  Future<void> _deleteRemoteTemplate(String templateId) async {
    final documents = _documents;
    if (documents == null) {
      return;
    }

    try {
      final identity = await _identity();
      if (!identity.isSignedInUser) return;

      await documents.delete(
        'ripot_template_structures',
        '${identity.documentKey}_$templateId',
      );
    } catch (_) {}
  }

  Future<void> migrateCloudTemplatesToSignedInUser() async {
    // Windows has no legacy native-Firebase installation data. Existing local
    // templates stay local; signed-in template structures load by account UID.
    final documents = _documents;
    if (documents == null || AccountRuntime.usesWindowsRest) {
      return;
    }

    try {
      final identity = await _identity();

      if (!identity.isSignedInUser || identity.authUid == null) {
        return;
      }

      final query = await documents.query(
        'ripot_template_structures',
        equals: {
          'ownerType': 'local',
          'ownerInstallationId': identity.installationId,
        },
      );

      for (final doc in query) {
        if (_session?.currentUser?.uid != identity.authUid) return;
        final data = doc.data;

        final templateId = data['templateId'] as String?;

        if (templateId == null || templateId.trim().isEmpty) {
          continue;
        }

        await documents.merge(
          'ripot_template_structures',
          '${identity.authUid}_$templateId',
          {
            ...data,
            'ownerType': 'user',
            'ownerId': identity.authUid,
            'authUid': identity.authUid,
            'ownerInstallationId': identity.installationId,
            'migratedFromInstallationId': identity.installationId,
            'migratedAtIso': DateTime.now().toIso8601String(),
          },
        );
      }
    } catch (_) {
      // Never block template usage
      // on migration attempts.
    }
  }
}
