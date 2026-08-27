import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/ids.dart';
import '../../../core/utils/time.dart';

import '../data/reports_repository.dart';
import '../data/templates_repository.dart';

import '../domain/models/nodes.dart';
import '../domain/models/report_doc.dart';
import '../domain/models/template_doc.dart';
import '../domain/models/subject_info_def.dart';
import '../domain/models/subject_info_value.dart';

class ReportEditorProvider extends ChangeNotifier {
  final ReportsRepository repo;
  final TemplatesRepository templatesRepo;

  static const String _savedSignaturePrefsKey = 'reports.savedSignatureBlock';

  late ReportDoc _doc;

  /// Selected node can be a SectionNode OR ContentNode id.
  String? _selectedNodeId;

  ReportEditorProvider({required this.repo, required this.templatesRepo}) {
    newReport();
  }

  // =========================================================
  // ✅ Provider is MODEL-ONLY (no TextEditingControllers)
  // Controllers/focus nodes live in the UI layer to avoid
  // disposal races during rebuilds.
  // =========================================================

  bool _hasUnsavedChanges = false;

  bool get hasUnsavedChanges => _hasUnsavedChanges;

  void _markDirty() {
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void _commit({bool dirty = true}) {
    if (dirty) _hasUnsavedChanges = true;
    notifyListeners();
  }

  // =========================
  // Getters
  // =========================

  ReportDoc get doc => _doc;
  String? get selectedNodeId => _selectedNodeId;

  SubjectInfoBlockDef get subjectInfoDef => _doc.subjectInfoDef;
  SubjectInfoValues get subjectInfoValues => _doc.subjectInfo;

  bool get selectedIsSection {
    final id = _selectedNodeId;
    if (id == null) return false;
    return _findNodeById(_doc.roots, id) is SectionNode;
  }

  bool get selectedIsContent {
    final id = _selectedNodeId;
    if (id == null) return false;
    return _findNodeById(_doc.roots, id) is ContentNode;
  }

  /// ✅ RULES:
  /// - Subsections can ALWAYS be added to a SectionNode (even if it already has intro content)
  /// - Content can be added only if the section has NO content yet (max 1 content per section)
  bool get canAddSubsectionHere {
    final id = _selectedNodeId;
    if (id == null) return false;
    final n = _findNodeById(_doc.roots, id);
    return n is SectionNode;
  }

  bool get canAddContentHere {
    final id = _selectedNodeId;
    if (id == null) return false;

    final n = _findNodeById(_doc.roots, id);
    if (n is! SectionNode) return false;

    // ✅ only one content per section (intro OR leaf content)
    return !_sectionHasContentChild(n);
  }

  // =========================
  // Selection
  // =========================

  void selectNode(String? id) {
    _selectedNodeId = id;
    notifyListeners();
  }

  void clearSelection() => selectNode(null);

  // =========================
  // Create / Load / Save
  // =========================

  ReportDoc _newEmptyDoc() {
    final now = nowIso();
    return ReportDoc(
      reportId: newId('rpt'),
      createdAtIso: now,
      updatedAtIso: now,
      roots: const [],
      images: const [],
      placementChoice: ImagePlacementChoice.inlinePage1,
      signature: const SignatureBlock(),
      subjectInfoDef: SubjectInfoBlockDef.kDefaults,
      subjectInfo: const SubjectInfoValues({}),
    );
  }

  void newReport() {
    _doc = _newEmptyDoc();
    _selectedNodeId = null;
    _hasUnsavedChanges = false;
    _commit(dirty: false); // ✅ prune + notify
    _applySavedSignatureToCurrentReportIfEmpty();
  }

  void newReportFromTemplate(TemplateDoc template) {
    final now = nowIso();

    // 1) Deep-clone template structure
    final cloned = template.roots
        .map((s) => s.cloneNodeTree())
        .toList(growable: false);

    // 2) Hydrate leaf sections with exactly one content node (Form Mode)
    final hydrated = cloned
        .map(_hydrateTemplateSectionForForm)
        .toList(growable: false);

    _doc = ReportDoc(
      reportId: newId('rpt'),
      createdAtIso: now,
      updatedAtIso: now,
      roots: hydrated,
      images: const [],
      placementChoice: ImagePlacementChoice.inlinePage1,
      signature: template.signature,
      subjectInfoDef: template.subjectInfo,
      subjectInfo: SubjectInfoValues.emptyFromDef(template.subjectInfo),
    );

    _selectedNodeId = null;
    _hasUnsavedChanges = true;
    _commit(); // ✅ prune + notify
    if (_isEmptySignature(template.signature)) {
      _applySavedSignatureToCurrentReportIfEmpty(preserveDirty: true);
    }
  }

  Future<void> save() async {
    _doc = _doc.copyWith(updatedAtIso: nowIso());
    await repo.saveReport(_doc);
    _hasUnsavedChanges = false;
    notifyListeners();
  }

  Future<void> autoSaveDraft() async {
    if (!_hasUnsavedChanges) return;
    _doc = _doc.copyWith(updatedAtIso: nowIso());
    await repo.saveReport(_doc);
    _hasUnsavedChanges = false;
    notifyListeners();
  }

  Future<void> loadById(String reportId) async {
    final loaded = await repo.loadReport(reportId);
    _doc = loaded;
    _selectedNodeId = null;
    _hasUnsavedChanges = false;
    _commit(dirty: false); // ✅ prune + notify (structure changed)
  }

  Future<void> duplicateFromExisting(String reportId) async {
    final loaded = await repo.loadReport(reportId);
    final now = nowIso();
    _doc = ReportDoc(
      reportId: newId('rpt'),
      createdAtIso: now,
      updatedAtIso: now,
      reportTitle: loaded.reportTitle,
      roots: loaded.roots.map((s) => s.cloneNodeTree()).toList(growable: false),
      images: loaded.images
          .map(
            (i) => ImageAttachment(
              id: newId('img'),
              filePath: i.filePath,
              label: i.label,
            ),
          )
          .toList(growable: false),
      placementChoice: loaded.placementChoice,
      reportLayout: loaded.reportLayout,
      indentContent: loaded.indentContent,
      indentHierarchy: loaded.indentHierarchy,
      showColonAfterTitlesWithContent: loaded.showColonAfterTitlesWithContent,
      fontScale: loaded.fontScale,
      signature: loaded.signature,
      letterheadMode: loaded.letterheadMode,
      applyLetterhead: loaded.applyLetterhead,
      letterheadId: loaded.letterheadId,
      prePrintedTopSpacing: loaded.prePrintedTopSpacing,
      reservePrePrintedFooter: loaded.reservePrePrintedFooter,
      subjectInfoDef: loaded.subjectInfoDef,
      subjectInfo: SubjectInfoValues.emptyFromDef(loaded.subjectInfoDef),
    );
    _selectedNodeId = null;
    _hasUnsavedChanges = true;
    _commit();
  }

  Future<void> loadTemplateAndStartReport(String templateId) async {
    final template = await templatesRepo.loadTemplate(templateId);
    newReportFromTemplate(template);
  }

  // =========================
  // ✅ Form Mode helper
  // =========================

  /// Ensures a leaf section has exactly ONE ContentNode.
  /// Safe to call repeatedly (no duplicates created).
  void ensureLeafHasContent(String sectionId) {
    final s = _findSectionById(_doc.roots, sectionId);
    if (s == null) return;

    // only leaf sections get content
    if (_sectionHasSectionChildren(s)) return;

    final contentNodes = s.children.whereType<ContentNode>().toList();
    if (contentNodes.isNotEmpty) {
      // already has one -> enforce exactly one by keeping first
      if (contentNodes.length == 1 && s.children.length == 1) return;

      final keep = contentNodes.first;
      _doc = _doc.copyWith(
        roots: _updateSectionTree(
          _doc.roots,
          sectionId,
          (sec) => sec.copyWith(children: [keep], collapsed: false),
        ),
        updatedAtIso: nowIso(),
      );
      _commit();
      return;
    }

    // create one
    final newTxt = ContentNode(id: _id('txt'), text: '', indent: s.indent);
    _doc = _doc.copyWith(
      roots: _updateSectionTree(
        _doc.roots,
        sectionId,
        (sec) => sec.copyWith(children: [newTxt], collapsed: false),
      ),
      updatedAtIso: nowIso(),
    );
    _commit();
  }

  // =========================
  // Subject Info (schema + values)
  // =========================

  void updateSubjectInfoValue(String fieldKey, String value) {
    _doc = _doc.copyWith(
      subjectInfo: _doc.subjectInfo.copyWithValue(fieldKey, value),
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  void setSubjectInfoEnabled(bool enabled) {
    _doc = _doc.copyWith(
      subjectInfoDef: _doc.subjectInfoDef.copyWith(enabled: enabled),
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  void setSubjectInfoColumns(int columns) {
    _doc = _doc.copyWith(
      subjectInfoDef: _doc.subjectInfoDef.copyWith(columns: columns),
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  void addSubjectField({String title = 'New field', bool required = false}) {
    final fields = _doc.subjectInfoDef.fields;
    final nextOrder = _nextOrder(fields);
    final key = _generateCustomFieldKey();

    final field = SubjectFieldDef(
      key: key,
      title: title.trim().isEmpty ? 'New field' : title.trim(),
      required: required,
      order: nextOrder,
      isSystem: false,
    );

    _doc = _doc.copyWith(
      subjectInfoDef: _doc.subjectInfoDef.copyWith(fields: [...fields, field]),
      subjectInfo: _doc.subjectInfo.copyWithValue(key, ''),
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  void setSubjectInfoHeading(String heading) {
    _doc = _doc.copyWith(
      subjectInfoDef: _doc.subjectInfoDef.copyWith(heading: heading.trim()),
    );
    _markDirty();
  }

  void removeSubjectField(String fieldKey) {
    final fields = _doc.subjectInfoDef.fields;
    final target = fields.firstWhere(
      (f) => f.key == fieldKey,
      orElse: () => const SubjectFieldDef(
        key: '',
        title: '',
        required: false,
        order: 0,
        isSystem: false,
      ),
    );
    if (target.key.isEmpty) return;
    if (target.isSystem) return;

    final nextFields = fields.where((f) => f.key != fieldKey).toList();

    final nextValues = Map<String, String>.from(_doc.subjectInfo.values);
    nextValues.remove(fieldKey);

    _doc = _doc.copyWith(
      subjectInfoDef: _doc.subjectInfoDef.copyWith(fields: nextFields),
      subjectInfo: SubjectInfoValues(nextValues),
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  void renameSubjectField(String fieldKey, String title) {
    final t = title.trim();
    if (t.isEmpty) return;

    final nextFields = _doc.subjectInfoDef.fields.map((f) {
      return f.key == fieldKey ? f.copyWith(title: t) : f;
    }).toList();

    _doc = _doc.copyWith(
      subjectInfoDef: _doc.subjectInfoDef.copyWith(fields: nextFields),
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  void toggleSubjectRequired(String fieldKey, bool required) {
    final nextFields = _doc.subjectInfoDef.fields.map((f) {
      return f.key == fieldKey ? f.copyWith(required: required) : f;
    }).toList();

    _doc = _doc.copyWith(
      subjectInfoDef: _doc.subjectInfoDef.copyWith(fields: nextFields),
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  void reorderSubjectFields(int oldIndex, int newIndex) {
    final ordered = [..._doc.subjectInfoDef.orderedFields];

    if (oldIndex < 0 || oldIndex >= ordered.length) return;
    if (newIndex < 0 || newIndex > ordered.length) return;
    if (newIndex > oldIndex) newIndex -= 1;

    final item = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, item);

    final resequenced = <SubjectFieldDef>[];
    for (int i = 0; i < ordered.length; i++) {
      resequenced.add(ordered[i].copyWith(order: i));
    }

    _doc = _doc.copyWith(
      subjectInfoDef: _doc.subjectInfoDef.copyWith(fields: resequenced),
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  int _nextOrder(List<SubjectFieldDef> fields) {
    if (fields.isEmpty) return 0;
    final maxOrder = fields.map((f) => f.order).reduce((a, b) => a > b ? a : b);
    return maxOrder + 1;
  }

  String _generateCustomFieldKey() {
    final r = Random();
    final chunk = List.generate(
      8,
      (_) => r.nextInt(36).toRadixString(36),
    ).join();
    return 'custom_$chunk';
  }

  // =========================
  // Template save
  // =========================

  Future<void> saveAsTemplate({
    required String name,
    required bool includeContent,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final t = TemplateDoc(
      templateId: newId('tpl'),
      updatedAt: DateTime.now(),
      name: trimmed,
      roots: _doc.roots
          .map((r) => r.toTemplateNode(includeContent: includeContent))
          .toList(growable: false),
      subjectInfo: _doc.subjectInfoDef,
      signature: _doc.signature,
    );

    await templatesRepo.saveTemplate(t);
  }

  // =========================
  // Report Title
  // =========================

  void setReportTitle(String v) {
    _doc = _doc.copyWith(reportTitle: v, updatedAtIso: nowIso());
    _markDirty();
  }

  void setReportDate(DateTime date) {
    final current = DateTime.tryParse(_doc.reportDateIso) ?? DateTime.now();
    final normalized = DateTime(
      date.year,
      date.month,
      date.day,
      current.hour,
      current.minute,
      current.second,
    ).toIso8601String();

    _doc = _doc.copyWith(reportDateIso: normalized, updatedAtIso: nowIso());
    _markDirty();
  }

  // =========================
  // Template -> Report hydration (Form Mode)
  // =========================

  SectionNode _hydrateTemplateSectionForForm(SectionNode s) {
    final sectionKids = s.children.whereType<SectionNode>().toList(
      growable: false,
    );
    final contentKids = s.children.whereType<ContentNode>().toList(
      growable: false,
    );

    final hasChildDependingOnThisSection = sectionKids.any(
      (child) => child.conditionalParentSectionId == s.id,
    );

    // Some sections are pure containers/headings. Others are "section-as-field":
    // they have their own input value AND may also contain child sections.
    // Example:
    //   Biopsy = Yes/No
    //     From = Antrum
    // Previously, once a section had child sections, its own ContentNode was
    // dropped during template hydration. That made the editor show
    // "Preparing field..." and broke conditional children that depended on the
    // parent section's value. Preserve/create the parent content only when the
    // section is actually configured like a field.
    final shouldHaveOwnContent =
        contentKids.isNotEmpty ||
        s.inputType != FieldInputType.freeText ||
        s.options.any((e) => e.trim().isNotEmpty) ||
        s.addToRecords ||
        hasChildDependingOnThisSection;

    final hydratedChildren = <Node>[];

    if (shouldHaveOwnContent) {
      hydratedChildren.add(
        contentKids.isNotEmpty
            ? contentKids.first
            : ContentNode(id: '${s.id}_content', text: '', indent: s.indent),
      );
    }

    hydratedChildren.addAll(sectionKids.map(_hydrateTemplateSectionForForm));

    if (hydratedChildren.isEmpty) {
      hydratedChildren.add(
        ContentNode(id: '${s.id}_content', text: '', indent: s.indent),
      );
    }

    return s.copyWith(
      children: hydratedChildren.toList(growable: false),
      collapsed: false,
    );
  }

  bool _sectionHasSectionChildren(SectionNode s) =>
      s.children.any((n) => n is SectionNode);
  bool _sectionHasContentChild(SectionNode s) =>
      s.children.any((n) => n is ContentNode);

  // =========================
  // Tree: IDs
  // =========================

  String _id(String prefix) => newId(prefix);

  TitleStyle _defaultTitleStyleForIndent(int indent) {
    return TitleStyle(bold: indent == 0);
  }

  // =========================
  // Tree: Global Add (structure)
  // =========================

  void addTopLevelSection(String title) {
    final t = title.trim();
    if (t.isEmpty) return;

    final sec = SectionNode(
      id: _id('sec'),
      title: t,
      indent: 0,
      style: _defaultTitleStyleForIndent(0),
    );

    _doc = _doc.copyWith(roots: [..._doc.roots, sec], updatedAtIso: nowIso());
    _commit(); // ✅ prune + notify
  }

  void addSameLevelSection(String title) {
    final t = title.trim();
    final targetId = _selectedNodeId;
    if (t.isEmpty || targetId == null) return;

    final selected = _findNodeById(_doc.roots, targetId);
    final effectiveTargetId = (selected is ContentNode)
        ? _findOwningSectionId(_doc.roots, targetId) ?? targetId
        : targetId;

    final targetSection = _findNodeById(_doc.roots, effectiveTargetId);
    final indent = targetSection is SectionNode ? targetSection.indent : 0;
    final newSec = SectionNode(
      id: _id('sec'),
      title: t,
      indent: indent,
      style: _defaultTitleStyleForIndent(indent),
    );

    final nextRoots = _appendSameLevelSibling(
      _doc.roots,
      effectiveTargetId,
      newSec,
    );
    _doc = _doc.copyWith(roots: nextRoots, updatedAtIso: nowIso());
    _commit(); // ✅ prune + notify
  }

  void wrapSelectedSection(String wrapperTitle) {
    final t = wrapperTitle.trim();
    final targetId = _selectedNodeId;
    if (t.isEmpty || targetId == null) return;

    final node = _findNodeById(_doc.roots, targetId);
    if (node is! SectionNode) return;

    final wrappedChild = _shiftIndentSectionSubtree(node, 1);

    final wrapper = SectionNode(
      id: _id('sec'),
      title: t,
      indent: node.indent,
      children: [wrappedChild],
      collapsed: false,
      style: _defaultTitleStyleForIndent(node.indent),
    );

    final nextRoots = _replaceNode(_doc.roots, targetId, wrapper);
    _doc = _doc.copyWith(roots: nextRoots, updatedAtIso: nowIso());
    _commit(); // ✅ prune + notify
  }

  void deleteSelected() {
    final targetId = _selectedNodeId;
    if (targetId == null) return;

    final nextRoots = _deleteNode(_doc.roots, targetId);
    _doc = _doc.copyWith(roots: nextRoots, updatedAtIso: nowIso());
    _selectedNodeId = null;
    _commit(); // ✅ prune + notify
  }

  // =========================
  // Tree: Add Here (context)
  // =========================

  void addHereSubsection(String title) {
    final t = title.trim();
    final targetId = _selectedNodeId;
    if (t.isEmpty || targetId == null) return;

    final selected = _findNodeById(_doc.roots, targetId);
    if (selected is! SectionNode) return;

    final nextIndent = selected.indent + 1;
    final newSec = SectionNode(
      id: _id('sec'),
      title: t,
      indent: nextIndent,
      style: _defaultTitleStyleForIndent(nextIndent),
    );

    _doc = _doc.copyWith(
      roots: _updateSectionTree(
        _doc.roots,
        targetId,
        (s) => s.copyWith(children: [...s.children, newSec], collapsed: false),
      ),
      updatedAtIso: nowIso(),
    );
    _commit(); // ✅ prune + notify
  }

  void addHereContent({String initialText = ''}) {
    final targetId = _selectedNodeId;
    if (targetId == null) return;

    final selected = _findNodeById(_doc.roots, targetId);
    if (selected is! SectionNode) return;

    // ✅ only one content per section
    if (_sectionHasContentChild(selected)) return;

    final newTxt = ContentNode(
      id: _id('txt'),
      text: initialText,
      indent: selected.indent,
    );

    _doc = _doc.copyWith(
      roots: _updateSectionTree(_doc.roots, targetId, (s) {
        // ✅ Insert content BEFORE subsections (intro content)
        final nextChildren = <Node>[
          newTxt,
          ...s.children.whereType<SectionNode>(),
        ];
        return s.copyWith(children: nextChildren, collapsed: false);
      }),
      updatedAtIso: nowIso(),
    );

    _commit(); // ✅ prune + notify
  }

  // =========================
  // Tree: Edit
  // =========================

  void toggleCollapsed(String sectionId) {
    _doc = _doc.copyWith(
      roots: _updateSectionTree(
        _doc.roots,
        sectionId,
        (s) => s.copyWith(collapsed: !s.collapsed),
      ),
      updatedAtIso: nowIso(),
    );
    _commit(); // ✅ prune + notify (structure-ish)
  }

  void renameSection(String sectionId, String title) {
    final t = title.trim();
    if (t.isEmpty) return;

    _doc = _doc.copyWith(
      roots: _updateSectionTree(
        _doc.roots,
        sectionId,
        (s) => s.copyWith(title: t),
      ),
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  void updateSectionStyle(String sectionId, TitleStyle style) {
    _doc = _doc.copyWith(
      roots: _updateSectionTree(
        _doc.roots,
        sectionId,
        (s) => s.copyWith(style: style),
      ),
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  void setSectionAddToRecords(String sectionId, bool value) {
    _doc = _doc.copyWith(
      roots: _updateSectionTree(
        _doc.roots,
        sectionId,
        (s) => s.copyWith(addToRecords: value),
      ),
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  void updateContent(String contentId, String text) {
    _doc = _doc.copyWith(
      roots: _updateContentTree(_doc.roots, contentId, text),
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  void updateSectionNote(String sectionId, String note) {
    _doc = _doc.copyWith(
      roots: _updateSectionTree(
        _doc.roots,
        sectionId,
        (s) => s.copyWith(note: note),
      ),
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  /// Defensive repair for older reports/templates that may contain a section
  /// configured as a field but missing its ContentNode. This prevents the
  /// Report Editor from getting stuck on "Preparing field...". It is scheduled
  /// after build by the UI when needed.
  void ensureSectionContent(String sectionId) {
    final node = _findNodeById(_doc.roots, sectionId);
    if (node is! SectionNode) return;
    if (node.children.any((child) => child is ContentNode)) return;

    _doc = _doc.copyWith(
      roots: _updateSectionTree(
        _doc.roots,
        sectionId,
        (section) => section.copyWith(
          children: <Node>[
            ContentNode(
              id: '${section.id}_content',
              text: '',
              indent: section.indent,
            ),
            ...section.children,
          ],
          collapsed: false,
        ),
      ),
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  // =========================
  // Delete content (outline)
  // =========================

  void deleteContentNode(String contentId) {
    List<Node> walk(List<Node> children) {
      return children
          .where((n) => !(n is ContentNode && n.id == contentId))
          .map((n) {
            if (n is SectionNode) {
              return n.copyWith(children: walk(n.children));
            }
            return n;
          })
          .toList();
    }

    _doc = _doc.copyWith(
      roots: _doc.roots
          .map((s) => s.copyWith(children: walk(s.children)))
          .toList(),
      updatedAtIso: nowIso(),
    );

    _selectedNodeId = null;
    _commit(); // ✅ prune + notify
  }

  bool get selectedSectionHasContent {
    final id = _selectedNodeId;
    if (id == null) return false;

    final n = _findNodeById(_doc.roots, id);
    if (n is! SectionNode) return false;

    return n.children.any((c) => c is ContentNode);
  }

  void deleteContentForSelectedSection() {
    final id = _selectedNodeId;
    if (id == null) return;

    final n = _findNodeById(_doc.roots, id);
    if (n is! SectionNode) return;

    _doc = _doc.copyWith(
      roots: _updateSectionTree(_doc.roots, id, (s) {
        final kept = s.children.where((c) => c is! ContentNode).toList();
        return s.copyWith(children: kept, collapsed: false);
      }),
      updatedAtIso: nowIso(),
    );

    _commit(); // ✅ prune + notify
  }

  void moveSectionUp(String sectionId) {
    _doc = _doc.copyWith(
      roots: _moveSectionAmongSiblings(_doc.roots, sectionId, -1),
      updatedAtIso: nowIso(),
    );
    _commit();
  }

  void moveSectionDown(String sectionId) {
    _doc = _doc.copyWith(
      roots: _moveSectionAmongSiblings(_doc.roots, sectionId, 1),
      updatedAtIso: nowIso(),
    );
    _commit();
  }

  // =========================
  // Images / Signature
  // =========================

  void setPlacementChoice(ImagePlacementChoice choice) {
    // Attachment mode paginates images in groups of 8 per page; it is not an
    // 8-image-per-report limit. Keep existing images when switching modes.
    _doc = _doc.copyWith(placementChoice: choice, updatedAtIso: nowIso());
    _markDirty();
  }

  // =========================
  // Global layout
  // =========================

  void setReportLayout(ReportLayout layout) {
    _doc = _doc.copyWith(reportLayout: layout, updatedAtIso: nowIso());
    _markDirty();
  }

  void setFontScale(double scale) {
    final clamped = scale.clamp(0.85, 1.35).toDouble();

    _doc = _doc.copyWith(fontScale: clamped, updatedAtIso: nowIso());
    _markDirty();
  }

  void setIndentContent(bool enabled) {
    _doc = _doc.copyWith(indentContent: enabled, updatedAtIso: nowIso());
    _markDirty();
  }

  void setIndentHierarchy(bool enabled) {
    _doc = _doc.copyWith(indentHierarchy: enabled, updatedAtIso: nowIso());
    _markDirty();
  }

  void setShowColonAfterTitlesWithContent(bool enabled) {
    _doc = _doc.copyWith(
      showColonAfterTitlesWithContent: enabled,
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  void addImages(List<String> filePaths) {
    final clean = filePaths.where((p) => p.trim().isNotEmpty).toList();
    if (clean.isEmpty) return;

    final cap = _doc.maxImages;
    if (_doc.images.length + clean.length > cap) {
      throw Exception('Maximum of $cap images allowed for this mode.');
    }

    final newImgs = clean
        .map((p) => ImageAttachment(id: _id('img'), filePath: p, label: ''))
        .toList();

    _doc = _doc.copyWith(
      images: [..._doc.images, ...newImgs],
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  void removeImage(String imageId) {
    _doc = _doc.copyWith(
      images: _doc.images.where((i) => i.id != imageId).toList(),
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  void updateImageLabel(String imageId, String label) {
    final safe = label.trim();
    if (safe.length > 25) {
      throw Exception('Image label cannot exceed 25 characters.');
    }
    _doc = _doc.copyWith(
      images: _doc.images
          .map((i) => i.id == imageId ? i.copyWith(label: safe) : i)
          .toList(),
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  void updateSigner({
    String? roleTitle,
    String? name,
    String? credentials,
    String? assistantLabel,
    String? assistantName,
  }) {
    _doc = _doc.copyWith(
      signature: _doc.signature.copyWith(
        roleTitle: roleTitle,
        name: name,
        credentials: credentials,
        assistantLabel: assistantLabel,
        assistantName: assistantName,
      ),
      updatedAtIso: nowIso(),
    );
    _persistCurrentSignatureBlock();
    _markDirty();
  }

  void setSignatureFilePath(String? path) {
    _doc = _doc.copyWith(
      signature: _doc.signature.copyWith(signatureFilePath: path),
      updatedAtIso: nowIso(),
    );
    _persistCurrentSignatureBlock();
    _markDirty();
  }

  bool _isEmptySignature(SignatureBlock signature) {
    return signature.roleTitle.trim().isEmpty &&
        signature.name.trim().isEmpty &&
        signature.credentials.trim().isEmpty &&
        signature.assistantName.trim().isEmpty &&
        (signature.signatureFilePath ?? '').trim().isEmpty;
  }

  Future<void> _applySavedSignatureToCurrentReportIfEmpty({
    bool preserveDirty = false,
  }) async {
    final currentReportId = _doc.reportId;
    if (!_isEmptySignature(_doc.signature)) return;
    final saved = await _loadSavedSignatureBlock();
    if (saved == null || _isEmptySignature(saved)) return;
    if (_doc.reportId != currentReportId) return;
    final wasDirty = _hasUnsavedChanges;
    _doc = _doc.copyWith(signature: saved, updatedAtIso: nowIso());
    _hasUnsavedChanges = preserveDirty ? wasDirty : false;
    notifyListeners();
  }

  Future<SignatureBlock?> _loadSavedSignatureBlock() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_savedSignaturePrefsKey);
      if (raw == null || raw.trim().isEmpty) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return SignatureBlock(
        roleTitle: (j['roleTitle'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        credentials: (j['credentials'] as String?) ?? '',
        assistantLabel:
            (j['assistantLabel'] as String?)?.trim().isNotEmpty == true
            ? (j['assistantLabel'] as String)
            : 'Assistant',
        assistantName: (j['assistantName'] as String?) ?? '',
        signatureFilePath: j['signatureFilePath'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistCurrentSignatureBlock() async {
    try {
      final s = _doc.signature;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _savedSignaturePrefsKey,
        jsonEncode({
          'roleTitle': s.roleTitle,
          'name': s.name,
          'credentials': s.credentials,
          'assistantLabel': s.assistantLabel,
          'assistantName': s.assistantName,
          'signatureFilePath': s.signatureFilePath,
        }),
      );
    } catch (_) {
      // Signature persistence must never block report editing.
    }
  }

  void setLetterheadMode(LetterheadMode mode) {
    final nextLetterheadId = mode == LetterheadMode.digital
        ? _doc.letterheadId
        : null;
    _doc = _doc.copyWith(
      letterheadMode: mode,
      letterheadId: nextLetterheadId,
      applyLetterhead:
          mode == LetterheadMode.digital && nextLetterheadId != null,
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  void setLetterhead(String? id) {
    _doc = _doc.copyWith(
      letterheadMode: id == null ? LetterheadMode.none : LetterheadMode.digital,
      letterheadId: id,
      applyLetterhead: id != null,
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  void setPrePrintedTopSpacing(PrePrintedTopSpacing spacing) {
    _doc = _doc.copyWith(
      letterheadMode: LetterheadMode.prePrinted,
      prePrintedTopSpacing: spacing,
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  void setReservePrePrintedFooter(bool enabled) {
    _doc = _doc.copyWith(
      letterheadMode: LetterheadMode.prePrinted,
      reservePrePrintedFooter: enabled,
      updatedAtIso: nowIso(),
    );
    _markDirty();
  }

  // =========================================================
  // ✅ Ensure form rules (container vs leaf content)
  // This is structural => commit
  // =========================================================
  void ensureFormReady() {
    bool changed = false;

    SectionNode fix(SectionNode s) {
      final hasSectionChildren = s.children.any((n) => n is SectionNode);
      final contentNodes = s.children.whereType<ContentNode>().toList();

      // container section: allow optional intro content (0 or 1), plus subsections
      if (hasSectionChildren) {
        // keep at most ONE content node (intro)
        final intro = contentNodes.isNotEmpty ? contentNodes.first : null;
        final subsections = s.children.whereType<SectionNode>().toList();

        final nextChildren = <Node>[
          if (intro != null) intro,
          ...subsections.map(fix),
        ];

        if (nextChildren.length != s.children.length) changed = true;
        return s.copyWith(children: nextChildren);
      }

      // leaf section: MUST have exactly ONE content
      if (contentNodes.isEmpty) {
        changed = true;
        final newTxt = ContentNode(id: _id('txt'), text: '', indent: s.indent);
        return s.copyWith(children: [newTxt], collapsed: false);
      }

      if (contentNodes.length > 1 || s.children.length != 1) {
        changed = true;
        return s.copyWith(children: [contentNodes.first], collapsed: false);
      }

      return s;
    }

    final nextRoots = _doc.roots.map(fix).toList(growable: false);

    if (!changed) return;

    _doc = _doc.copyWith(roots: nextRoots, updatedAtIso: nowIso());
    _commit(); // ✅ prune + notify
  }

  void collapseAllSections() {
    SectionNode walk(SectionNode s) => s.copyWith(
      collapsed: true,
      children: s.children
          .map((n) {
            if (n is SectionNode) return walk(n);
            return n;
          })
          .toList(growable: false),
    );

    _doc = _doc.copyWith(
      roots: _doc.roots.map(walk).toList(growable: false),
      updatedAtIso: nowIso(),
    );
    _commit();
  }

  // =========================
  // Tree helpers
  // =========================

  List<SectionNode> _updateSectionTree(
    List<SectionNode> roots,
    String targetId,
    SectionNode Function(SectionNode) updater,
  ) {
    return roots.map((s) => _updateSectionNode(s, targetId, updater)).toList();
  }

  SectionNode _updateSectionNode(
    SectionNode node,
    String targetId,
    SectionNode Function(SectionNode) updater,
  ) {
    var current = node;

    if (node.id == targetId) {
      current = updater(node);
    }

    final updatedChildren = current.children.map((child) {
      if (child is SectionNode)
        return _updateSectionNode(child, targetId, updater);
      return child;
    }).toList();

    return current.copyWith(children: updatedChildren);
  }

  List<SectionNode> _updateContentTree(
    List<SectionNode> roots,
    String contentId,
    String text,
  ) {
    List<Node> walk(List<Node> children) {
      return children.map((n) {
        if (n is ContentNode && n.id == contentId) {
          return n.copyWith(text: text);
        }
        if (n is SectionNode) {
          return n.copyWith(children: walk(n.children));
        }
        return n;
      }).toList();
    }

    return roots.map((s) => s.copyWith(children: walk(s.children))).toList();
  }

  Node? _findNodeById(List<SectionNode> roots, String id) {
    for (final s in roots) {
      if (s.id == id) return s;
      final found = _findNodeInChildren(s.children, id);
      if (found != null) return found;
    }
    return null;
  }

  SectionNode? _findSectionById(List<SectionNode> roots, String id) {
    final n = _findNodeById(roots, id);
    return (n is SectionNode) ? n : null;
  }

  Node? _findNodeInChildren(List<Node> children, String id) {
    for (final n in children) {
      if (n.id == id) return n;
      if (n is SectionNode) {
        final found = _findNodeInChildren(n.children, id);
        if (found != null) return found;
      }
    }
    return null;
  }

  String? _findOwningSectionId(List<SectionNode> roots, String nodeId) {
    for (final s in roots) {
      final found = _findOwningSectionIdInSection(s, nodeId);
      if (found != null) return found;
    }
    return null;
  }

  String? _findOwningSectionIdInSection(SectionNode section, String nodeId) {
    for (final n in section.children) {
      if (n.id == nodeId) return section.id;
      if (n is SectionNode) {
        final found = _findOwningSectionIdInSection(n, nodeId);
        if (found != null) return found;
      }
    }
    return null;
  }

  List<SectionNode> _appendSameLevelSibling(
    List<SectionNode> roots,
    String targetId,
    SectionNode newNode,
  ) {
    for (final root in roots) {
      if (root.id == targetId) {
        return [...roots, newNode];
      }
    }

    return roots
        .map(
          (s) => s.copyWith(
            children: _appendSameLevelSiblingInChildren(
              s.children,
              targetId,
              newNode,
            ),
          ),
        )
        .toList();
  }

  List<Node> _appendSameLevelSiblingInChildren(
    List<Node> children,
    String targetId,
    SectionNode newNode,
  ) {
    for (final n in children) {
      if (n.id == targetId) {
        return [...children, newNode];
      }
      if (n is SectionNode) {
        final updated = _appendSameLevelSiblingInChildren(
          n.children,
          targetId,
          newNode,
        );
        if (!identical(updated, n.children)) {
          final next = [...children];
          final index = children.indexOf(n);
          next[index] = n.copyWith(children: updated);
          return next;
        }
      }
    }
    return children;
  }

  List<SectionNode> _replaceNode(
    List<SectionNode> roots,
    String targetId,
    SectionNode replacement,
  ) {
    for (int i = 0; i < roots.length; i++) {
      if (roots[i].id == targetId) {
        final next = [...roots];
        next[i] = replacement;
        return next;
      }
    }

    return roots
        .map(
          (s) => s.copyWith(
            children: _replaceNodeInChildren(s.children, targetId, replacement),
          ),
        )
        .toList();
  }

  List<Node> _replaceNodeInChildren(
    List<Node> children,
    String targetId,
    SectionNode replacement,
  ) {
    for (int i = 0; i < children.length; i++) {
      final n = children[i];
      if (n.id == targetId) {
        final next = [...children];
        next[i] = replacement;
        return next;
      }
      if (n is SectionNode) {
        final updated = _replaceNodeInChildren(
          n.children,
          targetId,
          replacement,
        );
        if (!identical(updated, n.children)) {
          final next = [...children];
          next[i] = n.copyWith(children: updated);
          return next;
        }
      }
    }
    return children;
  }

  List<SectionNode> _deleteNode(List<SectionNode> roots, String targetId) {
    final rootIndex = roots.indexWhere((s) => s.id == targetId);
    if (rootIndex != -1) {
      final next = [...roots]..removeAt(rootIndex);
      return next;
    }

    return roots
        .map(
          (s) =>
              s.copyWith(children: _deleteNodeInChildren(s.children, targetId)),
        )
        .toList();
  }

  List<Node> _deleteNodeInChildren(List<Node> children, String targetId) {
    final idx = children.indexWhere((n) => n.id == targetId);
    if (idx != -1) {
      final next = [...children]..removeAt(idx);
      return next;
    }

    for (int i = 0; i < children.length; i++) {
      final n = children[i];
      if (n is SectionNode) {
        final updated = _deleteNodeInChildren(n.children, targetId);
        if (!identical(updated, n.children)) {
          final next = [...children];
          next[i] = n.copyWith(children: updated);
          return next;
        }
      }
    }

    return children;
  }

  SectionNode _shiftIndentSectionSubtree(SectionNode node, int delta) {
    int clampIndent(int v) => v.clamp(0, 20);

    Node shift(Node n) {
      if (n is ContentNode)
        return n.copyWith(indent: clampIndent(n.indent + delta));
      if (n is SectionNode) {
        final nextChildren = n.children.map(shift).toList();
        return n.copyWith(
          indent: clampIndent(n.indent + delta),
          children: nextChildren,
        );
      }
      return n;
    }

    return shift(node) as SectionNode;
  }

  List<SectionNode> _moveSectionAmongSiblings(
    List<SectionNode> nodes,
    String sectionId,
    int delta,
  ) {
    final rootIndex = nodes.indexWhere((s) => s.id == sectionId);
    if (rootIndex != -1) {
      final target = rootIndex + delta;
      if (target < 0 || target >= nodes.length) return nodes;
      final next = [...nodes];
      final item = next.removeAt(rootIndex);
      next.insert(target, item);
      return next;
    }

    return nodes
        .map((section) {
          final childSections = section.children
              .whereType<SectionNode>()
              .toList(growable: false);
          final childContent = section.children
              .where((n) => n is! SectionNode)
              .toList(growable: false);
          final idx = childSections.indexWhere((s) => s.id == sectionId);
          if (idx != -1) {
            final target = idx + delta;
            if (target < 0 || target >= childSections.length) return section;
            final nextSections = [...childSections];
            final item = nextSections.removeAt(idx);
            nextSections.insert(target, item);
            return section.copyWith(
              children: [...childContent, ...nextSections],
            );
          }

          final movedSections = _moveSectionAmongSiblings(
            childSections,
            sectionId,
            delta,
          );
          if (!identical(movedSections, childSections) &&
              movedSections != childSections) {
            return section.copyWith(
              children: [...childContent, ...movedSections],
            );
          }
          return section;
        })
        .toList(growable: false);
  }
}
