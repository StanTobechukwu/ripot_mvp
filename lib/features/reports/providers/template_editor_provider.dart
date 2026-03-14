import 'dart:math';
import 'package:flutter/foundation.dart';

import '../../../core/utils/ids.dart';

import '../domain/models/template_doc.dart';
import '../domain/models/subject_info_def.dart';
import '../domain/models/nodes.dart';


class TemplateEditorProvider extends ChangeNotifier {
  TemplateDoc _template;

  TemplateEditorProvider(this._template);

  TemplateDoc get template => _template;
  SubjectInfoBlockDef get subjectInfo => _template.subjectInfo;

  // ---------- block settings ----------
  void toggleSubjectInfo(bool enabled) {
    _template = _template.copyWith(
      subjectInfo: subjectInfo.copyWith(enabled: enabled),
    );
    notifyListeners();
  }

  void setSubjectInfoHeading(String heading) {
    _template = _template.copyWith(
      subjectInfo: subjectInfo.copyWith(heading: heading.trim()),
    );
    notifyListeners();
  }
  void setSubjectInfoColumns(int columns) {
  final safe = (columns == 2) ? 2 : 1;
  _template = _template.copyWith(
    subjectInfo: subjectInfo.copyWith(columns: safe),
  );
  notifyListeners();
}


  // ---------- field edits ----------
  void renameField(String fieldId, String title) {
    final t = title.trim();
    if (t.isEmpty) return;

    final updated = subjectInfo.fields
        .map((f) => f.key == fieldId ? f.copyWith(title: t) : f)
        .toList();

    _updateFields(updated);
  }

  void toggleRequired(String fieldId, bool required) {
    final updated = subjectInfo.fields
        .map((f) => f.key == fieldId ? f.copyWith(required: required) : f)
        .toList();

    _updateFields(updated);
  }

  void addCustomField({String title = 'Custom Field', bool required = false}) {
    final order = _nextOrder(subjectInfo.fields);
    final fieldId = _generateCustomFieldId();

    final field = SubjectFieldDef(
      key: fieldId,
      title: title,
      required: required,
      order: order,
      isSystem: false,
    );

    _updateFields([...subjectInfo.fields, field]);
  }

  void removeField(String fieldId) {
    final field = subjectInfo.fields.firstWhere((f) => f.key == fieldId);
    if (field.isSystem) return; // protect stable system fields

    _updateFields(subjectInfo.fields.where((f) => f.key != fieldId).toList());
  }

  /// Reorder fields in the template UI (ReorderableListView)
  void reorderFields(int oldIndex, int newIndex) {
    final list = [...subjectInfo.fields]..sort((a, b) => a.order.compareTo(b.order));

    if (oldIndex < 0 || oldIndex >= list.length) return;
    if (newIndex < 0 || newIndex > list.length) return;
    if (newIndex > oldIndex) newIndex -= 1;

    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);

    final resequenced = <SubjectFieldDef>[];
    for (int i = 0; i < list.length; i++) {
      resequenced.add(list[i].copyWith(order: i));
    }

