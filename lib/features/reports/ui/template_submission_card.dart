import 'package:flutter/material.dart';
import '../data/template_contribution_service.dart';

/// Actions belong to a single submission, never the whole library.
class TemplateSubmissionCard extends StatelessWidget {
  const TemplateSubmissionCard({
    super.key,
    required this.row,
    this.busy = false,
    this.onReview,
    this.onRevise,
    this.onWithdraw,
  });

  final Map<String, dynamic> row;
  final bool busy;
  final VoidCallback? onReview, onRevise, onWithdraw;

  @override
  Widget build(BuildContext context) {
    final status = row['status'] as String;
    final note = row['reviewerNote'] as String? ?? '';
    final ownReview = onReview != null && row['isOwn'] == true;
    return Card(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(row['name'] as String,
              style: Theme.of(context).textTheme.titleMedium)),
          if (status == 'pending' && onWithdraw != null)
            PopupMenuButton<String>(
              tooltip: 'Submission options',
              enabled: !busy,
              icon: const Icon(Icons.more_vert),
              onSelected: (_) => onWithdraw!(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'withdraw', child: Text('Withdraw submission')),
              ],
            ),
        ]),
        Text('${row['contributor']} · Revision ${row['revision']} · ${status.replaceAll('_', ' ')}'),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(status == 'rejected' ? 'Reason for rejection' : 'Reviewer feedback',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          SelectableText(note),
        ],
        if (status == 'withdrawn')
          const Text('Removed from review. Your saved template is unchanged.'),
        if (ownReview)
          const Padding(padding: EdgeInsets.only(top: 8), child: Text(
            'Your submission. Another reviewer must review it. You can withdraw it from My submissions.',
          )),
        if (onReview != null && !ownReview)
          TextButton(onPressed: busy ? null : onReview,
              child: const Text('Preview and review')),
        if (status != 'pending' && onRevise != null)
          TextButton(onPressed: busy ? null : onRevise,
              child: Text(status == 'approved' ? 'Submit updated version' :
                  status == 'withdrawn' ? 'Resubmit template' : 'Revise and resubmit')),
      ]),
    ));
  }
}

class TemplateWithdrawalDialog extends StatefulWidget {
  const TemplateWithdrawalDialog({super.key, required this.name, required this.submit});
  final String name;
  final Future<void> Function() submit;

  @override
  State<TemplateWithdrawalDialog> createState() => _TemplateWithdrawalDialogState();
}

class _TemplateWithdrawalDialogState extends State<TemplateWithdrawalDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _withdraw() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await widget.submit();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() {
        _error = templateContributionError(error);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Withdraw submission?'),
      content: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Remove “${widget.name}” from the review queue? Your saved template and any previously published version will be kept. You can resubmit later.'),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(liveRegion: true, child: Text(_error!)),
          ),
        ],
      )),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Keep submission')),
        FilledButton(onPressed: _busy ? null : _withdraw,
            child: Text(_busy ? 'Withdrawing…' : 'Withdraw submission')),
      ],
    ),
  );
}
