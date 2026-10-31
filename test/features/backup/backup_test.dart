import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/features/backup/data/backup_cipher.dart';
import 'package:ripot/features/backup/data/backup_schedule.dart';
import 'package:ripot/features/backup/data/backup_service.dart';
import 'package:ripot/features/backup/data/backup_snapshot.dart';
import 'package:ripot/features/backup/platform/backup_destination.dart';
import 'package:ripot/features/backup/platform/backup_local.dart';
import 'package:ripot/features/logbook/data/logbook_storage.dart';
import 'package:ripot/features/logbook/domain/logbook_models.dart';
import 'package:ripot/features/reports/data/reports_repository.dart';
import 'package:ripot/features/reports/data/pdf_file_store.dart';
import 'package:ripot/features/reports/domain/models/report_doc.dart';
import 'package:ripot/features/reports/domain/serialization/report_codec.dart';
import 'package:ripot/features/reports/services/platforms/file_loader.dart';
import 'package:ripot/features/records/domain/record_models.dart';

Map<String, dynamic> report(String id, {String title = 'Fictional test'}) =>
    ReportCodec.reportToJson(
      ReportDoc(
        reportId: id,
        createdAtIso: '2026-10-26',
        updatedAtIso: '2026-10-26',
        reportTitle: title,
      ),
    );

class TestDestination extends BackupDestination {
  bool locked = false, fail = false;
  int writes = 0;
  String? selected = 'Test folder';
  @override
  bool get supported => true;
  @override
  bool get needsDownloadConfirmation => false;
  @override
  Future<bool> acquire() async {
    if (locked) return false;
    locked = true;
    return true;
  }

  @override
  Future<void> release() async {
    locked = false;
  }

  @override
  Future<String?> choose() async => selected;
  @override
  Future<String?> location() async => selected;
  @override
  Future<String> write(Uint8List bytes, String scope, int keep) async {
    if (fail) throw StateError('Test disk full');
    writes++;
    return 'Ripot-$scope-test.ripotbackup';
  }
}

