import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/utils/ids.dart';
import '../domain/logbook_models.dart';
import 'logbook_storage.dart';

class LogbookRepository extends ChangeNotifier {
  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  LogbookRepository({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
  }) : _read = read ?? LogbookStorage().read,
       _write = write ?? LogbookStorage().write;
  LogbookData _data = LogbookData();
  LogbookData get data => _data;
  bool loaded = false;
  String? error;
  Future<void> _queue = Future.value();
  Future<void> _serial(Future<void> Function() operation) {
    final next = _queue.then((_) => operation());
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<void> load() => _serial(() async {
    if (loaded) return;
    try {
      final raw = await _read();
      _data = raw == null
          ? LogbookData()
          : LogbookData.fromJson(object(jsonDecode(raw)));
      loaded = true;
      error = null;
    } catch (_) {
      error =
          'The local Logbook could not be read. Retry or restore an encrypted backup.';
    }
    notifyListeners();
  });
  Future<void> _commit(LogbookData next, {bool changed = true}) async {
    if (changed) {
      next = next.copyWith(
        sequence: _data.sequence + 1,
        dirtySince: _data.dirty ? _data.dirtySince : DateTime.now(),
      );
    }
    final encoded = jsonEncode(next.toJson());
    final validated = LogbookData.fromJson(object(jsonDecode(encoded)));
    await _write(encoded);
    _data = validated;
    loaded = true;
    error = null;
    notifyListeners();
  }

  void _ready() {
    if (!loaded) throw StateError('Load or restore the Logbook first');
  }

  Future<void> saveDoctor(LogDoctor doctor, {bool? isMe}) => _serial(() async {
    _ready();
    final doctors = [..._data.doctors];
    final i = doctors.indexWhere((d) => d.id == doctor.id);
    if (i < 0) {
      doctors.add(doctor);
    } else {
      doctors[i] = doctor;
    }
    await _commit(
      _data.copyWith(
        doctors: doctors,
        meId: isMe == true
            ? doctor.id
            : isMe == false && _data.meId == doctor.id
            ? ''
            : null,
      ),
    );
  });
  LogEntry? forReport(String reportId) {
    for (final e in _data.entries) {
      if (e.linkedReportId == reportId && reportId.isNotEmpty) return e;
    }
    return null;
  }

  Future<void> saveEntry(LogEntry entry, {int? expectedRevision}) =>
      _serial(() async {
        _ready();
        final old = _data.entry(entry.id);
        if (old != null && old.revision != expectedRevision) {
          throw StateError('This entry changed. Reopen it before editing.');
        }
        if (old == null && expectedRevision != null) {
          throw StateError('This entry was removed. Reopen Logbook.');
        }
        if (entry.linkedReportId.isNotEmpty &&
            forReport(entry.linkedReportId)?.id != null &&
            forReport(entry.linkedReportId)!.id != entry.id) {
          throw StateError('This report already has a log entry');
        }
        if (old != null &&
            jsonEncode(old.data.toJson()) == jsonEncode(entry.data.toJson())) {
          return;
        }
        final saved = LogEntry(
          id: entry.id,
          linkedReportId: old?.linkedReportId ?? entry.linkedReportId,
          createdAt: old?.createdAt ?? entry.createdAt,
          updatedAt: DateTime.now(),
          revision: old == null ? 1 : old.revision + 1,
          data: entry.data,
          signatures: old?.signatures ?? [],
        );
        await _commit(
          _data.copyWith(
            entries: [
              for (final e in _data.entries)
                if (e.id != entry.id) e,
              saved,
            ],
            createdCount: _data.createdCount + (old == null ? 1 : 0),
          ),
        );
      });
  Future<void> sign(String id, int revision, String signerId, Uint8List png) =>
      _serial(() async {
        _ready();
        final old = _data.entry(id);
        if (old == null || old.revision != revision) {
          throw StateError(
            'The entry changed. Review it again before signing.',
          );
        }
        if (old.currentSignature != null) {
          throw StateError('This version already has a signature');
        }
        final doctor = _data.doctor(signerId);
        if (doctor == null) throw StateError('Select a doctor');
        final signature = LogSignature(
          revision: revision,
          snapshot: old.data,
          doctorId: signerId,
          signerName: doctor.name,
          pngBase64: base64Encode(png),
          recordedAt: DateTime.now(),
          doctorNames: {for (final d in _data.doctors) d.id: d.name},
        );
        final signed = LogEntry(
          id: old.id,
          linkedReportId: old.linkedReportId,
          createdAt: old.createdAt,
          updatedAt: DateTime.now(),
          revision: old.revision,
          data: old.data,
          signatures: [...old.signatures, signature],
        );
        await _commit(
          _data.copyWith(
            entries: [for (final e in _data.entries) e.id == id ? signed : e],
          ),
        );
      });
  Future<void> deleteEntry(String id) => _serial(() async {
    _ready();
    await _commit(
      _data.copyWith(entries: _data.entries.where((e) => e.id != id).toList()),
    );
  });
  Future<void> snooze() => _serial(() async {
    _ready();
    await _commit(
      _data.copyWith(snoozedUntil: DateTime.now().add(const Duration(days: 1))),
      changed: false,
    );
  });
  Future<void> backupSucceeded(LogbookData snapshot) => _serial(() async {
    _ready();
    if (snapshot.sequence > _data.sequence ||
        snapshot.createdCount > _data.createdCount) {
      throw StateError('Logbook changed during backup');
    }
    await _commit(
      _data.copyWith(
        backedSequence: snapshot.sequence,
        backedCreatedCount: snapshot.createdCount,
        backedAt: DateTime.now(),
      ),
      changed: false,
    );
  });
  Future<void> restore(LogbookData snapshot) => _serial(() async {
    // Validation and one durable write precede replacing any in-memory data.
    final next = LogbookData(
      doctors: snapshot.doctors,
      entries: snapshot.entries,
      meId: snapshot.meId,
      sequence: _data.sequence + 1,
      createdCount: snapshot.createdCount,
      dirtySince: DateTime.now(),
    );
    await _commit(next, changed: false);
  });
  LogEntry draft(LogData data, {String linkedReportId = ''}) => LogEntry(
    id: newId('log'),
    linkedReportId: linkedReportId,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    data: data,
  );
}
