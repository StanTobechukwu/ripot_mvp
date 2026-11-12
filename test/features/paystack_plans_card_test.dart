import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/core/firebase/account_session.dart';
import 'package:ripot/features/access/data/access_repository.dart';
import 'package:ripot/features/access/providers/access_provider.dart';
import 'package:ripot/features/auth/providers/auth_provider.dart';
import 'package:ripot/features/reports/data/templates_repository.dart';
import 'package:ripot/features/billing/ui/paystack_plans_card.dart';

class PaymentAccess extends AccessProvider {
  PaymentAccess() : super(repo: AccessRepository());
  @override
  Future<void> refresh({bool refreshPlay = true}) async {}
}

class PaymentAuth extends AuthProvider {
  PaymentAuth(AccessProvider access)
    : super(accessProvider: access, templatesRepository: TemplatesRepository());
  String uid = 'alice';
  @override
  AccountUser get currentUser =>
      AccountUser(uid: uid, email: '$uid@example.test');
  @override
  String get email => '$uid@example.test';
  void switchAccount() {
    uid = 'bob';
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'country selection shows only the approved offer and resets on account change',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final access = PaymentAccess();
      final auth = PaymentAuth(access);
      addTearDown(access.dispose);
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AccessProvider>.value(value: access),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PaystackPlansCard(
                  paymentCall: (name, data) async =>
                      name == 'refreshPaystackEntitlement'
                      ? {}
                      : {
                          'enabled': true,
                          'mode': 'live',
                          'internationalEnabled': true,
                          'billingCountries': [
                            {'code': 'NG', 'label': 'Nigeria'},
                            {'code': 'US', 'label': 'United States'},
                            {'code': 'CA', 'label': 'Canada'},
                          ],
                          'plans': [
                            {
                              'id': 'ng_monthly',
                              'amount': 250000,
                              'currency': 'NGN',
                              'interval': 'monthly',
                              'markets': ['NG'],
                            },
                            {
                              'id': 'us_monthly',
                              'amount': 1200000,
                              'currency': 'NGN',
                              'interval': 'monthly',
                              'markets': ['US'],
                            },
                          ],
                        },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('₦2,500'), findsNothing);
      expect(find.textContaining('₦12,000'), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('United States').last);
      await tester.pumpAndSettle();
      expect(find.text('₦12,000.00 NGN per month'), findsOneWidget);
      expect(find.textContaining('₦2,500'), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Canada').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('A plan is not available'), findsOneWidget);
      expect(find.text('Subscribe monthly'), findsNothing);
      auth.switchAccount();
      await tester.pumpAndSettle();
      expect(find.text('Canada'), findsNothing);
      expect(
        find.textContaining('Select your billing country to see'),
        findsOneWidget,
      );
      expect(find.text('Premium account: bob@example.test'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
