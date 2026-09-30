import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class AccountFunctionException implements Exception {
  const AccountFunctionException({required this.code});
  final String code;

  @override
  String toString() => 'Account function failed ($code).';
}

/// A small transport for Ripot's account callables on Windows only.
/// https://firebase.google.com/docs/functions/callable-reference
class CallableHttpClient {
  CallableHttpClient({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;

  Future<dynamic> call({
    required String projectId,
    required String name,
    required String idToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$').hasMatch(projectId) ||
        !RegExp(r'^[a-zA-Z][a-zA-Z0-9_-]*$').hasMatch(name)) {
      throw ArgumentError('Invalid callable endpoint.');
    }
    if (idToken.trim().isEmpty) {
      throw AccountFunctionException(code: 'unauthenticated');
    }

    final client = _clientFactory();
    try {
      // Construct the real endpoint independently of all user-entered data.
      final authenticatedRequest =
          http.Request(
              'POST',
              Uri.https('us-central1-$projectId.cloudfunctions.net', '/$name'),
            )
            ..followRedirects = false
            ..headers.addAll({
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer $idToken',
            })
            ..body = jsonEncode({'data': <String, dynamic>{}});
      final response = await (() async {
        final stream = await client.send(authenticatedRequest);
        return http.Response.fromStream(stream);
      })().timeout(timeout);

      dynamic body;
      try {
        body = jsonDecode(response.body);
      } on FormatException {
        throw AccountFunctionException(code: 'internal');
      }
      if (body is! Map<String, dynamic>) {
        throw AccountFunctionException(code: 'internal');
      }
      if (body.containsKey('error')) {
        final error = body['error'];
        final status = error is Map ? error['status'] : null;
        const validStatuses = {
          'CANCELLED',
          'UNKNOWN',
          'INVALID_ARGUMENT',
          'DEADLINE_EXCEEDED',
          'NOT_FOUND',
          'ALREADY_EXISTS',
          'PERMISSION_DENIED',
          'RESOURCE_EXHAUSTED',
          'FAILED_PRECONDITION',
          'ABORTED',
          'OUT_OF_RANGE',
          'UNIMPLEMENTED',
          'INTERNAL',
          'UNAVAILABLE',
          'DATA_LOSS',
          'UNAUTHENTICATED',
        };
        final code = validStatuses.contains(status)
            ? (status as String).toLowerCase().replaceAll('_', '-')
            : 'internal';
        throw AccountFunctionException(code: code);
      }
      if (response.statusCode != 200 || !body.containsKey('result')) {
        throw AccountFunctionException(code: 'internal');
      }
      return body['result'];
    } on TimeoutException {
      throw AccountFunctionException(code: 'deadline-exceeded');
    } on http.ClientException {
      throw AccountFunctionException(code: 'unavailable');
    } finally {
      client.close();
    }
  }
}