class ForegroundBackupService extends BackupService {
  ForegroundBackupService({required super.destination, Future<bool> Function()? automaticAccess})
    : super(automaticAccess: automaticAccess ?? (() async => true));
  @override
  bool get backgroundAndroid => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Free cannot enable automatic backup, but can disable an old schedule',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final service = ForegroundBackupService(
        destination: TestDestination(),
        automaticAccess: () async => false,
      );
      await expectLater(
        service.configure(
          const BackupSchedule(enabled: true),
          'fictional password',
        ),
        throwsStateError,
      );
      await service.configure(const BackupSchedule(enabled: false), null);
      expect((await service.schedule()).enabled, false);
    },
  );
  late Directory dir;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('ripot-backup-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => dir.path,
        );
  });
  tearDown(() async {
    await dir.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });
  test(
    'encrypted envelope round trip rejects wrong passphrase and tampering',
    () async {
      final data = {
        'format': 'test',
        'reports': ['fictional'],
      };
      final bytes = await BackupCipher.encrypt(data, 'a long test passphrase');
      expect(utf8.decode(bytes), isNot(contains('fictional')));
      expect(await BackupCipher.decrypt(bytes, 'a long test passphrase'), data);
      await expectLater(
        BackupCipher.decrypt(bytes, 'wrong passphrase'),
        throwsA(anything),
      );
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final ciphertext = base64Decode(j['ciphertext'] as String);
      ciphertext[0] ^= 1;
      j['ciphertext'] = base64Encode(ciphertext);
      await expectLater(
        BackupCipher.decrypt(
          Uint8List.fromList(utf8.encode(jsonEncode(j))),
          'a long test passphrase',
        ),
        throwsA(anything),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test('daily and weekly schedules catch up once without time drift', () {
    const daily = BackupSchedule(enabled: true, hour: 20, minute: 30);
    expect(
      daily.nextAfter(DateTime(2026, 10, 26, 20, 29)),
      DateTime(2026, 10, 26, 20, 30),
    );
    expect(
      daily.nextAfter(DateTime(2026, 10, 26, 20, 30)),
      DateTime(2026, 10, 27, 20, 30),
    );
    const weekly = BackupSchedule(enabled: true, hour: 9, weekday: 1);
    expect(
      weekly.nextAfter(DateTime(2026, 10, 26, 10)),
      DateTime(2026, 11, 2, 9),
    );
    final due = BackupSchedule(
      enabled: true,
      hour: 20,
      nextDue: DateTime(2026, 10, 20, 20),
    );
    expect(due.due(DateTime(2026, 10, 26)), isTrue);
    expect(
      due.advance(DateTime(2026, 10, 26)).nextDue,
      DateTime(2026, 10, 26, 20),
    );
  });
  test(
    'retention and manual backup preserve the automatic due time',
    () async {
      final schedule = BackupSchedule(
        enabled: true,
        hour: 8,
        minute: 15,
        nextDue: DateTime(2026, 10, 27, 8, 15),
      );
      SharedPreferences.setMockInitialValues({
        'backup.schedule.v1': jsonEncode(schedule.toJson()),
      });
      final destination = TestDestination(),
          service = BackupService(
            destination: TestDestination(),
            automaticAccess: () async => true,
          );
      await service.setRetention(7);
      expect((await service.schedule()).keep, 7);
      expect((await service.schedule()).nextDue, schedule.nextDue!.toUtc());
      expect((await service.schedule()).enabled, isTrue);
      final manual = BackupService(
        destination: destination,
        automaticAccess: () async => true,
      );
      await manual.backUp(BackupScope.all, 'a long test passphrase', 7);
      expect((await manual.schedule()).nextDue, schedule.nextDue!.toUtc());
      expect(destination.locked, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getString('backup.last.all'),
        isNotNull,
      );
      final last = (await SharedPreferences.getInstance()).getString(
        'backup.last.all',
      );
      destination.fail = true;
      await expectLater(
        manual.backUp(BackupScope.all, 'a long test passphrase', 7),
        throwsStateError,
      );
      expect(
        (await SharedPreferences.getInstance()).getString('backup.last.all'),
        last,
      );
      expect((await manual.schedule()).nextDue, schedule.nextDue!.toUtc());
      expect(destination.locked, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'automatic backup skips unchanged data and retries failures without advancing',
    () async {
      final destination = TestDestination();
      final service = ForegroundBackupService(destination: destination);
      await service.configure(
        const BackupSchedule(enabled: true, hour: 8),
        'a long test passphrase',
      );
      final p = await SharedPreferences.getInstance();
      final overdue = BackupSchedule(
        enabled: true,
        hour: 8,
        nextDue: DateTime.now().subtract(const Duration(days: 1)),
      );
      Future<void> makeDue() async {
        await p.setString('backup.schedule.v1', jsonEncode(overdue.toJson()));
      }

      await makeDue();
      await service.runIfDue();
      expect(destination.writes, 1);
      expect(
        (await service.schedule()).nextDue!.isAfter(DateTime.now()),
        isTrue,
      );
      await makeDue();
      await service.runIfDue();
      expect(destination.writes, 1);
      expect(
        (await service.schedule()).nextDue!.isAfter(DateTime.now()),
        isTrue,
      );
      await p.setStringList('reports.index', ['r']);
      await p.setString('reports.doc.r', jsonEncode(report('r')));
      destination.fail = true;
      await makeDue();
      await service.runIfDue();
      expect((await service.schedule()).nextDue, overdue.nextDue!.toUtc());
      expect(p.getString('backup.error'), isNotNull);
      expect(p.getString('backup.retryAfter'), isNotNull);
      expect(destination.locked, isFalse);
      await service.configure(const BackupSchedule(enabled: false), '');
      expect((await service.schedule()).enabled, isFalse);
      expect(
        await const FlutterSecureStorage().read(
          key: 'ripot.automaticBackup.passphrase.v1',
        ),
        isNull,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'choosing a folder invalidates old baseline but cancellation keeps it',
    () async {
      SharedPreferences.setMockInitialValues({
        'backup.baseline': 'old',
        'backup.retryAfter': 'later',
      });
      final destination = TestDestination()..selected = null;
      final service = BackupService(
        destination: destination,
        automaticAccess: () async => true,
      );
      await service.chooseFolder();
      final p = await SharedPreferences.getInstance();
      expect(p.getString('backup.baseline'), 'old');
      destination.selected = 'Another folder';
      await service.chooseFolder();
      expect(p.getString('backup.baseline'), isNull);
      expect(p.getString('backup.retryAfter'), isNull);
    },
  );
  test(
    'schedule edits reuse the stored password and refuse a missing password',
    () async {
      final destination = TestDestination();
      final service = ForegroundBackupService(destination: destination);
      const secure = FlutterSecureStorage();
      const key = 'ripot.automaticBackup.passphrase.v1';
      const password = 'a long test passphrase';
      await expectLater(
        service.configure(const BackupSchedule(enabled: true), null),
        throwsStateError,
      );
      await service.configure(const BackupSchedule(enabled: true), password);
      await service.configure(
        const BackupSchedule(enabled: true, hour: 9, weekday: 1),
        null,
      );
      expect(await secure.read(key: key), password);
      final saved = await service.schedule();
      expect(saved.hour, 9);
      expect(saved.weekday, 1);
      await secure.delete(key: key);
      await expectLater(
        service.configure(const BackupSchedule(enabled: true, hour: 10), null),
        throwsStateError,
      );
      expect((await service.schedule()).toJson(), saved.toJson());
      expect(destination.locked, isFalse);
    },
  );
  test(
    'full snapshot restores editable data, native PDFs, attachments and links',
    () async {
      final image = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
      final attachment = File('${dir.path}/image.png');
      await attachment.writeAsBytes(image);
      final r = report('report-1')
        ..['images'] = [
          {'id': 'image', 'filePath': attachment.path, 'label': 'Fictional'},
        ]
        ..['signature'] = {
          'signatureFilePath': attachment.path,
          'name': 'Example',
        };
      final record = RecordEntry(
        recordEntryId: 'record-1',
        linkedReportId: 'report-1',
        createdAtIso: '2026-10-26',
        updatedAtIso: '2026-10-26',
        values: const {
          'ref': 'ordinary clinical text',
          'filePath': 'also ordinary text',
        },
      );
      SharedPreferences.setMockInitialValues({
        'reports.index': ['report-1'],
        'reports.doc.report-1': jsonEncode(r),
        'reports.finalized.report-1': true,
        'records.index': ['record-1'],
        'records.doc.record-1': record.encode(),
        'records.byreport.report-1': 'record-1',
        'letterheads.index': ['letter-1'],
        'letterheads.doc.letter-1': jsonEncode({
          'letterheadId': 'letter-1',
          'name': 'Example',
          'logoFilePath': attachment.path,
        }),
        'templates.index': ['template-1'],
        'templates.doc.template-1': jsonEncode({
          'templateId': 'template-1',
          'name': 'Example',
          'roots': [],
          'signature': {'signatureFilePath': attachment.path},
        }),
        'registry.longitudinal.v1': jsonEncode({
          'version': 2,
          'patients': [
            {
              'id': 'patient-1',
              'name': 'Example',
              'relatedReportIds': ['report-1'],
            },
          ],
          'updates': [],
        }),
        'account.secret': 'must remain local',
        'backup.schedule.v1': 'must remain local',
      });
      final pdf = Uint8List.fromList('%PDF-1.4 fictional test'.codeUnits);
      await savePdfFile('report-1', pdf);
      await LogbookStorage().write(
        jsonEncode(
          LogbookData(
            doctors: const [LogDoctor(id: 'doctor', name: 'Example')],
            meId: 'doctor',
          ).toJson(),
        ),
      );
      final snapshots = BackupSnapshots(),
          snapshot = await BackupSnapshots().capture(BackupScope.all);
      expect(snapshot.values.containsKey('account.secret'), isFalse);
      expect(snapshot.values.containsKey('backup.schedule.v1'), isFalse);
      expect(
        jsonDecode(
          snapshot.values['reports.doc.report-1'],
        )['images'][0]['filePath'],
        startsWith('data:'),
      );
      await attachment.delete();
      await deletePdfFile('report-1');
      SharedPreferences.setMockInitialValues({
        'account.secret': 'still signed in',
        'reports.index': ['newer'],
        'reports.doc.newer': jsonEncode(report('newer')),
      });
      await snapshots.restore(snapshot);
      final restored = await ReportsRepository().loadReport('report-1');
      expect(restored.reportTitle, 'Fictional test');
      expect(await readFileBytes(restored.images.single.filePath), image);
      expect(await ReportsRepository().loadPdfBytesForReport('report-1'), pdf);
      final p = await SharedPreferences.getInstance();
      expect(p.getString('account.secret'), 'still signed in');
      expect(p.getString('reports.doc.newer'), isNull);
      expect(
        RecordEntry.decode(p.getString('records.doc.record-1')!).linkedReportId,
        'report-1',
      );
      expect(
        RecordEntry.decode(p.getString('records.doc.record-1')!).values['ref'],
        'ordinary clinical text',
      );
      expect(
        jsonDecode(
          p.getString('registry.longitudinal.v1')!,
        )['patients'][0]['relatedReportIds'],
        ['report-1'],
      );
      expect(
        LogbookData.fromJson(jsonDecode((await LogbookStorage().read())!)).meId,
        'doctor',
      );
      expect(await readRestoreJournal(), isNull);
    },
  );
  test(
    'missing attachment refuses backup instead of silently losing it',
    () async {
      final r = report('r')
        ..['images'] = [
          {'id': 'missing', 'filePath': '/missing/file.png', 'label': ''},
        ];
      SharedPreferences.setMockInitialValues({
        'reports.index': ['r'],
        'reports.doc.r': jsonEncode(r),
      });
      await expectLater(
        BackupSnapshots().capture(BackupScope.all),
        throwsFormatException,
      );
    },
  );
  test(
    'foreign attachment paths and mismatched IDs cannot mutate local data',
    () async {
      final p = await SharedPreferences.getInstance();
      await p.setString('untouched', 'yes');
      final r = report('r')
        ..['images'] = [
          {'id': 'file', 'filePath': '/etc/passwd', 'label': ''},
        ];
      final s = BackupSnapshot(
        scope: BackupScope.all,
        createdAt: DateTime.now(),
        values: {
          'reports.index': ['r'],
          'reports.doc.r': jsonEncode(r),
        },
      );
      await expectLater(BackupSnapshots().restore(s), throwsFormatException);
      expect(p.getString('untouched'), 'yes');
      expect(p.getStringList('reports.index'), isNull);
      s.values['reports.doc.r'] = jsonEncode(report('wrong'));
      expect(() => BackupSnapshot.parse(s.toJson()), throwsFormatException);
    },
  );
  test(
    'modular restore adds missing reports and keeps a newer existing draft',
    () async {
      SharedPreferences.setMockInitialValues({
        'reports.index': ['same', 'new'],
        'reports.doc.same': jsonEncode(report('same', title: 'Current draft')),
        'reports.doc.new': jsonEncode(report('new')),
      });
      final s = BackupSnapshot(
        scope: BackupScope.reports,
        createdAt: DateTime.now(),
        values: {
          'reports.index': ['same', 'old'],
          'reports.doc.same': jsonEncode(
            report('same', title: 'Old finalized report'),
          ),
          'reports.doc.old': jsonEncode(report('old')),
          'reports.finalized.same': true,
          'reports.pdf.same': base64Encode('%PDF-old'.codeUnits),
        },
      );
      await BackupSnapshots().restore(s);
      final p = await SharedPreferences.getInstance();
      expect(
        p.getStringList('reports.index'),
        containsAll(['same', 'new', 'old']),
      );
      expect(
        (await ReportsRepository().loadReport('same')).reportTitle,
        'Current draft',
      );
      expect(p.getBool('reports.finalized.same'), isNull);
      expect(p.getString('reports.pdf.same'), isNull);
    },
  );
  test(
    'section restore preserves current record links and skips a duplicate report record',
    () async {
      RecordEntry entry(String id, String reportId) => RecordEntry(
        recordEntryId: id,
        linkedReportId: reportId,
        values: const {},
        createdAtIso: '2026-10-26',
        updatedAtIso: '2026-10-26',
      );
      SharedPreferences.setMockInitialValues({
        'records.index': ['existing'],
        'records.doc.existing': entry('existing', 'current-report').encode(),
        'records.byreport.current-report': 'existing',
      });
      final incoming = BackupSnapshot(
        scope: BackupScope.records,
        createdAt: DateTime.now(),
        values: {
          'records.index': ['existing', 'duplicate', 'missing'],
          'records.doc.existing': entry('existing', 'old-report').encode(),
          'records.doc.duplicate': entry(
            'duplicate',
            'current-report',
          ).encode(),
          'records.doc.missing': entry('missing', 'other-report').encode(),
          'records.byreport.old-report': 'existing',
          'records.byreport.current-report': 'duplicate',
          'records.byreport.other-report': 'missing',
        },
      );
      await BackupSnapshots().restore(incoming);
      final p = await SharedPreferences.getInstance();
      expect(p.getStringList('records.index'), ['existing', 'missing']);
      expect(p.getString('records.byreport.current-report'), 'existing');
      expect(p.getString('records.byreport.old-report'), isNull);
      expect(p.getString('records.doc.duplicate'), isNull);
      expect(p.getString('records.byreport.other-report'), 'missing');
    },
  );
  test(
    'startup recovery returns the complete before-state after an interrupted restore',
    () async {
      SharedPreferences.setMockInitialValues({
        'reports.index': ['before'],
        'reports.doc.before': jsonEncode(report('before')),
      });
      final snapshots = BackupSnapshots(),
          before = await BackupSnapshots().capture(BackupScope.all);
      await writeRestoreJournal(jsonEncode(before.toJson()));
      final p = await SharedPreferences.getInstance();
      await p.remove('reports.doc.before');
      await p.setStringList('reports.index', ['partial']);
      await snapshots.recover();
      expect(p.getStringList('reports.index'), ['before']);
      expect(await readRestoreJournal(), isNull);
    },
  );
  test(
    'retention removes only owned copies of the same scope after verification',
    () async {
      final bytes = Uint8List.fromList('encrypted fixture'.codeUnits);
      final unrelated = File('${dir.path}/Ripot-all-unowned.ripotbackup');
      await unrelated.writeAsString('keep');
      for (var n = 0; n < 6; n++) {
        await writeManagedBackup(
          dir,
          bytes,
          'all',
          3,
          'Ripot-all-20261026-$n.ripotbackup',
        );
      }
      await writeManagedBackup(
        dir,
        bytes,
        'reports',
        3,
        'Ripot-reports-20261026-1.ripotbackup',
      );
      expect(await unrelated.exists(), isTrue);
      expect(
        await File('${dir.path}/Ripot-reports-20261026-1.ripotbackup').exists(),
        isTrue,
      );
      expect(
        await File('${dir.path}/Ripot-all-20261026-0.ripotbackup').exists(),
        isFalse,
      );
      expect(
        await File(
          '${dir.path}/Ripot-all-20261026-5.ripotbackup',
        ).readAsBytes(),
        bytes,
      );
      await expectLater(
        writeManagedBackup(dir, bytes, 'all', 3, '../outside.ripotbackup'),
        throwsStateError,
      );
      await expectLater(
        writeManagedBackup(
          dir,
          bytes,
          'all',
          3,
          'Ripot-all-20261026-5.ripotbackup',
        ),
        throwsStateError,
      );
      expect(
        await File('${dir.path}/Ripot-all-20261026-3.ripotbackup').exists(),
        isTrue,
      );
    },
  );
}
