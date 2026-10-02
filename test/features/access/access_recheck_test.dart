import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/features/access/data/access_repository.dart';
import 'package:ripot/features/access/domain/access_state.dart';
import 'package:ripot/features/access/providers/access_provider.dart';
import 'package:ripot/features/access/ui/access_recheck.dart';
import 'package:ripot/features/auth/providers/auth_provider.dart';
import 'package:ripot/features/reports/data/templates_repository.dart';

class RecheckRepository extends AccessRepository {
  int checks = 0;
  @override
  Future<AccessState> load({bool refreshPlay = true}) async {
    checks++;
    return AccessState.initial(installationId: 'demo').verifiedNow();
  }
}

class RecheckAuth extends AuthProvider {
  RecheckAuth(AccessProvider access)
    : super(accessProvider: access, templatesRepository: TemplatesRepository());
  bool signedIn = true;
  @override
  bool get isSignedIn => signedIn;
}

void main() {
  testWidgets(
    'startup checks once; repeated focus changes are coalesced and guests do not check',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = RecheckRepository();
      final access = AccessProvider(repo: repo);
      final auth = RecheckAuth(access);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AccessProvider>.value(value: access),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ],
          child: const MaterialApp(
            home: AccessRecheck(child: Scaffold(body: Text('Reports'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.checks, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(repo.checks, 1);
      access.resetForAccountChange();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(repo.checks, 2);
      auth.signedIn = false;
      access.resetForAccountChange();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(repo.checks, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      access.dispose();
    },
  );
}
