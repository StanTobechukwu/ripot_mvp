import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/firebase/account_functions.dart';
import '../../../core/firebase/account_runtime.dart';
import '../../../core/ui/item_actions.dart';
import '../../../core/utils/ids.dart';
import '../../auth/ui/auth_screens.dart';
import '../data/public_template_catalog.dart';
import '../data/templates_repository.dart';
import '../domain/models/template_doc.dart';
import '../domain/models/nodes.dart';
import '../domain/serialization/template_codec.dart';
import '../providers/report_editor_provider.dart';
import 'report_editor_screen.dart';
import 'template_actions.dart';

class OnlineTemplatesScreen extends StatefulWidget {
  const OnlineTemplatesScreen({super.key, this.initialView = 'browse'});
  final String initialView;
  @override
  State<OnlineTemplatesScreen> createState() => _OnlineTemplatesScreenState();
}

class _OnlineTemplatesScreenState extends State<OnlineTemplatesScreen> {
  List<Map<String, dynamic>> _catalog = [], _submissions = [];
  final Set<String> _saved = {}, _savedSlugs = {};
  String _view = 'browse', _search = '', _specialty = '', _warning = '';
  String? _cursor;
  bool _busy = false, _reviewer = false;
  int _pending = 0;
  @override
  void initState() {
    super.initState();
    _view = widget.initialView == 'review' ? 'review' : 'browse';
    WidgetsBinding.instance.addPostFrameCallback((_) => _run(() async {
      await _load();
      if (widget.initialView == 'contribute' && mounted) await _contribute();
    }));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _warning = ''; });
    try { await action(); }
    catch (_) {
      if (mounted) setState(() => _warning = 'Could not complete this action. Check your connection and account, then refresh. Your saved templates are unchanged.');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _load() async {
    final repo = context.read<TemplatesRepository>();
    _saved.clear(); _savedSlugs.clear();
    for (final summary in await repo.listTemplates()) {
      final doc = await repo.loadTemplate(summary.templateId);
      if (doc.sourceSlug.isNotEmpty) {
        _saved.add('${doc.sourceSlug}:${doc.sourceVersion}');
        _savedSlugs.add(doc.sourceSlug);
      }
    }
    final page = await loadOnlineTemplates();
    if (!mounted) return;
    setState(() {
      _catalog = page.entries;
      _warning = page.unavailable.isEmpty ? '' : '${page.unavailable.join(' and ')} currently unavailable. Saved templates still work offline.';
    });
    if (AccountRuntime.session?.currentUser != null) await _loadSubmissions();
  }

  Future<bool> _signIn() async {
    if (AccountRuntime.session?.currentUser == null) {
      await openAccountSheet(context);
    }
    return mounted && AccountRuntime.session?.currentUser != null;
  }

  Future<void> _loadSubmissions({bool more = false}) async {
    final result = await AccountFunctions.call('listTemplateContributions', data: {
      'review': _view == 'review', if (more && _cursor != null) 'cursor': _cursor,
    });
    if (!mounted) return;
    setState(() {
      final rows = (result['entries'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _submissions = more ? [..._submissions, ...rows] : rows;
      _reviewer = result['reviewer'] == true;
      _pending = (result['pendingCount'] as num?)?.toInt() ?? 0;
      _cursor = result['cursor'] as String?;
    });
  }

  Future<void> _changeView(String view) async {
    if (view != 'browse' && !await _signIn()) return;
    if (!mounted) return;
    setState(() { _view = view; _submissions = []; _cursor = null; });
    if (view != 'browse') await _loadSubmissions();
  }

  Future<void> _contribute({Map<String, dynamic>? revision}) async {
    if (!await _signIn() || !mounted) return;
    final repo = context.read<TemplatesRepository>();
    final templates = await repo.listTemplates();
    if (!mounted) return;
    if (templates.isEmpty) { showMessage(context, 'Create or import a template in Templates first.'); return; }
    final selected = await showItemActions(context, 'Choose a template to contribute', [
      for (final t in templates) ItemAction(t.templateId, t.name, Icons.description_outlined),
    ]);
    if (selected == null || !mounted) return;
    final doc = await repo.loadTemplate(selected);
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TemplateContributionScreen(template: doc, revision: revision)));
    if (mounted) { setState(() => _view = 'mine'); await _loadSubmissions(); }
  }

  Future<void> _preview(Map<String, dynamic> row, {bool review = false}) async {
    final doc = review ? TemplateCodec.templateFromJson(Map<String, dynamic>.from(row['template'] as Map))
        : await PublicTemplateCatalog.resolve(Uri(queryParameters: {'template': row['slug'] as String, 'version': row['version'] as String}));
    if (!mounted) return;
    if (doc == null) { showMessage(context, 'This version could not be loaded. Please refresh the library.'); return; }
    final key = '${row['slug']}:${row['version']}';
    final action = await showDialog<String>(context: context, builder: (dialog) => AlertDialog(
      title: Text(doc.name),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${row['specialty']} · By ${row['contributor']}'),
          Text('Version ${row['version']}'),
          const SizedBox(height: 12),
          Text(row['description'] as String? ?? ''),
          const SizedBox(height: 12),
          ...templateStructure(doc),
          if (review) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Review every title, option and attribution for patient information, permission and clinical suitability before approval.')),
        ],
      ))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Close')),
        if (review) ...[
          TextButton(onPressed: () => Navigator.pop(dialog, 'changes_requested'), child: const Text('Request changes')),
          TextButton(onPressed: () => Navigator.pop(dialog, 'rejected'), child: const Text('Reject')),
          FilledButton(onPressed: () => Navigator.pop(dialog, 'approved'), child: const Text('Approve and publish')),
        ] else ...[
          TextButton(onPressed: () => Navigator.pop(dialog, 'use'), child: const Text('Use now')),
          FilledButton(onPressed: _saved.contains(key) ? null : () => Navigator.pop(dialog, 'add'), child: Text(_saved.contains(key) ? 'Already added' : _savedSlugs.contains(row['slug']) ? 'Add new version as a copy' : 'Add to my templates')),
        ],
      ],
    ));
    if (action == null || !mounted) return;
    if (review) {
      String note = '';
      if (action != 'approved') {
        final answer = await askName(context, 'Feedback for contributor');
        if (answer == null || !mounted) return;
        note = answer;
      }
      await AccountFunctions.call('reviewTemplateContribution', data: {'id': row['id'], 'revision': row['revision'], 'decision': action, 'note': note});
      if (mounted) { showMessage(context, action == 'approved' ? 'Approved and published to the library.' : 'Review saved. The contributor can see your feedback in My submissions.'); await _loadSubmissions(); }
    } else if (action == 'use') {
      context.read<ReportEditorProvider>().newReportFromTemplate(doc);
      await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ReportEditorScreen()));
    } else if (await canAddTemplate(context) && mounted) {
      await context.read<TemplatesRepository>().saveTemplate(TemplateDoc(
        templateId: newId('tpl'), updatedAt: DateTime.now(), name: doc.name,
        roots: doc.roots, subjectInfo: doc.subjectInfo, sourceSlug: doc.sourceSlug,
        sourceVersion: doc.sourceVersion, contributor: doc.contributor,
      ));
      if (mounted) {
        setState(() { _saved.add(key); _savedSlugs.add(doc.sourceSlug); });
        showMessage(context, 'Added to your templates. This personal copy is available offline.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final specialties = _catalog.map((e) => e['specialty'] as String? ?? '').where((e) => e.isNotEmpty).toSet().toList()..sort();
    final entries = _catalog.where((e) => (_specialty.isEmpty || e['specialty'] == _specialty) &&
      '${e['name']} ${e['specialty']} ${e['contributor']}'.toLowerCase().contains(_search.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Online template library'), actions: [IconButton(tooltip: 'Refresh library', onPressed: _busy ? null : () => _run(_load), icon: const Icon(Icons.refresh))]),
      body: SafeArea(child: Column(children: [
        if (_busy) const LinearProgressIndicator(),
        Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(label: const Text('Browse'), selected: _view == 'browse', onSelected: _busy ? null : (_) => _run(() => _changeView('browse'))),
          ChoiceChip(label: const Text('My submissions'), selected: _view == 'mine', onSelected: _busy ? null : (_) => _run(() => _changeView('mine'))),
          if (_reviewer || _view == 'review') ChoiceChip(label: Text('Review ($_pending pending)'), selected: _view == 'review', onSelected: _busy ? null : (_) => _run(() => _changeView('review'))),
          OutlinedButton.icon(onPressed: _busy ? null : () => _run(_contribute), icon: const Icon(Icons.upload_outlined), label: const Text('Contribute a template')),
        ])),
        if (_warning.isNotEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(_warning)),
        if (_view == 'browse') ...[
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(decoration: const InputDecoration(labelText: 'Search templates', prefixIcon: Icon(Icons.search)), onChanged: (s) => setState(() => _search = s))),
          Padding(padding: const EdgeInsets.all(16), child: DropdownButtonFormField<String>(
            key: ValueKey('$_specialty:${specialties.join(',')}'), initialValue: specialties.contains(_specialty) ? _specialty : '',
            decoration: const InputDecoration(labelText: 'Specialty'),
            items: [const DropdownMenuItem(value: '', child: Text('All specialties')), for (final s in specialties) DropdownMenuItem(value: s, child: Text(s))],
            onChanged: (s) => setState(() => _specialty = s ?? ''),
          )),
        ],
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: _view == 'browse' ? [
          if (entries.isEmpty && !_busy) const Text('No templates match. Try another search or refresh.'),
          for (final row in entries) Card(child: ListTile(
            title: Text(row['name'] as String), subtitle: Text('${row['specialty']} · By ${row['contributor']}\n${_saved.contains('${row['slug']}:${row['version']}') ? 'Already added' : _savedSlugs.contains(row['slug']) ? 'New version available' : 'Preview and add'}'),
            trailing: const Icon(Icons.chevron_right), onTap: _busy ? null : () => _run(() => _preview(row)),
          )),
        ] : [
          if (_submissions.isEmpty && !_busy) const Text('No submissions to show. Sign in to view your submissions or reviewer queue.'),
          for (final row in _submissions) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row['name'] as String, style: Theme.of(context).textTheme.titleMedium),
            Text('${row['contributor']} · Revision ${row['revision']} · ${(row['status'] as String).replaceAll('_', ' ')}'),
            if ((row['reviewerNote'] as String? ?? '').isNotEmpty) Text('Feedback: ${row['reviewerNote']}'),
            if (_view == 'review') TextButton(onPressed: _busy ? null : () => _run(() => _preview(row, review: true)), child: const Text('Preview and review')),
            if (_view == 'mine' && row['status'] != 'pending') TextButton(onPressed: _busy ? null : () => _run(() => _contribute(revision: row)), child: Text(row['status'] == 'approved' ? 'Submit updated version' : 'Revise and resubmit')),
          ]))),
          if (_cursor != null) TextButton(onPressed: _busy ? null : () => _run(() => _loadSubmissions(more: true)), child: const Text('Load more')),
        ])),
      ])),
    );
  }
}

