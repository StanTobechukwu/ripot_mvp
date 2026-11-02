import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ripot/core/platform/report_clipboard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ripot/features/access/domain/access_state.dart';
import 'package:ripot/features/reports/domain/models/nodes.dart';
import 'package:ripot/features/reports/domain/models/report_doc.dart';
import 'package:ripot/features/reports/domain/models/subject_info_value.dart';
import 'package:ripot/features/reports/services/report_copy_service.dart';
import 'package:ripot/features/reports/services/report_text_service.dart';
import 'package:ripot/features/reports/ui/report_copy_action.dart';

const report = ReportDoc(reportId: 'draft-one', createdAtIso: '2026-11-02',
  updatedAtIso: '2026-11-02', reportTitle: 'Fictional clinical report',
  subjectInfo: SubjectInfoValues({'subjectName':'Fictional Patient', 'subjectId':'TEST-001'}),
  signature: SignatureBlock(roleTitle:'Clinician',name:'Test Clinician',credentials:'MD',assistantName:'Test Assistant'),
  roots: [SectionNode(id:'findings',title:'Findings',children:[
    ContentNode(id:'paragraph-1',text:'First full paragraph.'),
    ContentNode(id:'paragraph-2',text:'Second full paragraph.\nAnother line.'),
    SectionNode(id:'numeric',title:'Measurement',inputType:FieldInputType.numeric,unit:'mm',
      children:[ContentNode(id:'measurement',text:'12.5')]),
    SectionNode(id:'internal',title:'Internal code',showInPdf:false,note:'Visible clinical note.',
      children:[ContentNode(id:'internal-value',text:'DO NOT COPY THIS CODE')]),
    SectionNode(id:'empty',title:'OMIT EMPTY',omitWhenEmpty:true),
    SectionNode(id:'choice',title:'Extra findings?',children:[ContentNode(id:'choice-value',text:'No')]),
    SectionNode(id:'conditional',title:'HIDDEN CONDITION',conditionalParentSectionId:'choice',conditionalEquals:'Yes',
      children:[ContentNode(id:'conditional-value',text:'Hidden old value')]),
  ])]);

