import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../logbook/data/logbook_storage.dart';
import '../../logbook/domain/logbook_models.dart';
import '../../reports/data/reports_repository.dart';
import '../../reports/domain/serialization/report_codec.dart';
import '../../reports/domain/serialization/template_codec.dart';
import '../../reports/domain/models/letterhead_template.dart';
import '../../reports/services/platforms/file_loader.dart';
import '../../reports/services/platforms/media_store.dart';
import '../../reports/data/pdf_file_store.dart';
import '../../registry/data/registry_repository.dart';
import '../../records/domain/record_models.dart';
import '../platform/backup_local.dart';

enum BackupScope { all, reports, registry, logbook, records, templates }

bool backupKey(String key, BackupScope scope) {
  final reports =
      key == 'reports.index' ||
      key == 'reports.savedSignatureBlock' ||
      [
        'reports.doc.',
        'reports.pdf.',
        'reports.pdfname.',
        'reports.finalized.',
      ].any(key.startsWith);
  final templates =
      key == 'templates.index' ||
      key == 'templates.groups.v1' ||
      key == 'templates.starter_seed.v1' ||
      key == 'templates.starter_echo.v1' ||
      key.startsWith('templates.doc.');
  final letterheads =
      key == 'letterheads.index' || key.startsWith('letterheads.doc.');
  final records =
      key == 'records.index' ||
      key == 'records.custom_fields' ||
      key == 'records.registries' ||
      [
        'records.doc.',
        'records.byreport.',
        'records.vocab.',
      ].any(key.startsWith);
  return switch (scope) {
    BackupScope.all =>
      reports ||
          templates ||
          letterheads ||
          records ||
          key == RegistryRepository.storageKey,
    BackupScope.reports => reports || letterheads,
    BackupScope.templates => templates || letterheads,
    BackupScope.registry =>
      key == RegistryRepository.storageKey || key == 'records.registries',
    BackupScope.records => records,
    BackupScope.logbook => false,
  };
}

