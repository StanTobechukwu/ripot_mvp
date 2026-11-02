import 'package:flutter/material.dart';

import '../../access/domain/access_state.dart';
import '../domain/models/report_doc.dart';
import '../services/report_copy_service.dart';

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
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
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
      final result = await _service.copyReport(widget.doc, access: widget.access);
      if (!mounted || widget.accountUid != uid) return;
      setState(() => _allowance = result);
      final warning = !result.unlimited && result.charged &&
          {10, 5, 1, 0}.contains(result.remaining);
      _message(warning
          ? 'Report copied. ${result.remaining == 1 ? '1 free copy left' : '${result.remaining} free copies left'}.'
          : 'Report copied.',
        upgrade: warning);
    } on ReportCopyException catch (error) {
      if (!mounted || widget.accountUid != uid) return;
      switch (error.code) {
        case 'resource-exhausted':
          setState(() => _allowance = const ReportCopyAllowance(limit: 50, remaining: 0));
          _message('No free copies left. You can still copy reports you copied before if their text has not changed.', upgrade: true);
          break;
        case 'clipboard':
          _message('Could not copy. Tap Copy report to retry; you will not be charged twice.');
          _refresh();
          break;
        case 'unauthenticated':
        case 'account-changed':
          _message('Please sign in again, then retry copying.');
          break;
        case 'busy':
          break;
        default:
          _message('Connect to the internet to check your free copies, then try again.');
      }
    } catch (_) {
      if (mounted && widget.accountUid == uid) {
        _message('Connect to the internet to check your free copies, then try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showCopyInfo() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('About copying reports'),
      scrollable: true,
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Formatting', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('Copies the whole draft, with headings, spacing and alignment where the receiving app supports them. Plain-text fields keep the text only. Use PDF for the exact page layout, images and signatures.'),
          SizedBox(height: 20),
          Text('Free copies', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('Your account includes 50 free copies in total. They do not renew.\n\nCopying the same report again is free until you change its text. Copying after a text change uses another free copy.\n\nPremium includes unlimited copies.'),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final premium = widget.access.hasCurrentVerification && widget.access.isPremiumLike;
    final status = widget.accountUid == null
        ? 'Sign in to copy'
        : premium || _allowance?.unlimited == true
        ? 'Unlimited copies'
        : _allowance == null
        ? 'Free copies checked online'
        : _allowance!.remaining == 1 ? '1 free copy left'
        : '${_allowance!.remaining} free copies left';
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(status, style: Theme.of(context).textTheme.bodySmall)),
              IconButton(
                tooltip: 'About copying reports',
                onPressed: _showCopyInfo,
                icon: const Icon(Icons.info_outline, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
