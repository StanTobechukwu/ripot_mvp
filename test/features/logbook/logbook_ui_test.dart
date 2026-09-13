import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ripot/core/ui/item_actions.dart';
import 'package:ripot/features/logbook/data/logbook_repository.dart';
import 'package:ripot/features/logbook/domain/logbook_models.dart';
import 'package:ripot/features/logbook/ui/log_entry_editor.dart';
import 'package:ripot/features/logbook/ui/logbook_screen.dart';

void main() {
  testWidgets('Quick Log saves on a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = LogbookRepository(read: () async => null, write: (_) async {});
    await repo.load();
    await repo.saveDoctor(
      const LogDoctor(id: 'doctor', name: 'Example Doctor'),
      isMe: true,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: repo,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: const LogbookScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quick Log'));
    await tester.pumpAndSettle();
    expect(find.byType(LogEntryEditor), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).first,
      'Diagnostic procedure',
    );
    await tester.tap(find.text('Save').first);
    await tester.pumpAndSettle();
    expect(repo.data.entries.single.data.procedure, 'Diagnostic procedure');
    expect(
      repo.data.entries.single.data.participants.single.doctorId,
      'doctor',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('Action menu remains scrollable at large text sizes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showItemActions(
                context,
                'A long procedure template title that wraps onto several lines',
                const [
                  ItemAction('a', 'Use template', Icons.edit),
                  ItemAction('b', 'Edit template', Icons.edit),
                  ItemAction('c', 'Duplicate template', Icons.copy),
                  ItemAction('d', 'Export template', Icons.share),
                  ItemAction('e', 'Move to group', Icons.folder),
                  ItemAction(
                    'delete',
                    'Delete template',
                    Icons.delete,
                    destructive: true,
                  ),
                ],
              ),
              child: const Text('Options'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete template'));
    await tester.tap(find.text('Delete template'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