    _updateFields(resequenced);
  }
  // ---------- save/export ----------
  /// Builds a TemplateDoc ready for persistence.
  ///
  /// includeContent:
  ///  - false: structure only (SectionNodes only)
  ///  - true : include ContentNode text (SectionNodes + ContentNodes)
  ///
  /// Images are never part of TemplateDoc, so they are excluded automatically.
  TemplateDoc buildForSave({
    required String name,
    required bool includeContent,
  }) {
    final trimmed = name.trim();

    return _template.copyWith(
      name: trimmed.isEmpty ? _template.name : trimmed,
      updatedAt: DateTime.now(),
      roots: _template.roots
          .map((r) => r.toTemplateNode(includeContent: includeContent))
          .toList(growable: false),
      subjectInfo: _template.subjectInfo,
    );
  }

  // ---------- internal ----------
  void _updateFields(List<SubjectFieldDef> fields) {
    _template = _template.copyWith(
      subjectInfo: subjectInfo.copyWith(fields: fields),
    );
    notifyListeners();
  }

  int _nextOrder(List<SubjectFieldDef> fields) {
    if (fields.isEmpty) return 0;
    final maxOrder = fields.map((f) => f.order).reduce((a, b) => a > b ? a : b);
    return maxOrder + 1;
  }

  String _generateCustomFieldId() {
    final r = Random();
    final chunk = List.generate(8, (_) => r.nextInt(36).toRadixString(36)).join();
    return 'custom_$chunk';
}


  // ---------- outline editing ----------
  void addTopLevelSection(String title) {
    final t = title.trim();
    if (t.isEmpty) return;
    _template = _template.copyWith(
      roots: [..._template.roots, SectionNode(id: newId('sec'), title: t, indent: 0)],
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void addSubsection(String parentId, String title) {
    final t = title.trim();
    if (t.isEmpty) return;
    _template = _template.copyWith(
      roots: _updateTree(
        _template.roots,
        parentId,
        (s) => s.copyWith(
          children: [...s.children, SectionNode(id: newId('sec'), title: t, indent: s.indent + 1)],
          collapsed: false,
        ),
      ),
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void renameSection(String sectionId, String title) {
    final t = title.trim();
    if (t.isEmpty) return;
    _template = _template.copyWith(
      roots: _updateTree(_template.roots, sectionId, (s) => s.copyWith(title: t)),
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void updateSectionStyle(String sectionId, TitleStyle style) {
    _template = _template.copyWith(
      roots: _updateTree(_template.roots, sectionId, (s) => s.copyWith(style: style)),
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void toggleCollapsed(String sectionId) {
    _template = _template.copyWith(
      roots: _updateTree(_template.roots, sectionId, (s) => s.copyWith(collapsed: !s.collapsed)),
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void deleteSection(String sectionId) {
    _template = _template.copyWith(
      roots: _deleteNode(_template.roots, sectionId),
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void moveSectionUp(String sectionId) {
    _template = _template.copyWith(
      roots: _moveSectionAmongSiblings(_template.roots, sectionId, -1),
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void moveSectionDown(String sectionId) {
    _template = _template.copyWith(
      roots: _moveSectionAmongSiblings(_template.roots, sectionId, 1),
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  List<SectionNode> _updateTree(
    List<SectionNode> roots,
    String targetId,
    SectionNode Function(SectionNode) updater,
  ) {
    return roots.map((s) => _updateNode(s, targetId, updater)).toList(growable: false);
  }

  SectionNode _updateNode(
    SectionNode node,
    String targetId,
    SectionNode Function(SectionNode) updater,
  ) {
    var current = node.id == targetId ? updater(node) : node;
    return current.copyWith(
      children: current.children.map((child) {
        if (child is SectionNode) return _updateNode(child, targetId, updater);
        return child;
      }).toList(growable: false),
    );
  }

  List<SectionNode> _deleteNode(List<SectionNode> roots, String targetId) {
    List<Node> walk(List<Node> children) {
      return children.where((n) => !(n is SectionNode && n.id == targetId)).map((n) {
        if (n is SectionNode) return n.copyWith(children: walk(n.children));
        return n;
      }).toList(growable: false);
    }

    return roots.where((s) => s.id != targetId).map((s) => s.copyWith(children: walk(s.children))).toList(growable: false);
  }

  List<SectionNode> _moveSectionAmongSiblings(List<SectionNode> roots, String targetId, int delta) {
    final topIndex = roots.indexWhere((s) => s.id == targetId);
    if (topIndex != -1) {
      final next = [...roots];
      final newIndex = topIndex + delta;
      if (newIndex < 0 || newIndex >= next.length) return roots;
      final item = next.removeAt(topIndex);
      next.insert(newIndex, item);
      return next;
    }

    SectionNode walk(SectionNode section) {
      final childSections = section.children.whereType<SectionNode>().toList(growable: false);
      final childIndex = childSections.indexWhere((s) => s.id == targetId);
      if (childIndex != -1) {
        final newIndex = childIndex + delta;
        if (newIndex < 0 || newIndex >= childSections.length) return section;

        final reordered = [...childSections];
        final item = reordered.removeAt(childIndex);
        reordered.insert(newIndex, item);

        final others = section.children.where((c) => c is! SectionNode).toList(growable: false);
        return section.copyWith(children: [...others, ...reordered]);
      }

      return section.copyWith(
        children: section.children.map((c) => c is SectionNode ? walk(c) : c).toList(growable: false),
      );
    }

    return roots.map(walk).toList(growable: false);
  }
}
