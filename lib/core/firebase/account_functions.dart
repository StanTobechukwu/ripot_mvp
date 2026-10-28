import 'package:cloud_functions/cloud_functions.dart';

import 'account_runtime.dart';
import '../../firebase_options.dart';
import 'callable_http_client.dart';

/// The Cloud Functions Flutter plugin has no Windows implementation. Account
/// operations on Windows use the official authenticated callable protocol.
/// Trial/subscription decisions still belong exclusively to the server.
class AccountFunctions {
  static const _allowed = {
    'submitTemplateContribution',
    'listTemplateContributions',
    'reviewTemplateContribution',
    'withdrawTemplateContribution',
    'activatePremiumTrial',
    'syncFounderEntitlement',
    'refreshPlayEntitlement',
  };

  static Future<dynamic> call(
    String name, {
    Map<String, dynamic> data = const {},
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_allowed.contains(name)) throw ArgumentError.value(name, 'name');
    if (!AccountRuntime.usesWindowsRest) {
      final result = await FirebaseFunctions.instance
          .httpsCallable(name, options: HttpsCallableOptions(timeout: timeout))
          .call(data);
      return result.data;
    }

    final session = AccountRuntime.session;
    final user = session?.currentUser;
    final token = await session?.idToken().timeout(timeout);
    if (user == null ||
        token == null ||
        token.isEmpty ||
        session?.currentUser?.uid != user.uid) {
      throw const AccountFunctionException(code: 'unauthenticated');
    }
    final result = await CallableHttpClient().call(
      projectId: DefaultFirebaseOptions.windows.projectId,
      name: name,
      idToken: token,
      timeout: timeout,
      data: data,
    );
    if (session?.currentUser?.uid != user.uid) {
      throw const AccountFunctionException(code: 'unauthenticated');
    }
    return result;
  }
}
