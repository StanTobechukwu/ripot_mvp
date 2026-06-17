import '../models/nodes.dart';
import '../models/template_doc.dart';
import '../models/subject_info_def.dart';
import '../models/report_doc.dart';

class TemplateCodec {
  static Map<String, dynamic> templateToJson(TemplateDoc t) => {
        'templateId': t.templateId,
        'updatedAtIso': t.updatedAt.toIso8601String(),
        'name': t.name,
        'roots': t.roots.map(_sectionToJson).toList(),
        'subjectInfo': t.subjectInfo.toJson(),
        'signature': _signatureToJson(t.signature),
      };

  static TemplateDoc templateFromJson(Map<String, dynamic> j) {
    return TemplateDoc(
      templateId: (j['templateId'] as String?) ?? 'unknown',
      updatedAt: DateTime.tryParse((j['updatedAtIso'] as String?) ?? '') ??
          DateTime.now(),
      name: (j['name'] as String?) ?? 'Untitled Template',
      roots: ((j['roots'] as List?) ?? const [])
          .map((e) => _sectionFromJson(e as Map<String, dynamic>))
          .toList(),
      subjectInfo:
          SubjectInfoBlockDef.fromJson(j['subjectInfo'] as Map<String, dynamic>?),
      signature: _signatureFromJson((j['signature'] as Map?)?.cast<String, dynamic>()),
    );
  }


  static Map<String, dynamic> _signatureToJson(SignatureBlock s) => {
        'roleTitle': s.roleTitle,
        'name': s.name,
        'credentials': s.credentials,
        'assistantLabel': s.assistantLabel,
        'assistantName': s.assistantName,
        'signatureFilePath': s.signatureFilePath,
      };

  static SignatureBlock _signatureFromJson(Map<String, dynamic>? json) {
    final j = json ?? const <String, dynamic>{};
    return SignatureBlock(
      roleTitle: (j['roleTitle'] as String?) ?? '',
      name: (j['name'] as String?) ?? '',
      credentials: (j['credentials'] as String?) ?? '',
      assistantLabel: (j['assistantLabel'] as String?)?.trim().isNotEmpty == true
          ? (j['assistantLabel'] as String)
          : 'Assistant',
      assistantName: (j['assistantName'] as String?) ?? '',
      signatureFilePath: j['signatureFilePath'] as String?,
    );
  }

  // ----- nodes -----

  static Map<String, dynamic> _sectionToJson(SectionNode s) => {
        'type': 'section',
        'id': s.id,
        'title': s.title,
        'collapsed': s.collapsed,
        'style': _styleToJson(s.style),
        'inputType': s.inputType.name,
        'options': s.options,
        'showInPdf': s.showInPdf,
        'addToRecords': s.addToRecords,
        'conditionalParentSectionId': s.conditionalParentSectionId,
        'conditionalEquals': s.conditionalEquals,
        'indent': s.indent, // ✅ added
        'children': s.children.map(_nodeToJson).toList(),
      };

  static SectionNode _sectionFromJson(Map<String, dynamic> j) => SectionNode(
        id: (j['id'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        collapsed: (j['collapsed'] as bool?) ?? false,
        style: _styleFromJson((j['style'] as Map?)?.cast<String, dynamic>() ?? {}),
        inputType: _fieldInputTypeFromJson(j['inputType'] as String?),
        options: ((j['options'] as List?) ?? const []).map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList(growable: false),
        showInPdf: (j['showInPdf'] as bool?) ?? true,
        addToRecords: (j['addToRecords'] as bool?) ?? false,
        conditionalParentSectionId: (j['conditionalParentSectionId'] as String?) ?? '',
        conditionalEquals: (j['conditionalEquals'] as String?) ?? '',
        indent: (j['indent'] as int?) ?? 0, // ✅ added
        children: ((j['children'] as List?) ?? const [])
            .map((e) => _nodeFromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static Map<String, dynamic> _nodeToJson(Node n) {
    if (n is SectionNode) return _sectionToJson(n);
    if (n is ContentNode) {
      return {
        'type': 'content',
        'id': n.id,
        'text': n.text,
        'indent': n.indent, // ✅ added (if ContentNode has indent)
      };
    }
    throw StateError('Unknown node type');
  }

  static Node _nodeFromJson(Map<String, dynamic> j) {
    final type = (j['type'] as String?) ?? '';
    if (type == 'section') return _sectionFromJson(j);
    if (type == 'content') {
      return ContentNode(
        id: (j['id'] as String?) ?? '',
        text: (j['text'] as String?) ?? '',
        indent: (j['indent'] as int?) ?? 0, // ✅ added (if ContentNode has indent)
      );
    }
    throw StateError('Unknown node json type: $type');
  }

  // ----- style -----

  static Map<String, dynamic> _styleToJson(TitleStyle s) => {
        'level': s.level.name,
        'bold': s.bold,
        'align': s.align.name,
      };

  static TitleStyle _styleFromJson(Map<String, dynamic> j) {
    return TitleStyle(
      level: HeadingLevel.values.byName(
          (j['level'] as String?) ?? HeadingLevel.h2.name),
      bold: (j['bold'] as bool?) ?? true,
      align: TitleAlign.values.byName(
          (j['align'] as String?) ?? TitleAlign.left.name),
    );
  }

  static FieldInputType _fieldInputTypeFromJson(String? name) {
    if (name == null || name.trim().isEmpty) return FieldInputType.freeText;
    for (final value in FieldInputType.values) {
      if (value.name == name) return value;
    }
    return FieldInputType.freeText;
  }

}
