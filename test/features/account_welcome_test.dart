import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/features/access/data/access_repository.dart';
import 'package:ripot/features/access/providers/access_provider.dart';
import 'package:ripot/features/auth/providers/auth_provider.dart';
import 'package:ripot/features/auth/ui/startup_account_gate.dart';
import 'package:ripot/features/reports/data/templates_repository.dart';

class FakeAuth extends AuthProvider {
  FakeAuth({required this.access, this.signedIn = false, this.available = true})
    : super(accessProvider: access, templatesRepository: TemplatesRepository());
  final AccessProvider access;
  bool signedIn;
  final bool available;
  @override
  bool get isSignedIn => signedIn;
  @override
  bool get authAvailable => available;
  @override
  Future<bool> signIn({required String email, required String password}) async {
    signedIn = true;
    notifyListeners();
    return true;
  }
  @override
  Future<bool> signUp({required String email, required String password}) =>
      signIn(email: email, password: password);
  @override
  void dispose() { super.dispose(); access.dispose(); }
}

Widget app(FakeAuth auth) => ChangeNotifierProvider<AuthProvider>.value(
  value: auth,
  child: const MaterialApp(home: StartupAccountGate(
    child: Scaffold(body: Text('My Reports')),
  )),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({
    'reports.index': ['existing-fictional-report'],
  }));

  FakeAuth makeAuth({bool signedIn = false, bool available = true}) {
    final auth = FakeAuth(access: AccessProvider(repo: AccessRepository()),
        signedIn: signedIn, available: available);
    addTearDown(auth.dispose);
    return auth;
  }

  testWidgets('guest can skip once and existing saved work is untouched', (tester) async {
    final auth = makeAuth();
    await tester.pumpWidget(app(auth));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Ripot'), findsOneWidget);
    final skip = find.text('Continue without an account');
    await tester.ensureVisible(skip);
    await tester.tap(skip);
    await tester.pumpAndSettle();
    expect(find.text('My Reports'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('reports.index'), ['existing-fictional-report']);
    expect(prefs.getBool(StartupAccountGate.completedKey), isTrue);
    expect(auth.signedIn, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app(auth));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Ripot'), findsNothing);
    expect(find.text('My Reports'), findsOneWidget);
  });

  testWidgets('restored signed-in account goes straight to reports', (tester) async {
    await tester.pumpWidget(app(makeAuth(signedIn: true)));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Ripot'), findsNothing);
    expect(find.text('My Reports'), findsOneWidget);
  });

  testWidgets('unconfigured account services cannot block local work', (tester) async {
    await tester.pumpWidget(app(makeAuth(available: false)));
    await tester.pumpAndSettle();
    expect(find.text('My Reports'), findsOneWidget);
  });

  testWidgets('successful first sign-in opens reports without popping the app route', (tester) async {
    await tester.pumpWidget(app(makeAuth()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'fictional@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'fictional-password');
    final submit = find.widgetWithText(FilledButton, 'Sign in');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('My Reports'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('create-account flow can return to sign-in or continue as guest', (tester) async {
    await tester.pumpWidget(app(makeAuth()));
    await tester.pumpAndSettle();
    var create = find.widgetWithText(TextButton, 'Create account');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    final back = find.text('Already have an account? Sign in');
    await tester.ensureVisible(back);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Ripot'), findsOneWidget);
    create = find.widgetWithText(TextButton, 'Create account');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    final skip = find.text('Continue without an account');
    await tester.ensureVisible(skip);
    await tester.tap(skip);
    await tester.pumpAndSettle();
    expect(find.text('My Reports'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
