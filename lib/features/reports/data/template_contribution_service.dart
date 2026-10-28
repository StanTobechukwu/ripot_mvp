import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;
import '../../../core/firebase/callable_http_client.dart';
import 'public_template_catalog.dart';

/// A read-only check before collecting contribution details. This never submits
/// a template and never sends an account token to the public endpoint.
Future<void> checkTemplateContributionService() async {
  final client = http.Client();
  try {
    final response = await client.get(Uri.parse(
      '${PublicTemplateCatalog.communityEndpoint}?health=1',
    )).timeout(const Duration(seconds: 12));
    if (response.statusCode == 404) {
      throw const AccountFunctionException(code: 'service-not-deployed');
    }
    if (response.statusCode != 200) {
      throw const AccountFunctionException(code: 'unavailable');
    }
    final body = jsonDecode(response.body);
    if (body is! Map || body['schemaVersion'] != 1 || body['contributions'] != 'ready') {
      throw const AccountFunctionException(code: 'service-update-required');
    }
  } on FormatException {
    throw const AccountFunctionException(code: 'service-update-required');
  } finally {
    client.close();
  }
}

String templateContributionError(Object error, {bool submitting = false}) {
  final code = switch (error) {
    FirebaseFunctionsException e => e.code,
    AccountFunctionException e => e.code,
    TimeoutException() => 'deadline-exceeded',
    http.ClientException() => 'unavailable',
    _ => 'unknown',
  };
  // Map only known server messages. Never display arbitrary server details.
  final serverMessage = switch (error) {
    FirebaseFunctionsException e => e.message,
    AccountFunctionException e => e.message,
    _ => null,
  };
  final permissionMessage = switch (serverMessage) {
    'Another reviewer must approve your own contribution.' ||
    'Another reviewer must review your own contribution.' =>
      'This template was submitted by the account you are using. Another reviewer must review it. To withdraw it, open My submissions and use its three-dot menu.',
    'Reviewer access is required.' =>
      'This account does not have reviewer access. Sign in with an authorised reviewer account.',
    'This submission belongs to another contributor.' ||
    'Only the contributor can withdraw this submission.' =>
      'Only the account that submitted this template can change or withdraw it.',
    _ => 'This action was refused. Refresh the library and check which Ripot account is signed in. If it continues, contact support@ripot.app.',
  };
  final message = switch (code) {
    'service-not-deployed' => 'Template contributions are not available on the server yet. Please contact support@ripot.app. Your saved template is safe.',
    'service-update-required' => 'The template service needs an update. Please contact support@ripot.app. Your saved template is safe.',
    'unauthenticated' => 'Please sign in again, then retry this action.',
    'permission-denied' => permissionMessage,
    'account-changed' => 'Your signed-in account changed. Close this screen and reopen the library before continuing.',
    'invalid-argument' => 'Check the required details and template structure. Templates must be non-empty, below 250 KB, with at most 200 nodes and 50 options per field.',
    'resource-exhausted' => 'The submission limit has been reached. You can submit up to ten templates or revisions in 24 hours. Please try again later.',
    'failed-precondition' || 'aborted' || 'already-exists' => 'This submission has changed. Refresh My submissions or the review queue before continuing.',
    'not-found' || 'unimplemented' => 'The template service or submission could not be found. Refresh and retry; if it persists, contact support@ripot.app.',
    'deadline-exceeded' => 'The server did not respond in time. Check My submissions before retrying; the request may already have arrived.',
    'unavailable' => 'Could not reach the template service. Check your connection and try again. If other pages work, the service may be temporarily unavailable.',
    _ => 'The template service could not complete this action. Retry later or contact support@ripot.app.',
  };
  return submitting && code != 'account-changed' ? '$message Your entries are kept on this screen. Retrying here will not create a duplicate submission.' : message;
}