class BackupSnapshot {
  final BackupScope scope;
  final DateTime createdAt;
  final Map<String, dynamic> values;
  final String? logbook;
  final Map<String, String> fingerprints;
  BackupSnapshot({
    required this.scope,
    required this.createdAt,
    required this.values,
    this.logbook,
    this.fingerprints = const {},
  });
  int get reports => (values['reports.index'] as List? ?? []).length;
  int get templates => (values['templates.index'] as List? ?? []).length;
  int get records => (values['records.index'] as List? ?? []).length;
  Map<String, dynamic> toJson() => {
    'format': 'ripot-snapshot',
    'version': 1,
    'scope': scope.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'values': values,
    'logbook': logbook,
    'fingerprints': fingerprints,
  };
  static BackupSnapshot parse(Map<String, dynamic> j) {
    if (j['format'] != 'ripot-snapshot' || j['version'] != 1) {
      throw const FormatException('Unsupported backup version.');
    }
    final s = BackupScope.values.byName(j['scope'] as String);
    final values = Map<String, dynamic>.from(j['values'] as Map);
    if (values.keys.any((k) => !backupKey(k, s))) {
      throw const FormatException('Backup contains unsupported settings.');
    }
    for (final e in values.entries) {
      if (e.value is! String &&
          e.value is! bool &&
          e.value is! int &&
          !(e.value is List && (e.value as List).every((v) => v is String))) {
        throw const FormatException('Invalid backup value.');
      }
      final listKey =
          e.key.endsWith('.index') ||
          e.key == 'templates.groups.v1' ||
          e.key.startsWith('records.vocab.');
      final boolKey =
          e.key.startsWith('reports.finalized.') ||
          e.key == 'templates.starter_seed.v1' ||
          e.key == 'templates.starter_echo.v1';
      if (listKey
          ? e.value is! List
          : boolKey
          ? e.value is! bool
          : e.value is! String) {
        throw const FormatException('Invalid preference type.');
      }
      if (e.key.contains('.doc.') &&
          !RegExp(
            r'^[A-Za-z0-9_-]{1,180}$',
          ).hasMatch(e.key.split('.doc.').last)) {
        throw const FormatException('Invalid document identifier.');
      }
      if (e.key.startsWith('reports.doc.') &&
          ReportCodec.reportFromJson(
                jsonDecode(e.value as String) as Map<String, dynamic>,
              ).reportId !=
              e.key.substring('reports.doc.'.length)) {
        throw const FormatException('Report identity mismatch.');
      }
      if (e.key.startsWith('templates.doc.') &&
          TemplateCodec.templateFromJson(
                jsonDecode(e.value as String) as Map<String, dynamic>,
              ).templateId !=
              e.key.substring('templates.doc.'.length)) {
        throw const FormatException('Template identity mismatch.');
      }
      if (e.key.startsWith('letterheads.doc.') &&
          LetterheadTemplate.fromJson(
                jsonDecode(e.value as String) as Map<String, dynamic>,
              ).letterheadId !=
              e.key.substring('letterheads.doc.'.length)) {
        throw const FormatException('Letterhead identity mismatch.');
      }
      if (e.key.startsWith('records.doc.') &&
          RecordEntry.decode(e.value as String).recordEntryId !=
              e.key.substring('records.doc.'.length)) {
        throw const FormatException('Record identity mismatch.');
      }
      if (e.key.startsWith('reports.pdf.')) {
        final bytes = base64Decode(e.value as String);
        if (bytes.length < 5 ||
            utf8.decode(bytes.take(5).toList()) != '%PDF-') {
          throw const FormatException('Invalid saved PDF.');
        }
      }
    }
    for (final prefix in ['reports', 'templates', 'letterheads', 'records']) {
      final ids = List<String>.from(values['$prefix.index'] as List? ?? []);
      if (ids.toSet().length != ids.length ||
          ids.any((id) => !values.containsKey('$prefix.doc.$id'))) {
        throw const FormatException('Backup document index is incomplete.');
      }
      for (final key in values.keys.where(
        (k) => k.startsWith('$prefix.doc.'),
      )) {
        if (!ids.contains(key.substring('$prefix.doc.'.length))) {
          throw const FormatException('Unindexed backup document.');
        }
      }
    }
    final reportIds = List<String>.from(values['reports.index'] as List? ?? []);
    for (final prefix in [
      'reports.pdf.',
      'reports.pdfname.',
      'reports.finalized.',
    ]) {
      if (values.keys
          .where((k) => k.startsWith(prefix))
          .any((k) => !reportIds.contains(k.substring(prefix.length)))) {
        throw const FormatException('Orphaned report metadata.');
      }
    }
    final book = j['logbook'] as String?;
    if (book != null) {
      if (s != BackupScope.all && s != BackupScope.logbook) {
        throw const FormatException('Unexpected Logbook.');
      }
      LogbookData.fromJson(jsonDecode(book) as Map<String, dynamic>);
    }
    if (values[RegistryRepository.storageKey] != null) {
      final raw =
          jsonDecode(values[RegistryRepository.storageKey] as String)
              as Map<String, dynamic>;
      if (![1, 2].contains(raw['version'])) {
        throw const FormatException('Unsupported Registry data.');
      }
      for (final p in raw['patients'] as List) {
        RegistryPatient.fromJson(Map<String, dynamic>.from(p as Map));
      }
      for (final u in raw['updates'] as List) {
        RegistryUpdate.fromJson(Map<String, dynamic>.from(u as Map));
      }
    }
    return BackupSnapshot(
      scope: s,
      createdAt: DateTime.parse(j['createdAt'] as String),
      values: values,
      logbook: book,
      fingerprints: Map<String, String>.from(j['fingerprints'] as Map? ?? {}),
    );
  }
}

class BackupSnapshots {
  BackupSnapshots({
    ReportsRepository? reports,
    LogbookStorage? logbook,
    Future<Uint8List?> Function(String)? mediaReader,
  }) : _reports = reports ?? ReportsRepository(),
       _logbook = logbook ?? LogbookStorage(),
       _readMedia = mediaReader ?? readFileBytes;
  final ReportsRepository _reports;
  final LogbookStorage _logbook;
  final Future<Uint8List?> Function(String) _readMedia;