List<Widget> templateStructure(TemplateDoc doc) {
  final widgets = <Widget>[];
  void visit(SectionNode section, int depth) {
    widgets.add(Padding(padding: EdgeInsets.only(left: depth * 12, top: 8), child: Text('${section.title} (${section.inputType.name})${section.unit.isEmpty ? '' : ' · ${section.unit}'}${section.options.isEmpty ? '' : '\nOptions: ${section.options.join(', ')}'}${section.conditionalParentSectionId.isEmpty ? '' : '\nShown when ${section.conditionalParentSectionId} = ${section.conditionalEquals}'}')));
    for (final child in section.children) { if (child is SectionNode) visit(child, depth + 1); }
  }
  for (final root in doc.roots) { visit(root, 0); }
  return widgets;
}

class TemplateContributionScreen extends StatefulWidget {
  const TemplateContributionScreen({super.key, required this.template, this.revision});
  final TemplateDoc template;
  final Map<String, dynamic>? revision;
  @override
  State<TemplateContributionScreen> createState() => _TemplateContributionScreenState();
}
class _TemplateContributionScreenState extends State<TemplateContributionScreen> {
  final _form = GlobalKey<FormState>();
  final _requestId = newId('submission');
  final Map<String, String> _fields = {};
  bool _patientFree = false, _permission = false, _busy = false;
  String _error = '';
  @override
  void initState() {
    super.initState();
    for (final key in ['name','specialty','description','contributor']) { _fields[key] = widget.revision?[key] as String? ?? (key == 'name' ? widget.template.name : ''); }
  }
  Future<void> _submit() async {
    if (!_form.currentState!.validate() || !_patientFree || !_permission) return;
    setState(() { _busy = true; _error = ''; });
    try {
      // Strip report content locally as well as on the server; never upload signatures.
      final clean = TemplateCodec.templateToJson(widget.template.copyWith(roots: widget.template.roots.map((r) => r.toTemplateNode(includeContent: false)).toList()));
      clean.remove('signature'); clean.remove('subjectInfo');
      await AccountFunctions.call('submitTemplateContribution', data: {
        ..._fields, 'requestId': _requestId, 'template': clean, 'patientFree': true, 'permissionToPublish': true,
        if (widget.revision != null) 'id': widget.revision!['id'],
        if (widget.revision != null) 'revision': widget.revision!['revision'],
      });
      if (mounted) { showMessage(context, 'Submitted for review. Track the decision in My submissions.'); Navigator.pop(context); }
    } catch (_) { if (mounted) setState(() => _error = 'Submission failed. Check your connection and sign-in. You can retry safely. If this is a revision, refresh My submissions first.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Contribute a template')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: Form(key: _form, child: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Share a useful reporting structure. Your submission stays private until a reviewer approves it. Public credit appears exactly as entered below.'),
      const SizedBox(height: 12),
      for (final entry in {'name':'Template name','specialty':'Specialty','description':'Description and intended use','contributor':'Public contributor name'}.entries)
        Padding(padding: const EdgeInsets.only(bottom: 12), child: TextFormField(initialValue: _fields[entry.key], enabled: !_busy, decoration: InputDecoration(labelText: entry.value), maxLength: entry.key == 'description' ? 1500 : entry.key == 'specialty' ? 80 : 120, maxLines: entry.key == 'description' ? 3 : 1, onChanged: (v) => _fields[entry.key] = v.trim(), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null)),
      const Text('Structure to be submitted', style: TextStyle(fontWeight: FontWeight.bold)),
      ...templateStructure(widget.template),
      const SizedBox(height: 16),
      const Text('Report values, signatures and custom subject fields are removed. Check titles, options, units and the text above: they must contain no patient information.'),
      CheckboxListTile(value: _patientFree, onChanged: _busy ? null : (v) => setState(() => _patientFree = v ?? false), title: const Text('I checked this structure and it contains no patient information.')),
      CheckboxListTile(value: _permission, onChanged: _busy ? null : (v) => setState(() => _permission = v ?? false), title: const Text('I have permission to share this template and allow Ripot to publish it with my contributor credit.')),
      if (_error.isNotEmpty) Text(_error),
      FilledButton(onPressed: _busy || !_patientFree || !_permission ? null : _submit, child: Text(_busy ? 'Submitting…' : 'Submit for review')),
    ])))),
  );
}
