import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class RestResponse {
  const RestResponse(this.status, this.data);
  final int status;
  final dynamic data;
}

class RestTransportException implements Exception {
  const RestTransportException();
  @override
  String toString() => 'The account service could not be reached.';
}

/// Requests never follow redirects or include credentials in exception text.
class RestJsonClient {
  RestJsonClient({
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 15),
  }) : _clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() _clientFactory;
  final Duration timeout;

  Future<RestResponse> request(
    String method,
    Uri uri, {
    Object? body,
    String? idToken,
    bool form = false,
  }) async {
    if (uri.scheme != 'https' ||
        !const {
          'identitytoolkit.googleapis.com',
          'securetoken.googleapis.com',
          'firestore.googleapis.com',
        }.contains(uri.host)) {
      throw ArgumentError('Unsupported account endpoint.');
    }
    final client = _clientFactory();
    try {
      final request = http.Request(method, uri)..followRedirects = false;
      if (idToken != null) request.headers['Authorization'] = 'Bearer $idToken';
      if (body != null) {
        if (form) {
          request.bodyFields = Map<String, String>.from(body as Map);
        } else {
          request.headers['Content-Type'] = 'application/json; charset=utf-8';
          request.body = jsonEncode(body);
        }
      }
      final response = await (() async => http.Response.fromStream(
        await client.send(request),
      ))().timeout(timeout);
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const RestTransportException();
      }
      final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
      return RestResponse(response.statusCode, decoded);
    } on TimeoutException {
      throw const RestTransportException();
    } on http.ClientException {
      throw const RestTransportException();
    } on FormatException {
      throw const RestTransportException();
    } finally {
      client.close();
    }
  }
}
