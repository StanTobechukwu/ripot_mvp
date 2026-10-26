import 'package:flutter/material.dart';
import '../data/template_contribution_service.dart';

/// Keeps review feedback and server errors in the same dialog until saved.
class TemplateReviewDialog extends StatefulWidget {
  const TemplateReviewDialog({
    super.key,
    required this.title,
    required this.submissionId,
    required this.revision,
    required this.preview,
    required this.submit,
  });

  final String title;
  final String submissionId;
  final int revision;
  final List<Widget> preview;
  final Future<void> Function(Map<String, dynamic> data) submit;

  @override
  State<TemplateReviewDialog> createState() => _TemplateReviewDialogState();
}

class _TemplateReviewDialogState extends State<TemplateReviewDialog> {
  final _form = GlobalKey<FormState>();
  final _feedback = TextEditingController();
  String? _decision;
  String _error = '';
  bool _saving = false;

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  void _choose(String? decision) {
    setState(() { _decision = decision; _error = ''; });
  }

  Future<void> _save() async {
    if (_saving || _decision == null) return;
    if (_decision != 'approved' && !_form.currentState!.validate()) return;
    setState(() { _saving = true; _error = ''; });
    try {
      await widget.submit({
        'id': widget.submissionId,
        'revision': widget.revision,
        'decision': _decision,
        'note': _decision == 'approved' ? '' : _feedback.text.trim(),
        'patientFreeReviewed': _decision == 'approved',
      });
      if (mounted) Navigator.of(context).pop(_decision);
    } catch (error) {
      if (mounted) setState(() => _error = templateContributionError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final approving = _decision == 'approved';
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(_decision == null ? widget.title : approving
            ? 'Confirm publication' : _decision == 'rejected'
                ? 'Reject template' : 'Request template changes'),
        scrollable: true,
        content: SizedBox(width: 560, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_decision == null) ...[
              ...widget.preview,
              const SizedBox(height: 12),
              const Text('Review every title, option and attribution for patient information, permission and clinical suitability before approval. Another reviewer must review your own contribution.'),
            ] else if (approving)
              const Text('I reviewed all titles, options, units, descriptions and contributor credit. This structure contains no patient information, has permission for publication and is suitable for the stated documentation purpose.')
            else ...[
              Text(_decision == 'rejected'
                  ? 'Explain why this template is being rejected. The contributor will see this feedback in My submissions.'
                  : 'Describe what needs to change. The contributor can revise the template and resubmit it.'),
              const SizedBox(height: 12),
              Form(key: _form, child: TextFormField(
                controller: _feedback,
                enabled: !_saving,
                minLines: 3,
                maxLines: 6,
                maxLength: 1500,
                decoration: const InputDecoration(labelText: 'Feedback for contributor', border: OutlineInputBorder()),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Enter feedback before saving this review.' : null,
              )),
            ],
            if (_saving) const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Saving review…'),
            ),
            if (_error.isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(liveRegion: true, child: Text(_error,
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ),
          ],
        )),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (_decision == null) ...[
            TextButton(onPressed: () => _choose('changes_requested'), child: const Text('Request changes')),
            TextButton(onPressed: () => _choose('rejected'), child: const Text('Reject')),
            FilledButton(onPressed: () => _choose('approved'), child: const Text('Approve and publish')),
          ] else ...[
            TextButton(onPressed: _saving ? null : () => _choose(null), child: const Text('Back')),
            FilledButton(onPressed: _saving ? null : _save, child: Text(
              approving ? 'Confirmed — publish' : _decision == 'rejected'
                  ? 'Confirm rejection' : 'Send feedback')),
          ],
        ],
      ),
    );
  }
}
