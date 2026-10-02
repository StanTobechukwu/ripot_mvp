import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/core/firebase/account_session.dart';
import 'package:ripot/features/access/data/access_repository.dart';
import 'package:ripot/features/access/domain/access_state.dart';
import 'package:ripot/features/access/providers/access_provider.dart';
import 'package:ripot/features/access/ui/premium_prompt.dart';
import 'package:ripot/features/auth/providers/auth_provider.dart';
import 'package:ripot/features/reports/data/templates_repository.dart';

class TrialRepository extends AccessRepository {
  AccessState current = AccessState.initial(
    installationId: 'demo',
  ).verifiedNow();
  int activations = 0;
  bool failActivation = false;
  @override
  Future<AccessState?> loadCached() async => current;
  @override
  Future<AccessState> load({bool refreshPlay = true}) async => current;
  @override
  Future<void> save(AccessState state) async {
    current = state;
  }

  @override
  Future<AccessState?> activatePremiumTrialForSignedInAccount() async {
    activations++;
    if (failActivation) return null;
    return current = current
        .copyWith(
          plan: RipotPlan.trial,
          hasUsedTrial: true,
          trialStartAt: DateTime.now(),
          trialEndsAt: DateTime.now().add(const Duration(days: 21)),
        )
        .verifiedNow();
  }
}

class PromptAuth extends AuthProvider {
  PromptAuth(AccessProvider access, {this.signedIn = true})
    : super(accessProvider: access, templatesRepository: TemplatesRepository());
  bool signedIn;
  @override
  bool get isSignedIn => signedIn;
  @override
  bool get authAvailable => true;
  @override
  AccountUser? get currentUser =>
      signedIn ? const AccountUser(uid: 'fictional') : null;
  @override
  Future<bool> signIn({required String email, required String password}) async {
    signedIn = true;
    notifyListeners();
    return true;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<(TrialRepository, AccessProvider)> mount(
    WidgetTester tester, {
    bool guest = false,
    bool used = false,
    bool fail = false,
  }) async {
    final repo = TrialRepository()..failActivation = fail;
    if (used) repo.current = repo.current.copyWith(hasUsedTrial: true);
    final access = AccessProvider(repo: repo);
    await access.load();
    final auth = PromptAuth(access, signedIn: !guest);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AccessProvider>(create: (_) => access),
          ChangeNotifierProvider<AuthProvider>(create: (_) => auth),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final unlocked = await showPremiumFeatureSheet(
                    context,
                    PremiumFeature.records,
                  );
                  if (context.mounted && unlocked)
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Records opened')),
                    );
                },
                child: const Text('Open Records'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Records'));
    await tester.pumpAndSettle();
    return (repo, access);
  }

  testWidgets(
    'eligible account sees trial first and the original action resumes',
    (tester) async {
      final (repo, access) = await mount(tester);
      expect(find.text('Activate your free Premium trial'), findsOneWidget);
      expect(find.text('View subscription options'), findsNothing);
      await tester.tap(find.text('Activate your free Premium trial'));
      await tester.pumpAndSettle();
      expect(repo.activations, 1);
      expect(access.safeState.isPremiumLike, isTrue);
      expect(find.text('Records opened'), findsOneWidget);
    },
  );

  testWidgets(
    'signing in checks eligibility but does not silently start the trial',
    (tester) async {
      final (repo, _) = await mount(tester, guest: true);
      expect(find.text('Activate your free Premium trial'), findsNothing);
      await tester.tap(find.text('Sign in to check your free trial'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'fictional@example.invalid',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'fictional-password',
      );
      final submit = find.widgetWithText(FilledButton, 'Sign in');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(repo.activations, 0);
      expect(find.text('Activate your free Premium trial'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Open Records'), findsOneWidget);
    },
  );

  testWidgets(
    'used trial shows subscription options without promising another trial',
    (tester) async {
      await mount(tester, used: true);
      expect(find.text('View subscription options'), findsOneWidget);
      expect(find.text('Activate your free Premium trial'), findsNothing);
    },
  );

  testWidgets(
    'failed activation keeps the feature locked and allows dismissal',
    (tester) async {
      final (repo, access) = await mount(tester, fail: true);
      await tester.tap(find.text('Activate your free Premium trial'));
      await tester.pumpAndSettle();
      expect(repo.activations, 1);
      expect(access.safeState.isPremiumLike, isFalse);
      expect(find.text('Records opened'), findsNothing);
      expect(find.textContaining('We could not activate'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Open Records'), findsOneWidget);
    },
  );
}
