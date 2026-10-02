import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/features/reports/data/reports_repository.dart';
import 'package:ripot/features/reports/domain/models/report_doc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ReportsRepository repo;
  final bytes = Uint8List.fromList(
    '%PDF-1.4 fictional test document'.codeUnits,
  );
  ReportDoc doc(String id) => ReportDoc(
    reportId: id,
    createdAtIso: '2026-10-02T00:00:00Z',
    updatedAtIso: '2026-10-02T00:00:00Z',
  );
  Future<void> finish(String id, {int limit = 10}) =>
      repo.savePdfBytesForReport(
        id,
        bytes,
        doc: doc(id),
        maxFinalizedReports: () => limit,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('ripot-finalized-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    repo = ReportsRepository();
  });
  tearDown(() async {
    await directory.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  test(
    'many editable drafts do not consume any final-report allowance',
    () async {
      for (var i = 0; i < 25; i++) {
        await repo.saveReport(doc('draft-$i'));
      }
      await finish('draft-0');
      final reports = await repo.listReports();
      expect(reports.where((r) => r.isFinalReport), hasLength(1));
      expect(reports.where((r) => r.isSavedWork), hasLength(24));
    },
  );

  test(
    'an existing draft cannot bypass the tenth finalized-report limit',
    () async {
      for (var i = 0; i < 10; i++) {
        await finish('final-$i');
      }
      await repo.saveReport(doc('draft'));
      await expectLater(
        finish('draft'),
        throwsA(isA<FinalizedReportLimitException>()),
      );
      expect(await repo.loadPdfBytesForReport('draft'), isNull);
      expect((await repo.loadReport('draft')).reportId, 'draft');
      expect(await repo.isReportFinalized('draft'), isFalse);
      await finish('draft', limit: 100);
      expect(
        (await repo.listReports()).where((r) => r.isFinalReport),
        hasLength(11),
      );
    },
  );

  test(
    'expiry preserves excess PDFs and drafts; replacements use no new slot',
    () async {
      for (var i = 0; i < 12; i++) {
        await finish('final-$i', limit: 100);
      }
      await repo.saveReport(doc('new-draft'));
      await expectLater(
        finish('new-draft'),
        throwsA(isA<FinalizedReportLimitException>()),
      );
      await finish('final-0');
      expect(await repo.loadPdfBytesForReport('final-11'), bytes);
      expect((await repo.listReports()), hasLength(13));
      await repo.deleteReport('final-0');
      await repo.deleteReport('final-1');
      await repo.deleteReport('final-2');
      await finish('new-draft');
      expect(
        (await repo.listReports()).where((r) => r.isFinalReport),
        hasLength(10),
      );
    },
  );

  test('concurrent finalizations cannot both take the last slot', () async {
    final outcomes = await Future.wait([
      finish('a', limit: 1).then((_) => true, onError: (_) => false),
      finish('b', limit: 1).then((_) => true, onError: (_) => false),
    ]);
    expect(outcomes.where((ok) => ok), hasLength(1));
    expect(
      (await repo.listReports()).where((r) => r.isFinalReport),
      hasLength(1),
    );
  });

  test(
    'failed PDF write consumes no slot; restoring existing PDFs remains allowed',
    () async {
      await expectLater(
        repo.savePdfBytesForReport(
          'bad',
          Uint8List(0),
          doc: doc('bad'),
          maxFinalizedReports: () => 1,
        ),
        throwsArgumentError,
      );
      await finish('first', limit: 1);
      await repo.saveReport(doc('restored'));
      await repo.importPdfBytesForReport(
        'restored',
        bytes,
        fileName: 'Restored.pdf',
      );
      expect(await repo.loadPdfBytesForReport('restored'), bytes);
      expect(
        (await repo.listReports()).where((r) => r.isFinalReport),
        hasLength(2),
      );
    },
  );
}