Map<String,dynamic> response({int remaining = 49, bool repeated = false, bool charged = true}) =>
  {'limit':50,'remaining':remaining,'unlimited':false,'repeated':repeated,'charged':charged};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const renderer = ReportTextService();

  test('copy contains the complete visible draft, units, subject fields and typed signatory', () {
    final text = renderer.render(report);
    expect(text, startsWith('DRAFT\n\nFictional clinical report'));
    for (final value in ['Date: 2026-11-02','Fictional Patient','TEST-001',
      'First full paragraph.','Second full paragraph.\nAnother line.', '12.5 mm',
      'Visible clinical note.','Test Clinician','MD','Assistant: Test Assistant']) {
      expect(text, contains(value));
    }
    for (final value in ['DO NOT COPY THIS CODE','OMIT EMPTY','HIDDEN CONDITION','Hidden old value']) {
      expect(text, isNot(contains(value)));
    }
    expect(text.indexOf('First full paragraph.'), lessThan(text.indexOf('Second full paragraph.')));
  });

  test('existing allowance fingerprint text stays byte-for-byte compatible', () {
    const previous = 'DRAFT\n\nFictional clinical report\n\nDate: 2026-11-02'
        '\n\nSubject Name: Fictional Patient\nSubject ID: TEST-001'
        '\n\nFindings:\nFirst full paragraph.\nSecond full paragraph.\nAnother line.'
        '\nMeasurement:\n12.5 mm\nInternal code:\nVisible clinical note.'
        '\nExtra findings?:\nNo\n\nClinician\nTest Clinician\nMD\n\nAssistant: Test Assistant';
    expect(renderer.render(report), previous);
    final empty = report.copyWith(roots: const []);
    expect(renderer.render(empty.copyWith(roots: const [SectionNode(id: 'blank', title: '')])),
        renderer.render(empty));
  });

  test('formatted and plain clipboard drafts preserve content and selected layout', () {
    for (final layout in ReportLayout.values) {
      final doc = report.copyWith(reportLayout: layout, indentContent: true);
      final data = renderer.clipboard(doc);
      for (final value in ['Fictional Patient', 'TEST-001', 'First full paragraph.',
        'Second full paragraph.', 'Another line.', '12.5 mm', 'Visible clinical note.',
        'Test Clinician', 'Test Assistant']) {
        expect(data.text, contains(value));
        expect(data.html, contains(value));
      }
      for (final value in ['DO NOT COPY THIS CODE', 'OMIT EMPTY', 'Hidden old value']) {
        expect(data.text, isNot(contains(value)));
        expect(data.html, isNot(contains(value)));
      }
      expect(data.html, contains('Second full paragraph.<br>Another line.'));
      expect(data.html, contains('font-weight:bold'));
      if (layout == ReportLayout.aligned) {
        expect(data.html, contains('width:140pt'));
      } else if (layout == ReportLayout.block) {
        expect(data.text, contains('Findings:\n\n  First full paragraph.'));
        expect(data.html, contains('margin:0 0 10pt 24pt'));
      } else {
        expect(data.text, contains('Findings: First full paragraph.'));
        expect(data.html, contains('Findings:</span> First full paragraph.'));
      }
    }
  });

  test('clinical text is escaped, not interpreted as HTML or external content', () {
    final doc = report.copyWith(reportTitle: '<img src="https://example.test/tracker">',
      roots: const [SectionNode(id: 'value', title: 'A & B', children: [
        ContentNode(id: 'clinical', text: '<script>alert(1)</script>\n<5 mm & >2 mm'),
      ])]);
    final data = renderer.clipboard(doc);
    expect(data.html, isNot(contains('<script>')));
    expect(data.html, isNot(contains('<img')));
    expect(data.html, contains('&lt;5 mm &amp; &gt;2 mm'));
    expect(data.text, contains('<5 mm & >2 mm'));
  });

  test('layout changes preserve authorization identity while changing both clipboard formats', () async {
    final keys = <String>[];
    final writes = <ReportClipboardData>[];
    final service = ReportCopyService(currentUid: () => 'alice',
      call: (name, data) async {
        expect(data.keys, ['fingerprint']);
        keys.add(data['fingerprint'] as String);
        return response(repeated: keys.length > 1, charged: keys.length == 1);
      }, writeClipboard: (data) async { writes.add(data); });
    await service.copyReport(report);
    await service.copyReport(report.copyWith(reportLayout: ReportLayout.block));
    expect(keys[0], keys[1]);
    expect(writes[0].html, isNot(writes[1].html));
    expect(writes[0].text, isNot(writes[1].text));
    expect(writes[0].html, contains('Fictional Patient'));
  });

  test('native bridge receives HTML and plain text in one authorized write', () async {
    const channel = MethodChannel('ripot/report_clipboard');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodCall? captured;
    messenger.setMockMethodCallHandler(channel, (call) async { captured = call; });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final data = renderer.clipboard(report);
    await writeReportClipboard(data);
    expect(captured?.method, 'write');
    expect(captured?.arguments, {'text': data.text, 'html': data.html});
  });

  test('no truncation and fingerprints ignore save/layout changes but include changed clinical text', () {
    final longText = List.filled(3000,'A complete sentence.').join('\n');
    final large = report.copyWith(roots:[SectionNode(id:'long',title:'Narrative',
      children:[ContentNode(id:'value',text:longText)])]);
    expect(renderer.render(large), contains(longText));
    final first = renderer.render(report);
    final saved = renderer.render(report.copyWith(updatedAtIso:'2026-11-03',fontScale:1.3,
      reportLayout:ReportLayout.block));
    expect(ReportTextService.fingerprint('alice', first), ReportTextService.fingerprint('alice', saved));
    expect(ReportTextService.fingerprint('alice', first), isNot(ReportTextService.fingerprint('bob', first)));
    expect(ReportTextService.fingerprint('alice', first), isNot(ReportTextService.fingerprint('alice',
      renderer.render(report.copyWith(subjectInfo:const SubjectInfoValues({'subjectName':'Changed Patient'}))))));
  });

  test('only a fingerprint is sent; clipboard receives all text only after authorization', () async {
    String? clipboard;
    final text = renderer.render(report);
    final service = ReportCopyService(currentUid:()=> 'alice', call:(name,data) async {
      expect(clipboard, isNull);
      expect(name,'authorizeReportCopy');
      expect(data.keys, ['fingerprint']);
      expect(data['fingerprint'],ReportTextService.fingerprint('alice',text));
      return response();
    }, writeClipboard:(value) async => clipboard = value.text);
    expect((await service.copy(text)).remaining,49);
    expect(clipboard,text);
  });

  test('denial, server failure and account switches never write report text to clipboard', () async {
    String? uid = 'alice';
    var writes = 0;
    var mode = 'limit';
    final service = ReportCopyService(currentUid:()=>uid, call:(name,data) async {
      if (mode == 'limit') throw const ReportCopyException('resource-exhausted');
      if (mode == 'offline') throw StateError('offline');
      uid = 'bob';
      return response();
    }, writeClipboard:(_) async { writes++; });
    for (final next in ['limit','offline','switch']) {
      mode = next;
      await expectLater(service.copy('text'), throwsA(anything));
    }
    uid = null;
    await expectLater(service.copy('text'), throwsA(isA<ReportCopyException>()));
    expect(writes,0);
  });

  test('failed clipboard retry uses the same short authorization; editing and expiry require checks', () async {
    var now = DateTime(2026,11,2);
    var calls = 0;
    var writes = 0;
    final service = ReportCopyService(currentUid:()=> 'alice', clock:()=>now,
      call:(name,data) async { calls++; return response(); },
      writeClipboard:(_) async { writes++; if (writes.isOdd) throw StateError('clipboard blocked'); });
    await expectLater(service.copy('same'), throwsA(isA<ReportCopyException>()));
    await service.copy('same');
    expect(calls,1);
    await expectLater(service.copy('changed'), throwsA(isA<ReportCopyException>()));
    now = now.add(const Duration(minutes:2));
    await service.copy('changed');
    expect(calls,3);
  });

  test('double taps cannot race clipboard operations', () async {
    final authorize = Completer<dynamic>();
    var writes = 0;
    final service = ReportCopyService(currentUid:()=> 'alice', call:(name,data)=>authorize.future,
      writeClipboard:(_) async { writes++; });
    final first = service.copy('text');
    await expectLater(service.copy('text'), throwsA(isA<ReportCopyException>()));
    authorize.complete(response());
    await first;
    expect(writes,1);
  });

  test('offline Premium is bounded; expired trial or verification uses server allowance', () async {
    var calls = 0;
    final service = ReportCopyService(currentUid:()=> 'alice', call:(name,data) async {calls++; return response();},
      writeClipboard:(_) async {});
    final premium = AccessState.initial(installationId:'test').copyWith(plan:RipotPlan.premium).verifiedNow();
    expect((await service.copy('paid',access:premium)).unlimited,isTrue);
    expect(calls,0);
    final old = premium.copyWith(offlineAccessUntil:DateTime.now().subtract(const Duration(seconds:1)));
    expect((await service.copy('offline-expired',access:old)).unlimited,isFalse);
    final expiredTrial = premium.copyWith(plan:RipotPlan.trial,trialEndsAt:DateTime.now().subtract(const Duration(seconds:1)));
    await service.copy('trial-expired',access:expiredTrial);
    expect(calls,2);
  });

  testWidgets('Preview action displays allowance and warns at 10 remaining', (tester) async {
    var upgrades = 0;
    String? clipboard;
    final service = ReportCopyService(currentUid:()=> 'alice',
      call:(name,data) async => response(remaining:name == 'getReportCopyAllowance' ? 11 : 10,
        charged:name == 'authorizeReportCopy'),
      writeClipboard:(text) async => clipboard = text.text);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ReportCopyAction(
      doc:report,accountUid:'alice',access:AccessState.initial(installationId:'test'),
      service:service,onSignIn:() async {},onUpgrade:() async {upgrades++;},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('11 free copies left'),findsOneWidget);
    await tester.tap(find.text('Copy report'));
    await tester.pumpAndSettle();
    expect(clipboard,renderer.clipboard(report).text);
    expect(find.text('10 free copies left'),findsOneWidget);
    expect(find.text('View Premium'),findsOneWidget);
    await tester.tap(find.text('View Premium'));
    expect(upgrades,1);
    expect(tester.takeException(),isNull);
  });

  testWidgets('compact copy toolbar fits a phone and explains allowance on demand', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = ReportCopyService(currentUid: () => 'alice',
      call: (name, data) async => response(remaining: 49));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReportCopyAction(
      doc: report, accountUid: 'alice', access: AccessState.initial(installationId: 'test'),
      service: service, onSignIn: () async {}, onUpgrade: () async {},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('49 free copies left'), findsOneWidget);
    expect(find.textContaining('They do not renew'), findsNothing);
    await tester.tap(find.byTooltip('About copying reports'));
    await tester.pumpAndSettle();
    expect(find.textContaining('They do not renew'), findsOneWidget);
    expect(find.textContaining('until you change its text'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('guest copy offers sign-in without claiming an allowance', (tester) async {
    var signs = 0;
    final service = ReportCopyService(currentUid:()=>null, call:(name,data) async => throw StateError('must not call'));
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ReportCopyAction(
      doc:report,accountUid:null,access:AccessState.initial(installationId:'test'),
      service:service,onSignIn:() async {signs++;},onUpgrade:() async {},
    ))));
    await tester.tap(find.text('Copy report'));
    await tester.pump();
    expect(signs,1);
    expect(tester.takeException(),isNull);
  });
}
