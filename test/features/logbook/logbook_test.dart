import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/features/reports/data/templates_repository.dart';
import 'package:ripot/features/reports/data/reports_repository.dart';
import 'package:ripot/features/logbook/data/logbook_repository.dart';
import 'package:ripot/features/logbook/data/logbook_storage_io.dart';
import 'package:ripot/features/logbook/domain/logbook_models.dart';
import 'package:ripot/features/logbook/domain/logbook_filter.dart';
import 'package:ripot/features/logbook/services/backup_folder_io.dart';
import 'package:ripot/features/logbook/services/logbook_backup.dart';
import 'package:ripot/features/logbook/services/report_log_draft.dart';
import 'package:ripot/features/reports/domain/models/report_doc.dart';
import 'package:ripot/features/reports/domain/models/nodes.dart';
import 'package:ripot/features/reports/domain/models/template_doc.dart';
import 'package:ripot/features/reports/domain/serialization/template_codec.dart';
import 'package:ripot/features/reports/domain/serialization/report_codec.dart';

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAALQAAAA8CAIAAABATAfQAAABJ0lEQVR4nO3aQWrDMABFwVzB9z9sujCU0vLa2LFUC2b2/RHiLWzTxxPC478PwH2JgyQOkjhI4iCJgyQOkjhI4iCJgyQOkjhI4iCJgyQOkjhI4iCJgyQOkjhIA+PYts3y0stj49hZXnR5RhyXH93ynOWxzxzbD5YXWp7xQLrcpVjezXtbWehSLO9mv8oucSmWd6/GccOjWx69fCyOWx3d8onlQ394Jo4VL8XywDi+/sCKl2L5hDMPpCteiuUTzr+trHgplg9591V2xUux/KJrvnOseCmW/3TlR7Bx57Y8Z/mb67+Qjju05TnLn0Z9Ph93aMtzlp/+TZBfiIMkDpI4SOIgiYMkDpI4SOIgiYMkDpI4SOIgiYMkDpI4SOIgiYMkDpI4SOIgfQByRiC4oXJ3lAAAAABJRU5ErkJggg==',
);
LogData procedure({String name = 'Procedure', String doctor = 'd1'}) => LogData(
  procedure: name,
  procedureDate: DateTime(2026, 9, 12),
  participants: [
    LogParticipant(doctor, ProcedureRole.performer, supervised: true),
  ],
  supervisorId: 'd2',
);
Future<LogbookRepository> repository({
  Future<void> Function(String)? write,
}) async {
  final r = LogbookRepository(
    read: () async => null,
    write: write ?? (_) async {},
  );
  await r.load();
  await r.saveDoctor(const LogDoctor(id: 'd1', name: 'Dr Example'), isMe: true);
  await r.saveDoctor(const LogDoctor(id: 'd2', name: 'Dr Reviewer'));
  return r;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Removing a group keeps template IDs and definitions', () async {
    SharedPreferences.setMockInitialValues({'templates.starter_seed.v1':true, 'templates.starter_echo.v1':true});
    final repo = TemplatesRepository();
    final template = TemplateDoc(templateId:'keep-id',updatedAt:DateTime.now(),name:'Test template',groupName:'Endoscopy',roots:const [SectionNode(id:'section',title:'Findings',addToLog:true)]);
    await repo.addGroup('Endoscopy');
    await repo.saveTemplate(template);
    expect((await repo.listTemplates()).single.groupName, 'Endoscopy');
    await repo.removeGroup('Endoscopy');
    final stored = await repo.loadTemplate('keep-id');
    expect(stored.groupName,'');expect(stored.roots.single.id,'section');expect(stored.roots.single.addToLog,isTrue);
    expect(await repo.listGroups(),isEmpty);
  });
  test('Deleting a report leaves its saved log and signature intact', () async {
    SharedPreferences.setMockInitialValues({});
    final reports=ReportsRepository();
    final book=await repository();
    final report=ReportDoc(reportId:'source',createdAtIso:'2026-09-12',updatedAtIso:'2026-09-12');
    await reports.saveReport(report);
    final log=book.draft(procedure(),linkedReportId:report.reportId);await book.saveEntry(log);await book.sign(log.id,1,'d2',png);
    await reports.deleteReport(report.reportId);
    expect(book.forReport(report.reportId)!.currentSignature,isNotNull);
    expect(book.data.entries.single.data.procedure,'Procedure');
  });
  test(
    'Doctor IDs survive renaming; one report cannot create duplicate logs',
    () async {
      final r = await repository();
      final entry = r.draft(procedure(), linkedReportId: 'report');
      await r.saveEntry(entry);
      await r.saveDoctor(const LogDoctor(id: 'd1', name: 'Changed name'));
      expect(r.data.entries.single.data.participants.single.doctorId, 'd1');
      expect(filterLogbook(r.data.entries, doctorId: 'd1').length, 1);
      expect(filterLogbook(r.data.entries, doctorId: 'd2').length, 1);
      await expectLater(
        r.saveEntry(r.draft(procedure(), linkedReportId: 'report')),
        throwsStateError,
      );
      expect(r.forReport('report')!.id, entry.id);
    },
  );
  test(
    'A new revision needs a fresh signature and preserves the signed snapshot',
    () async {
      final r = await repository();
      final entry = r.draft(procedure());
      await r.saveEntry(entry);
      await r.sign(entry.id, 1, 'd2', png);
      final signed = r.data.entry(entry.id)!;
      expect(signed.currentSignature, isNotNull);
      await r.saveEntry(
        LogEntry(
          id: entry.id,
          createdAt: entry.createdAt,
          updatedAt: entry.updatedAt,
          data: procedure(name: 'Amended procedure'),
        ),
        expectedRevision: 1,
      );
      final edited = r.data.entry(entry.id)!;
      expect(edited.revision, 2);
      expect(edited.currentSignature, isNull);
      expect(edited.signatures.single.snapshot.procedure, 'Procedure');
      await expectLater(r.sign(entry.id, 1, 'd2', png), throwsStateError);
      expect(
        LogbookData.fromJson(
          r.data.toJson(),
        ).entries.single.signatures.single.snapshot.procedure,
        'Procedure',
      );
    },
  );
  test(
    'Persist failure retains old state and queued concurrent saves retain both entries',
    () async {
      var fail = false;
      final r = await repository(
        write: (_) async {
          if (fail) throw const FileSystemException('full');
        },
      );
      final entry = r.draft(procedure());
      fail = true;
      await expectLater(
        r.saveEntry(entry),
        throwsA(isA<FileSystemException>()),
      );
      expect(r.data.entries, isEmpty);
      fail = false;
      await Future.wait([
        r.saveEntry(entry),
        r.saveEntry(r.draft(procedure())),
      ]);
      expect(r.data.entries.length, 2);
    },
  );
  test(
    'Reminder snooze keeps dirty state; a backup marks only its captured snapshot',
    () async {
      final r = await repository();
      for (var i = 0; i < 20; i++) {
        await r.saveEntry(r.draft(procedure()));
      }
      expect(r.data.backupDue(DateTime.now()), isTrue);
      await r.snooze();
      expect(r.data.dirty, isTrue);
      expect(r.data.backupDue(DateTime.now()), isFalse);
      final snapshot = r.data;
      await r.saveEntry(r.draft(procedure()));
      await r.backupSucceeded(snapshot);
      expect(r.data.dirty, isTrue);
      expect(r.data.createdCount - r.data.backedCreatedCount, 1);
    },
  );
  test(
    'Restore is validated, repeatable, and replaces without duplicates',
    () async {
      final r = await repository();
      await r.saveEntry(r.draft(procedure()));
      final snapshot = LogbookData.fromJson(r.data.toJson());
      await r.restore(snapshot);
      await r.restore(snapshot);
      expect(r.data.entries.length, 1);
      final j = snapshot.toJson();
      j['doctors'] = [];
      expect(() => LogbookData.fromJson(j), throwsFormatException);
      expect(r.data.entries.length, 1);
      final corrupt = snapshot.toJson();
      corrupt['entries'] = [...corrupt['entries'], ...corrupt['entries']];
      expect(() => LogbookData.fromJson(corrupt), throwsFormatException);
    },
  );
  test(
    'Encryption rejects wrong passwords, tampering and excessive KDF settings',
    () async {
      final r = await repository();
      await r.saveEntry(r.draft(procedure()));
      await r.sign(r.data.entries.single.id, 1, 'd2', png);
      final encrypted = await LogbookBackup.encrypt(
        r.data,
        'a strong test passphrase',
      );
      expect(utf8.decode(encrypted).contains('Dr Example'), isFalse);
      final restored = await LogbookBackup.decrypt(
        encrypted,
        'a strong test passphrase',
      );
      expect(restored.entries.single.currentSignature, isNotNull);
      await expectLater(
        LogbookBackup.decrypt(encrypted, 'incorrect password'),
        throwsA(anything),
      );
      final payload = object(jsonDecode(utf8.decode(encrypted)));
      final ciphertext = base64Decode(payload['ciphertext'] as String);
      ciphertext[0] ^= 1;
      payload['ciphertext'] = base64Encode(ciphertext);
      await expectLater(
        LogbookBackup.decrypt(
          Uint8List.fromList(utf8.encode(jsonEncode(payload))),
          'a strong test passphrase',
        ),
        throwsA(anything),
      );
      payload['iterations'] = 999999999;
      await expectLater(
        LogbookBackup.decrypt(
          Uint8List.fromList(utf8.encode(jsonEncode(payload))),
          'a strong test passphrase',
        ),
        throwsFormatException,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'Rotation retains two completed files and keeps unrelated manual copies',
    () async {
      final dir = await Directory.systemTemp.createTemp('ripot_backup_test_');
      addTearDown(() => dir.delete(recursive: true));
      final manual = File('${dir.path}/my_manual_backup.ripotbackup');
      await manual.writeAsString('keep');
      for (var i = 0; i < 3; i++) {
        await writeRotatingBackup(dir, Uint8List.fromList([i, 3, 4]));
      }
      final generated = await dir
          .list()
          .where((f) => f.path.contains('ripot-logbook-'))
          .toList();
      expect(generated.length, 2);
      expect(await manual.readAsString(), 'keep');
      final bytes = await Future.wait(
        generated.map((f) => File(f.path).readAsBytes()),
      );
      expect(bytes.map((b) => b.first).toSet(), {1, 2});
    },
  );
  test(
    'Local snapshot recovery survives an interrupted or corrupt current write',
    () async {
      final dir = await Directory.systemTemp.createTemp('ripot_store_test_');
      addTearDown(() => dir.delete(recursive: true));
      final store = LogbookStorage(directory: dir);
      final r = await repository();
      await store.write(jsonEncode(r.data.toJson()));
      await r.saveEntry(r.draft(procedure()));
      await store.write(jsonEncode(r.data.toJson()));
      await File('${dir.path}/current.json').writeAsString('{broken');
      final restored = LogbookData.fromJson(
        object(jsonDecode((await store.read())!)),
      );
      expect(restored.entries, isEmpty);
      expect(restored.doctors.length, 2);
      await expectLater(store.write('{bad'), throwsFormatException);
      expect(await File('${dir.path}/recovery.json').exists(), isTrue);
    },
  );
  test(
    'Report log prefill respects conditions and units and never infers performer from author',
    () {
      const parent = SectionNode(
        id: 'p',
        title: 'Finding',
        children: [ContentNode(id: 'pc', text: 'No')],
      );
      const hidden = SectionNode(
        id: 'h',
        title: 'Hidden',
        addToLog: true,
        conditionalParentSectionId: 'p',
        conditionalEquals: 'Yes',
        children: [ContentNode(id: 'hc', text: 'Must not copy')],
      );
      const number = SectionNode(
        id: 'n',
        title: 'Length',
        inputType: FieldInputType.numeric,
        unit: 'cm',
        addToLog: true,
        children: [ContentNode(id: 'nc', text: '4')],
      );
      final report = ReportDoc(
        reportId: 'r',
        createdAtIso: '2026-09-12',
        updatedAtIso: '2026-09-12',
        reportTitle: 'Test',
        roots: [parent, hidden, number],
        signature: const SignatureBlock(name: 'Report author'),
      );
      final data = logDataFromReport(report);
      expect(data.participants, isEmpty);
      expect(data.reportAuthor, 'Report author');
      expect(data.fields.single.value, '4 cm');
      final round = ReportCodec.reportFromJson(
        ReportCodec.reportToJson(report),
      );
      expect(round.roots.last.addToLog, isTrue);
      final template = TemplateDoc(
        templateId: 't',
        updatedAt: DateTime(2026),
        name: 'Template',
        groupName: 'Group',
        roots: [number],
      );
      final decoded = TemplateCodec.templateFromJson(
        TemplateCodec.templateToJson(template),
      );
      expect(decoded.groupName, 'Group');
      expect(
        decoded.roots.single
            .toTemplateNode(includeContent: false)
            .cloneNodeTree()
            .addToLog,
        isTrue,
      );
    },
  );
}