  Future<Map<String, dynamic>> _values(BackupScope scope) async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return {
      for (final k
          in (p.getKeys().where((k) => backupKey(k, scope)).toList()..sort()))
        k: p.get(k),
    };
  }

  Map<String, String> _fingerprints(
    Map<String, dynamic> values,
    String? book,
  ) => {
    for (final e in values.entries)
      e.key: sha256.convert(utf8.encode(jsonEncode(e.value))).toString(),
    if (book != null) 'logbook': sha256.convert(utf8.encode(book)).toString(),
  };
  Future<Map<String, String>> inventory() async {
    final values = await _values(BackupScope.all);
    for (final id in values['reports.index'] as List? ?? []) {
      final pdf = await _reports.loadPdfBytesForReport(id as String);
      if (pdf != null) values['reports.pdf.$id'] = base64Encode(pdf);
    }
    return _fingerprints(values, await _logbook.read());
  }

  // Touch only attachment fields in known schemas. A custom clinical field
  // named "ref" or "filePath" must remain ordinary text.
  Future<dynamic> _portableValue(
    String key,
    dynamic value, {
    bool restoring = false,
  }) async {
    if (value is! String) return value;
    final relevant =
        key.startsWith('reports.doc.') ||
        key.startsWith('templates.doc.') ||
        key.startsWith('letterheads.doc.') ||
        key == RegistryRepository.storageKey ||
        key == 'reports.savedSignatureBlock';
    if (!relevant) return value;
    final j = jsonDecode(value) as Map<String, dynamic>;
    Future<void> media(Map node, String field) async {
      final path = node[field];
      if (path == null || path == '') return;
      if (path is! String) throw const FormatException('Invalid attachment.');
      if (restoring) {
        if (!path.startsWith('data:')) {
          throw const FormatException(
            'A backup cannot reference files outside itself.',
          );
        }
        final data = UriData.parse(path),
            bytes = UriData.parse(path).contentAsBytes();
        if (bytes.isEmpty) throw const FormatException('Empty attachment.');
        node[field] = await savePortableBytes(
          Uint8List.fromList(bytes),
          fileStem: 'restore-${sha256.convert(bytes)}',
          extension: 'bin',
          mimeType: data.mimeType,
        );
      } else {
        final bytes = await _readMedia(path);
        if (bytes == null || bytes.isEmpty) {
          throw const FormatException(
            'An image, logo or signature is missing. Restore or remove the missing attachment before backing up.',
          );
        }
        node[field] =
            'data:application/octet-stream;base64,${base64Encode(bytes)}';
      }
    }

    if (key.startsWith('reports.doc.')) {
      for (final image in j['images'] as List? ?? []) {
        await media(image as Map, 'filePath');
      }
    }
    if (key.startsWith('reports.doc.') || key.startsWith('templates.doc.')) {
      if (j['signature'] is Map) {
        await media(j['signature'] as Map, 'signatureFilePath');
      }
    }
    if (key.startsWith('letterheads.doc.')) await media(j, 'logoFilePath');
    if (key == 'reports.savedSignatureBlock') {
      await media(j, 'signatureFilePath');
    }
    if (key == RegistryRepository.storageKey) {
      for (final update in j['updates'] as List? ?? []) {
        for (final image in update['images'] as List? ?? []) {
          await media(image as Map, 'ref');
        }
      }
    }
    return jsonEncode(j);
  }

  Future<BackupSnapshot> capture(BackupScope scope) async {
    final raw = await _values(scope), portable = <String, dynamic>{};
    final book = (scope == BackupScope.all || scope == BackupScope.logbook)
        ? await _logbook.read()
        : null;
    for (final e in raw.entries) {
      portable[e.key] = await _portableValue(e.key, e.value);
    }
    for (final id in List<String>.from(raw['reports.index'] as List? ?? [])) {
      final pdf = await _reports.loadPdfBytesForReport(id);
      if (pdf != null) {
        portable['reports.pdf.$id'] = base64Encode(pdf);
      } else if (raw['reports.finalized.$id'] == true) {
        throw const FormatException(
          'A saved report PDF is missing. Restore it before backing up.',
        );
      }
    }
    if (jsonEncode(raw) != jsonEncode(await _values(scope)) ||
        ((scope == BackupScope.all || scope == BackupScope.logbook) &&
            book != await _logbook.read())) {
      throw StateError(
        'Data changed during backup. Please retry after saving your work.',
      );
    }
    final s = BackupSnapshot(
      scope: scope,
      createdAt: DateTime.now(),
      values: portable,
      logbook: book,
      fingerprints: {
        ..._fingerprints({
          ...raw,
          for (final e in portable.entries.where(
            (e) => e.key.startsWith('reports.pdf.'),
          ))
            e.key: e.value,
        }, book),
        for (final e in portable.entries.where(
          (e) =>
              e.key.contains('.doc.') ||
              e.key == RegistryRepository.storageKey ||
              e.key == 'reports.savedSignatureBlock',
        ))
          'attachment-content:${e.key}': sha256
              .convert(utf8.encode(jsonEncode(e.value)))
              .toString(),
      },
    );
    return BackupSnapshot.parse(s.toJson());
  }

  Future<void> _set(SharedPreferences p, String key, dynamic value) async {
    final ok = switch (value) {
      String v => await p.setString(key, v),
      bool v => await p.setBool(key, v),
      int v => await p.setInt(key, v),
      List v => await p.setStringList(key, List<String>.from(v)),
      _ => false,
    };
    if (!ok) throw StateError('Could not save restored data.');
  }

  Future<void> _apply(BackupSnapshot s) async {
    final p = await SharedPreferences.getInstance();
    // PDFs are portable preferences until the next normal PDF save. Remove any
    // native copies with these identities so stale bytes cannot win on read.
    final ids = {
      ...p.getStringList('reports.index') ?? <String>[],
      ...List<String>.from(s.values['reports.index'] as List? ?? []),
    };
    if (s.scope == BackupScope.all || s.scope == BackupScope.reports) {
      for (final id in ids) {
        if (!RegExp(r'^[A-Za-z0-9_-]{1,180}$').hasMatch(id)) {
          throw const FormatException('Invalid local report identifier.');
        }
        await deletePdfFile(id);
      }
    }
    for (final k in p.getKeys().where((k) => backupKey(k, s.scope)).toList()) {
      if (!await p.remove(k)) throw StateError('Could not replace local data.');
    }
    for (final e in s.values.entries) {
      await _set(p, e.key, e.value);
    }
    if (s.scope == BackupScope.all || s.scope == BackupScope.logbook) {
      await _logbook.write(s.logbook ?? jsonEncode(LogbookData().toJson()));
    }
  }

  // Modular restores never overwrite existing items. Identical identifiers
  // retain the device's version, including its PDF and linked metadata.
  BackupSnapshot merge(BackupSnapshot incoming, BackupSnapshot current) {
    if (incoming.scope == BackupScope.all) return incoming;
    final values = <String, dynamic>{...incoming.values, ...current.values};
    for (final key in {...incoming.values.keys, ...current.values.keys}) {
      final a = incoming.values[key], b = current.values[key];
      if (a is List && b is List) {
        values[key] = <String>{
          ...List<String>.from(b),
          ...List<String>.from(a),
        }.toList();
      }
    }
    List<dynamic> mergeBy(List<dynamic> a, List<dynamic> b, String id) {
      final old = b.map((e) => (e as Map)[id]).toSet();
      return [...b, ...a.where((e) => !old.contains((e as Map)[id]))];
    }

    for (final key in ['records.registries', 'records.custom_fields']) {
      if (incoming.values[key] != null && current.values[key] != null) {
        values[key] = jsonEncode(
          mergeBy(
            jsonDecode(incoming.values[key] as String) as List,
            jsonDecode(current.values[key] as String) as List,
            key == 'records.custom_fields' ? 'key' : 'registryId',
          ),
        );
      }
    }
    final a = incoming.values[RegistryRepository.storageKey],
        b = current.values[RegistryRepository.storageKey];
    if (a != null && b != null) {
      final old = jsonDecode(b as String) as Map<String, dynamic>,
          added = jsonDecode(a as String) as Map<String, dynamic>;
      values[RegistryRepository.storageKey] = jsonEncode({
        ...old,
        'version': 2,
        for (final k in ['patients', 'updates'])
          k: mergeBy(added[k] as List, old[k] as List, 'id'),
      });
    }
    // Never import a historical PDF/finalization flag into an existing draft.
    for (final id in current.values['reports.index'] as List? ?? []) {
      for (final prefix in [
        'reports.pdf.',
        'reports.pdfname.',
        'reports.finalized.',
      ]) {
        if (current.values.containsKey('$prefix$id')) {
          values['$prefix$id'] = current.values['$prefix$id'];
        } else {
          values.remove('$prefix$id');
        }
      }
    }
    if (incoming.scope == BackupScope.records) {
      // The report-to-record lookup must describe the records actually kept.
      // A historical link must not reattach a current record to an old report.
      final existingIds = List<String>.from(
        current.values['records.index'] as List? ?? [],
      );
      final keptIds = <String>[...existingIds];
      final linkedReports = <String>{};
      values.removeWhere((key, _) => key.startsWith('records.byreport.'));
      for (final id in existingIds) {
        final entry = RecordEntry.decode(values['records.doc.$id'] as String);
        if (entry.linkedReportId.isNotEmpty) {
          linkedReports.add(entry.linkedReportId);
          values['records.byreport.${entry.linkedReportId}'] = id;
        }
      }
      for (final id in List<String>.from(
        incoming.values['records.index'] as List? ?? [],
      )) {
        if (existingIds.contains(id)) continue;
        final entry = RecordEntry.decode(values['records.doc.$id'] as String);
        if (entry.linkedReportId.isNotEmpty &&
            !linkedReports.add(entry.linkedReportId)) {
          values.remove('records.doc.$id');
          continue;
        }
        keptIds.add(id);
        if (entry.linkedReportId.isNotEmpty) {
          values['records.byreport.${entry.linkedReportId}'] = id;
        }
      }
      if (values.containsKey('records.index')) {
        values['records.index'] = keptIds;
      }
    }
    String? book = incoming.logbook;
    if (book != null && current.logbook != null) {
      final old = LogbookData.fromJson(
            jsonDecode(current.logbook!) as Map<String, dynamic>,
          ),
          added = LogbookData.fromJson(
            jsonDecode(book) as Map<String, dynamic>,
          );
      final ids = old.entries.map((e) => e.id).toSet(),
          links = old.entries
              .map((e) => e.linkedReportId)
              .where((id) => id.isNotEmpty)
              .toSet();
      final entries = [
        ...old.entries,
        ...added.entries.where(
          (e) =>
              !ids.contains(e.id) &&
              (e.linkedReportId.isEmpty || !links.contains(e.linkedReportId)),
        ),
      ];
      final doctors = [
        ...old.doctors,
        ...added.doctors.where((d) => !old.doctors.any((o) => o.id == d.id)),
      ];
      book = jsonEncode(
        old
            .copyWith(
              entries: entries,
              doctors: doctors,
              sequence: old.sequence + 1,
              createdCount:
                  old.createdCount + entries.length - old.entries.length,
              dirtySince: old.dirtySince ?? DateTime.now(),
              meId: old.meId.isEmpty ? added.meId : old.meId,
            )
            .toJson(),
      );
    }
    return BackupSnapshot.parse(
      BackupSnapshot(
        scope: incoming.scope,
        createdAt: incoming.createdAt,
        values: values,
        logbook: book ?? current.logbook,
      ).toJson(),
    );
  }

  Future<void> restore(BackupSnapshot input) async {
    final s = BackupSnapshot.parse(input.toJson());
    // Capture before staging. This verifies that a rollback is possible before
    // any local data changes. A missing local attachment aborts safely.
    final before = await capture(s.scope);
    final staged = <String, dynamic>{};
    for (final e in s.values.entries) {
      staged[e.key] = await _portableValue(e.key, e.value, restoring: true);
    }
    final prepared = BackupSnapshot(
      scope: s.scope,
      createdAt: s.createdAt,
      values: staged,
      logbook: s.logbook,
    );
    // Merge against raw local references so existing images and PDFs remain
    // unchanged. The separate portable rollback includes native PDF bytes.
    final current = BackupSnapshot(
      scope: s.scope,
      createdAt: before.createdAt,
      values: {
        ...await _values(s.scope),
        for (final e in before.values.entries.where(
          (e) => e.key.startsWith('reports.pdf.'),
        ))
          e.key: e.value,
      },
      logbook: before.logbook,
    );
    final target = merge(prepared, current);
    await writeRestoreJournal(jsonEncode(before.toJson()));
    try {
      await _apply(target);
      final actual = await _values(s.scope);
      if (jsonEncode(actual) !=
          jsonEncode(
            Map.fromEntries(
              target.values.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key)),
            ),
          )) {
        throw StateError('Restored data could not be verified.');
      }
      if (s.scope == BackupScope.all || s.scope == BackupScope.logbook) {
        final expected = target.logbook ?? jsonEncode(LogbookData().toJson());
        if (await _logbook.read() != expected) {
          throw StateError('Restored Logbook could not be verified.');
        }
      }
      await clearRestoreJournal();
    } catch (_) {
      await recover();
      rethrow;
    }
  }

  Future<void> recover() async {
    final raw = await readRestoreJournal();
    if (raw == null) return;
    final s = BackupSnapshot.parse(jsonDecode(raw) as Map<String, dynamic>);
    await _apply(s);
    await clearRestoreJournal();
  }
}
