import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ripot/core/firebase/callable_http_client.dart';
import 'package:ripot/features/reports/ui/template_submission_card.dart';

void main() {
  Map<String, dynamic> row(String status) => {
    'id': 'one', 'name': 'Test structure', 'contributor': 'Author',
    'status': status, 'revision': 1, 'reviewerNote': '',
  };

  testWidgets('withdraw is a pending card menu action, and reviewer cards have no withdraw menu', (tester) async {
    var withdrawals = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TemplateSubmissionCard(
      row: row('pending'), onWithdraw: () => withdrawals++,
    ))));
    expect(find.text('Withdraw submission'), findsNothing);
    await tester.tap(find.byTooltip('Submission options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Withdraw submission'));
    await tester.pumpAndSettle();
    expect(withdrawals, 1);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TemplateSubmissionCard(
      row: row('pending'), onReview: () {},
    ))));
    expect(find.byTooltip('Submission options'), findsNothing);
  });

  testWidgets('rejected reason stays visible and withdrawn submissions can be resubmitted', (tester) async {
    var revisions = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TemplateSubmissionCard(
      row: {...row('rejected'), 'reviewerNote': 'Specify the units.'},
      onWithdraw: () => fail('Not pending'), onRevise: () => revisions++,
    ))));
    expect(find.text('Reason for rejection'), findsOneWidget);
    expect(find.text('Specify the units.'), findsOneWidget);
    expect(find.byTooltip('Submission options'), findsNothing);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TemplateSubmissionCard(
      row: row('withdrawn'), onWithdraw: () => fail('Already withdrawn'),
      onRevise: () => revisions++,
    ))));
    expect(find.textContaining('Your saved template is unchanged'), findsOneWidget);
    expect(find.byTooltip('Submission options'), findsNothing);
    await tester.tap(find.text('Resubmit template'));
    expect(revisions, 1);
  });

  Future<void> open(WidgetTester tester, Future<void> Function() submit,
      void Function(bool?) completed) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
      Scaffold(body: TextButton(onPressed: () async {
        completed(await showDialog<bool>(context: context, barrierDismissible: false,
          builder: (_) => TemplateWithdrawalDialog(name: 'Test structure', submit: submit)));
      }, child: const Text('Open'))),
    )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('cancel keeps submission without contacting server', (tester) async {
    bool? result;
    await open(tester, () async => fail('Cancelled'), (value) => result = value);
    await tester.tap(find.text('Keep submission'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(find.byType(TemplateWithdrawalDialog), findsNothing);
  });

  testWidgets('withdraw waits for confirmation from server and prevents duplicate taps', (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    bool? result;
    await open(tester, () { calls++; return pending.future; }, (value) => result = value);
    await tester.tap(find.text('Withdraw submission'));
    await tester.pump();
    await tester.tap(find.text('Withdrawing…'));
    await tester.pump();
    expect(calls, 1);
    expect(result, isNull);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Keep submission')).onPressed, isNull);
    pending.complete();
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.byType(TemplateWithdrawalDialog), findsNothing);
  });

  testWidgets('server failure stays visible; retry does not close until success', (tester) async {
    var calls = 0;
    bool? result;
    await open(tester, () async {
      if (++calls == 1) throw const AccountFunctionException(code: 'failed-precondition');
    }, (value) => result = value);
    await tester.tap(find.text('Withdraw submission'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.textContaining('This submission has changed'), findsOneWidget);
    await tester.tap(find.text('Withdraw submission'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(calls, 2);
  });
}
