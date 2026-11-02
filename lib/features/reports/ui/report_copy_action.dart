import 'package:flutter/material.dart';

import '../../access/domain/access_state.dart';
import '../domain/models/report_doc.dart';
import '../services/report_copy_service.dart';
import '../services/report_text_service.dart';

class ReportCopyAction extends StatefulWidget {
  const ReportCopyAction({super.key, required this.doc, required this.accountUid,
    required this.access, required this.onSignIn, required this.onUpgrade, this.service});
  final ReportDoc doc;
  final String? accountUid;
  final AccessState access;
  final Future<void> Function() onSignIn;
  final Future<void> Function() onUpgrade;
  final ReportCopyService? service;

  @override
  State<ReportCopyAction> createState() => _ReportCopyActionState();
}

class _ReportCopyActionState extends State<ReportCopyAction> {
  late final ReportCopyService _service = widget.service ?? ReportCopyService();
  ReportCopyAllowance? _allowance;
  bool _busy = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(ReportCopyAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountUid != widget.accountUid ||
        oldWidget.access.isPremiumLike != widget.access.isPremiumLike) {
      _allowance = null;
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    if (widget.accountUid == null) return;
    try {
      final result = await _service.status();
      if (mounted && generation == _generation) {
        setState(() => _allowance = result);
      }
    } catch (_) {
      // Do not infer a fresh allowance from an unavailable server. Copy can
      // retry verification, or use an existing bounded Premium entitlement.
    }
  }

  void _message(String message, {bool upgrade = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      action: upgrade ? SnackBarAction(label: 'View Premium', onPressed: widget.onUpgrade) : null,
    ));
  }

  Future<void> _copy() async {
    if (widget.accountUid == null) {
      await widget.onSignIn();
      return;
    }
    if (_busy) return;
    ++_generation; // A slower status read must not overwrite this copy's count.
    final uid = widget.accountUid;
    setState(() => _busy = true);
    try {
      final result = await _service.copy(const ReportTextService().render(widget.doc), access: widget.access);
      if (!mounted || widget.accountUid != uid) return;
      setState(() => _allowance = result);
      final warning = !result.unlimited && result.charged &&
          {10, 5, 1, 0}.contains(result.remaining);
      _message(result.unlimited ? 'Complete draft text copied.' :
        'Complete draft text copied. ${result.remaining} free report versions remaining.'
        '${result.repeated ? ' This repeat used no additional copy.' : ''}'
        '${warning ? ' Premium includes unlimited report copying.' : ''}',
        upgrade: warning);
    } on ReportCopyException catch (error) {
      if (!mounted || widget.accountUid != uid) return;
      switch (error.code) {
        case 'resource-exhausted':
          setState(() => _allowance = const ReportCopyAllowance(limit: 50, remaining: 0));
          _message('Your 50 free report versions have been used. Previously copied, unchanged versions are still free.', upgrade: true);
          break;
        case 'clipboard':
          _message('Clipboard access failed. Tap Copy report again. Retrying this unchanged version uses no additional copy.');
          _refresh();
          break;
        case 'unauthenticated':
        case 'account-changed':
          _message('Please sign in again, then retry copying.');
          break;
        case 'busy':
          break;
        default:
          _message('Copy allowance could not be verified. Connect to the internet and try again. Your draft is unchanged.');
      }
    } catch (_) {
      if (mounted && widget.accountUid == uid) {
        _message('Copy allowance could not be verified. Connect to the internet and try again. Your draft is unchanged.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final premium = widget.access.hasCurrentVerification && widget.access.isPremiumLike;
    final status = widget.accountUid == null
        ? 'Sign in for 50 free report versions.'
        : premium || _allowance?.unlimited == true
        ? 'Unlimited report copying with active Premium or trial.'
        : _allowance == null
        ? '50 free report versions per account; allowance checked online.'
        : '${_allowance!.remaining} of 50 free report versions remaining.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : _copy,
            icon: _busy ? const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.copy_all_outlined),
            label: const Text('Copy report'),
          ),
          Text('$status\nUnchanged text counts once. The allowance does not reset.',
            style: Theme.of(context).textTheme.bodySmall),
          Tooltip(
            triggerMode: TooltipTriggerMode.tap,
            message: 'Copies the complete draft as plain text. Changed report text uses another free copy. Images, handwritten signatures and letterhead layout need PDF export.',
            child: const Icon(Icons.info_outline, size: 20, semanticLabel: 'About copying report text'),
          ),
        ],
      ),
    );
  }
}
