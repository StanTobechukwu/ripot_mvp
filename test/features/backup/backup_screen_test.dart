import 'package:provider/provider.dart';
import 'package:ripot/features/access/providers/access_provider.dart';
import 'package:ripot/features/access/data/access_repository.dart';
import 'package:ripot/features/access/domain/access_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/features/backup/data/backup_schedule.dart';
import 'package:ripot/features/backup/data/backup_service.dart';
import 'package:ripot/features/backup/platform/backup_destination.dart';
import 'package:ripot/features/backup/ui/backup_screen.dart';

class PremiumTestAccess extends AccessProvider {
  PremiumTestAccess() : super(repo: AccessRepository());
  @override
  AccessState get safeState => AccessState.initial(installationId: 'test')
      .copyWith(
        plan: RipotPlan.premium,
        premiumExpiresAt: DateTime.now().add(const Duration(days: 1)),
      )
      .verifiedNow();
}

class ScreenDestination extends BackupDestination {
  String? selected = 'Test backups';
  @override
  bool get supported => true;
  @override
  Future<String?> location() async => selected;
}

class ScreenService extends BackupService {
  ScreenService() : super(destination: ScreenDestination());
  BackupSchedule saved = const BackupSchedule();
  bool failSave = false;
  bool cancelFolder = false;
  bool paused = false;
  final passwords = <String?>[];
  int saves = 0;
  @override
  bool get needsSessionPassword => paused;
  @override
  Future<void> unlockSession(String passphrase) async {
    paused = false;
  }

  @override
  Future<void> runIfDue() async {}
  @override
  Future<BackupSchedule> schedule() async => saved;
  @override
  Future<void> chooseFolder() async {
    if (!cancelFolder)
      (destination as ScreenDestination).selected = 'Test backups';
  }

  @override
  Future<void> configure(BackupSchedule input, String? passphrase) async {
    if (failSave) throw StateError('Choose a backup folder first.');
    passwords.add(passphrase);
    saved = input;
    saves++;
  }
}

Future<void> openScreen(WidgetTester tester, ScreenService service) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider<AccessProvider>(
      create: (_) => PremiumTestAccess(),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BackupScreen(service: service),
                ),
              ),
              child: const Text('Open backups'),
            ),
          ),
        ),
      ),
    ),
  );
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

  testWidgets('keep editing and discard do not change the saved schedule', (
    tester,
  ) async {
    final service = ScreenService();
    await openScreen(tester, service);
    await enable(tester);
    await back(tester);
    expect(find.text('Save backup settings?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
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
    await tester.tap(find.widgetWithText(FilledButton, 'Save settings'));
    await tester.pumpAndSettle();
    await enterPassphrase(tester);
    expect(service.saved.enabled, isTrue);
    expect(service.saves, 1);
    expect(find.text('Open backups'), findsOneWidget);
  });

  testWidgets('cancelled passphrase keeps unsaved settings and page open', (
    tester,
  ) async {
    final service = ScreenService();
    await openScreen(tester, service);
    await enable(tester);
    await back(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save settings'));
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
    await tester.tap(find.widgetWithText(FilledButton, 'Save settings'));
    await tester.pumpAndSettle();
    await enterPassphrase(tester);
    expect(find.text('Backup settings were not saved'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a backup folder first.'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    service.failSave = false;
    await back(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save settings'));
    await tester.pumpAndSettle();
    await enterPassphrase(tester);
    expect(service.saves, 1);
    expect(find.text('Open backups'), findsOneWidget);
  });

  testWidgets(
    'folder refresh preserves draft; reverting edits needs no prompt',
    (tester) async {
      await openScreen(tester, ScreenService());
      await enable(tester);
      await tester.ensureVisible(find.text('Backup folder'));
      await tester.tap(find.text('Backup folder'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await enable(tester);
      await back(tester);
      expect(find.text('Open backups'), findsOneWidget);
    },
  );

  testWidgets(
    'missing folder is requested before a passphrase; cancelling preserves draft',
    (tester) async {
      final service = ScreenService()..cancelFolder = true;
      (service.destination as ScreenDestination).selected = null;
      await openScreen(tester, service);
      await enable(tester);
      await back(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save settings'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a backup folder'), findsOneWidget);
      expect(find.text('Choose a backup password'), findsNothing);
      await tester.tap(find.text('Choose folder'));
      await tester.pumpAndSettle();
      expect(service.saves, 0);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      service.cancelFolder = false;
      await back(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose folder'));
      await tester.pumpAndSettle();
      await enterPassphrase(tester);
      expect(service.saved.enabled, isTrue);
      expect(find.text('Open backups'), findsOneWidget);
    },
  );

  testWidgets(
    'manual backup also requests a missing folder before encryption',
    (tester) async {
      final service = ScreenService();
      (service.destination as ScreenDestination).selected = null;
      await openScreen(tester, service);
      await tester.ensureVisible(find.text('Back up now'));
      await tester.tap(find.text('Back up now'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a backup folder'), findsOneWidget);
      expect(find.text('Choose a backup password'), findsNothing);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      await back(tester);
      expect(find.text('Open backups'), findsOneWidget);
    },
  );

  testWidgets('saving on the page clears the exit prompt', (tester) async {
    final service = ScreenService();
    await openScreen(tester, service);
    await enable(tester);
    await tester.ensureVisible(find.text('Save settings'));
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    await enterPassphrase(tester);
    expect(find.text('You have changes to save.'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Settings saved'),
          )
          .onPressed,
      isNull,
    );
    await back(tester);
    expect(find.text('Save backup settings?'), findsNothing);
    expect(find.text('Open backups'), findsOneWidget);
    expect(service.saves, 1);
  });

  testWidgets('schedule changes reuse the password without another prompt', (
    tester,
  ) async {
    final service = ScreenService()
      ..saved = const BackupSchedule(enabled: true);
    await openScreen(tester, service);
    await tester.ensureVisible(find.text('Daily'));
    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekly · Monday').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save settings'));
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(service.saved.weekday, 1);
    expect(service.passwords, [null]);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Settings saved'), findsOneWidget);
  });

  testWidgets(
    'password restart is shown only for an already saved automatic setup',
    (tester) async {
      final service = ScreenService()..paused = true;
      await openScreen(tester, service);
      await enable(tester);
      expect(find.text('Automatic backups are paused.'), findsNothing);
      expect(find.text('Enter backup password'), findsNothing);
    },
  );

  testWidgets(
    'paused backup asks for the existing password without changing the schedule',
    (tester) async {
      final service = ScreenService()
        ..saved = const BackupSchedule(enabled: true)
        ..paused = true;
      await openScreen(tester, service);
      await tester.ensureVisible(find.text('Enter backup password'));
      await tester.tap(find.text('Enter backup password'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'fictional passphrase');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Automatic backups are paused.'), findsNothing);
      expect(service.saves, 0);
      expect(service.saved.enabled, isTrue);
    },
  );
}
