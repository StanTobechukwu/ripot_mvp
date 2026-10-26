import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/features/backup/data/backup_schedule.dart';
import 'package:ripot/features/backup/data/backup_service.dart';
import 'package:ripot/features/backup/platform/backup_destination.dart';
import 'package:ripot/features/backup/ui/backup_screen.dart';

class ScreenDestination extends BackupDestination {
  @override
  bool get supported => true;
  @override
  Future<String?> location() async => 'Test backups';
}

class ScreenService extends BackupService {
  ScreenService() : super(destination: ScreenDestination());
  BackupSchedule saved = const BackupSchedule();
  bool failSave = false;
  int saves = 0;
  @override
  Future<BackupSchedule> schedule() async => saved;
  @override
  Future<void> chooseFolder() async {}
  @override
  Future<void> configure(BackupSchedule input, String passphrase) async {
    if (failSave) throw StateError('Choose a backup folder first.');
    saved = input;
    saves++;
  }
}

Future<void> openScreen(WidgetTester tester, ScreenService service) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) => Scaffold(
      body: TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => BackupScreen(service: service),
        )),
        child: const Text('Open backups'),
      ),
    )),
  ));
  await tester.tap(find.text('Open backups'));
  await tester.pumpAndSettle();
}

Future<void> enable(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(SwitchListTile));
  await tester.tap(find.byType(SwitchListTile));
  await tester.pumpAndSettle();
}

Future<void> back(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
}

Future<void> enterPassphrase(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'fictional passphrase');
  await tester.enterText(find.byType(TextField).at(1), 'fictional passphrase');
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('visiting without edits leaves without a prompt', (tester) async {
    await openScreen(tester, ScreenService());
    await back(tester);
    expect(find.text('Open backups'), findsOneWidget);
    expect(find.text('Save backup settings?'), findsNothing);
  });

  testWidgets('keep editing and discard do not change the saved schedule', (tester) async {
    final service = ScreenService();
    await openScreen(tester, service);
    await enable(tester);
    await back(tester);
    expect(find.text('Save backup settings?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
    await back(tester);
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.text('Open backups'), findsOneWidget);
    expect(service.saved.enabled, isFalse);
    expect(service.saves, 0);
  });

  testWidgets('save on exit persists settings before leaving', (tester) async {
    final service = ScreenService();
    await openScreen(tester, service);
    await enable(tester);
    await back(tester);
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    await enterPassphrase(tester);
    expect(service.saved.enabled, isTrue);
    expect(service.saves, 1);
    expect(find.text('Open backups'), findsOneWidget);
  });

  testWidgets('cancelled passphrase keeps unsaved settings and page open', (tester) async {
    final service = ScreenService();
    await openScreen(tester, service);
    await enable(tester);
    await back(tester);
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await back(tester);
    expect(find.text('Save backup settings?'), findsOneWidget);
    expect(service.saves, 0);
  });

  testWidgets('failed save keeps the draft and allows retry', (tester) async {
    final service = ScreenService()..failSave = true;
    await openScreen(tester, service);
    await enable(tester);
    await back(tester);
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    await enterPassphrase(tester);
    expect(find.text('Choose a backup folder first.'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
    service.failSave = false;
    await back(tester);
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    await enterPassphrase(tester);
    expect(service.saves, 1);
    expect(find.text('Open backups'), findsOneWidget);
  });

  testWidgets('folder refresh preserves draft; reverting edits needs no prompt', (tester) async {
    await openScreen(tester, ScreenService());
    await enable(tester);
    await tester.ensureVisible(find.text('Backup folder'));
    await tester.tap(find.text('Backup folder'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
    await enable(tester);
    await back(tester);
    expect(find.text('Open backups'), findsOneWidget);
  });
}
