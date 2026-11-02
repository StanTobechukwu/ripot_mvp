import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/firebase/account_functions.dart';
import '../../../core/firebase/account_runtime.dart';
import '../../../core/firebase/callable_http_client.dart';
import '../../../core/platform/report_clipboard.dart';
import '../../access/domain/access_state.dart';
import '../domain/models/report_doc.dart';
import 'report_text_service.dart';

typedef CopyCallable = Future<dynamic> Function(String name, Map<String, dynamic> data);

class ReportCopyAllowance {
  const ReportCopyAllowance({required this.limit, required this.remaining,
    this.unlimited = false, this.repeated = false, this.charged = false});
  final int limit;
  final int remaining;
  final bool unlimited;
  final bool repeated;
  final bool charged;

  factory ReportCopyAllowance.parse(dynamic value) {
    if (value is! Map || value['limit'] != 50 || value['remaining'] is! int ||
        value['remaining'] < 0 || value['remaining'] > 50 ||
        value['unlimited'] is! bool || value['repeated'] is! bool ||
        value['charged'] is! bool) {
      throw const ReportCopyException('unavailable');
    }
    return ReportCopyAllowance(limit: value['limit'] as int,
      remaining: value['remaining'] as int, unlimited: value['unlimited'] as bool,
      repeated: value['repeated'] as bool, charged: value['charged'] as bool);
  }
}

class ReportCopyException implements Exception {
  const ReportCopyException(this.code);
  final String code;
}

class ReportCopyService {
  ReportCopyService({String? Function()? currentUid, CopyCallable? call,
    Future<void> Function(ReportClipboardData)? writeClipboard, DateTime Function()? clock})
      : _currentUid = currentUid ?? (() => AccountRuntime.session?.currentUser?.uid),
        _call = call ?? ((name, data) => AccountFunctions.call(name, data: data)),
        _writeClipboard = writeClipboard ?? writeReportClipboard,
        _clock = clock ?? DateTime.now;

  final String? Function() _currentUid;
  final CopyCallable _call;
  final Future<void> Function(ReportClipboardData) _writeClipboard;
  final DateTime Function() _clock;
  bool _busy = false;
  // A clipboard failure may need a fresh user gesture in web browsers. Keep
  // only this short-lived, account-bound authorization for that immediate retry.
  String? _retryKey;
  DateTime? _retryUntil;
  ReportCopyAllowance? _retryAllowance;

  String _uid() {
    final uid = _currentUid();
    if (uid == null || uid.isEmpty) throw const ReportCopyException('unauthenticated');
    return uid;
  }

  Future<ReportCopyAllowance> _request(String name, String uid, Map<String, dynamic> data) async {
    try {
      final result = await _call(name, data);
      if (_currentUid() != uid) throw const ReportCopyException('account-changed');
      return ReportCopyAllowance.parse(result);
    } on FirebaseFunctionsException catch (e) {
      throw ReportCopyException(e.code);
    } on AccountFunctionException catch (e) {
      throw ReportCopyException(e.code);
    }
  }

  Future<ReportCopyAllowance> status() =>
      _request('getReportCopyAllowance', _uid(), const {});

  Future<ReportCopyAllowance> copyReport(ReportDoc doc, {AccessState? access}) {
    const renderer = ReportTextService();
    return _copy(renderer.render(doc), renderer.clipboard(doc), access: access);
  }

  Future<ReportCopyAllowance> copy(String text, {AccessState? access}) =>
      _copy(text, ReportClipboardData(text: text), access: access);

  Future<ReportCopyAllowance> _copy(String text, ReportClipboardData clipboard,
      {AccessState? access}) async {
    if (_busy) throw const ReportCopyException('busy');
    final uid = _uid();
    final key = ReportTextService.fingerprint(uid, text);
    _busy = true;
    try {
      ReportCopyAllowance allowance;
      if (_retryKey == key && _retryUntil != null &&
          _clock().isBefore(_retryUntil!) && _retryAllowance != null) {
        allowance = _retryAllowance!;
      } else if (access != null && access.hasCurrentVerification && access.isPremiumLike) {
        // Same bounded offline entitlement as the existing Premium features.
        allowance = const ReportCopyAllowance(limit: 50, remaining: 0, unlimited: true);
      } else {
        allowance = await _request('authorizeReportCopy', uid, {'fingerprint': key});
      }
      if (_currentUid() != uid) throw const ReportCopyException('account-changed');
      try {
        await _writeClipboard(clipboard);
      } catch (_) {
        _retryKey = key;
        _retryUntil = _clock().add(const Duration(seconds: 60));
        _retryAllowance = allowance;
        throw const ReportCopyException('clipboard');
      }
      _retryKey = null;
      _retryUntil = null;
      _retryAllowance = null;
      return allowance;
    } finally {
      _busy = false;
    }
  }
}
