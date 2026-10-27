import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ripot/core/firebase/callable_http_client.dart';
import 'package:ripot/features/reports/ui/template_review_dialog.dart';

void main() {
  Future<void> open(WidgetTester tester, {
    required Future<void> Function(Map<String, dynamic>) submit,
    required void Function(String?) completed,
    bool longPreview = false,
  }) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
      Scaffold(body: TextButton(child: const Text('Open review'), onPressed: () async {
        completed(await showDialog<String>(context: context,
          barrierDismissible: false,
          builder: (_) => TemplateReviewDialog(
            title: 'Test template', submissionId: 'submission-1', revision: 3,
            accountEmail: 'reviewer@example.invalid',
            preview: [for (var i = 0; i < (longPreview ? 200 : 1); i++) Text('Section $i')],
            submit: submit,
          ),
        ));
      })),
    )));
    await tester.tap(find.text('Open review'));
    await tester.pumpAndSettle();
  }

  testWidgets('Close dismisses a long preview on a narrow screen without saving', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var closed = false;
    await open(tester, longPreview: true,
      submit: (_) async => fail('Closing must not submit a decision'),
      completed: (result) { expect(result, isNull); closed = true; });
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(find.byType(TemplateReviewDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final decision in ['rejected', 'changes_requested']) {
    testWidgets('$decision requires feedback, saves once and returns only after success', (tester) async {
      final pending = Completer<void>();
      final requests = <Map<String, dynamic>>[];
      String? result;
      await open(tester, submit: (data) { requests.add(data); return pending.future; },
        completed: (value) => result = value);
      await tester.tap(find.text(decision == 'rejected' ? 'Reject' : 'Request changes'));
      await tester.pumpAndSettle();
      expect(find.text('Reviewing as: reviewer@example.invalid'), findsOneWidget);
      expect(find.text('Test template'), findsOneWidget);
      final confirm = find.text(decision == 'rejected' ? 'Confirm rejection' : 'Send feedback');
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      expect(find.text('Enter feedback before saving this review.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '  Please clarify the field labels.  ');
      await tester.tap(confirm);
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();
      expect(requests, hasLength(1));
      expect(requests.single, {
        'id': 'submission-1', 'revision': 3, 'decision': decision,
        'note': 'Please clarify the field labels.', 'patientFreeReviewed': false,
      });
      expect(result, isNull);
      expect(find.text('Saving review…'), findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(result, decision);
      expect(find.byType(TemplateReviewDialog), findsNothing);
    });
  }

  for (final code in ['permission-denied', 'unavailable', 'failed-precondition']) {
    testWidgets('$code remains visible with feedback preserved and Close works', (tester) async {
      var closed = false;
      await open(tester, submit: (_) async => throw AccountFunctionException(code: code),
        completed: (value) { expect(value, isNull); closed = true; });
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Needs correction');
      await tester.tap(find.text('Confirm rejection'));
      await tester.pumpAndSettle();
      expect(closed, isFalse);
      expect(find.text('Needs correction'), findsOneWidget);
      expect(find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.liveRegion == true), findsWidgets);
      if (code == 'permission-denied') expect(find.textContaining('This action was refused'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('approval requires confirmation; Back does not publish', (tester) async {
    final requests = <Map<String, dynamic>>[];
    String? result;
    await open(tester, submit: (data) async { requests.add(data); }, completed: (value) => result = value);
    await tester.tap(find.text('Approve and publish'));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    await tester.tap(find.text('Approve and publish'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmed — publish'));
    await tester.pumpAndSettle();
    expect(requests.single['patientFreeReviewed'], isTrue);
    expect(requests.single['decision'], 'approved');
    expect(result, 'approved');
  });
}
