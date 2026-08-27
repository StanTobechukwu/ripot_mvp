import 'package:flutter/foundation.dart';

@immutable
sealed class Node {
  final String id;
  const Node({required this.id});
}

enum HeadingLevel { h1, h2, h3, h4 }
enum TitleAlign { left, center, right }

enum FieldInputType { freeText, yesNo, singleSelect, multiSelect }

extension FieldInputTypeLabel on FieldInputType {
  String get label {
    switch (this) {
      case FieldInputType.freeText:
        return 'Free text';
      case FieldInputType.yesNo:
        return 'Yes / No';
      case FieldInputType.singleSelect:
        return 'Single select';
      case FieldInputType.multiSelect:
        return 'Multi-select';
    }
  }
}

@immutable
class TitleStyle {
  final HeadingLevel level;
  final bool bold;
  final TitleAlign align;

  const TitleStyle({
    this.level = HeadingLevel.h4,
    this.bold = true,
    this.align = TitleAlign.left,
  });

  TitleStyle copyWith({
    HeadingLevel? level,
    bool? bold,
    TitleAlign? align,
  }) {
    return TitleStyle(
      level: level ?? this.level,
      bold: bold ?? this.bold,
      align: align ?? this.align,
    );
  }
}

@immutable
class SectionNode extends Node {
  final String title;
  final bool collapsed;
  final TitleStyle style;
  final List<Node> children;

  /// Input type used by Report Editor for this section's content.
  final FieldInputType inputType;

  /// Options/suggestions used by structured inputs.
  final List<String> options;

  /// When false, this field is hidden from the final PDF but can still be used for records.
  final bool showInPdf;

  /// When true, this section's structured value is copied into Records
  /// when the report is saved. Free-text fields must not use this.
  final bool addToRecords;

  /// Structured fields can optionally allow an additional narrative note.
  /// This is a template-level capability, not the note value itself.
  final bool allowOptionalNote;

  /// Report-instance narrative note attached to a structured field.
  /// This note is not structured Records data.
  final String note;

  /// Optional simple conditional display rule for this section.
  /// The section is shown only when the parent section's first content value
  /// equals [conditionalEquals]. This is intentionally limited to one parent
  /// and one expected value so the template remains simple.
  final String conditionalParentSectionId;
  final String conditionalEquals;

  bool get hasCondition =>
      conditionalParentSectionId.trim().isNotEmpty && conditionalEquals.trim().isNotEmpty;

  /// ✅ indentation level for this section (0,1,2...)
  final int indent;

  const SectionNode({
    required super.id,
    required this.title,
    this.collapsed = false,
    this.style = const TitleStyle(),
    this.children = const [],
    this.inputType = FieldInputType.freeText,
    this.options = const [],
    this.showInPdf = true,
    this.addToRecords = false,
    this.allowOptionalNote = false,
    this.note = '',
    this.conditionalParentSectionId = '',
    this.conditionalEquals = '',
    this.indent = 0,
  });

  SectionNode copyWith({
    String? title,
    bool? collapsed,
    TitleStyle? style,
    List<Node>? children,
    FieldInputType? inputType,
    List<String>? options,
    bool? showInPdf,
    bool? addToRecords,
    bool? allowOptionalNote,
    String? note,
    String? conditionalParentSectionId,
    String? conditionalEquals,
    int? indent,
  }) {
    return SectionNode(
      id: id,
      title: title ?? this.title,
      collapsed: collapsed ?? this.collapsed,
      style: style ?? this.style,
      children: children ?? this.children,
      inputType: inputType ?? this.inputType,
      options: options ?? this.options,
      showInPdf: showInPdf ?? this.showInPdf,
      addToRecords: addToRecords ?? this.addToRecords,
      allowOptionalNote: allowOptionalNote ?? this.allowOptionalNote,
      note: note ?? this.note,
      conditionalParentSectionId: conditionalParentSectionId ?? this.conditionalParentSectionId,
      conditionalEquals: conditionalEquals ?? this.conditionalEquals,
      indent: indent ?? this.indent,
    );
  }
}

@immutable
class ContentNode extends Node {
  final String text;

  /// ✅ indentation level for this paragraph/content node
  final int indent;

  const ContentNode({
    required super.id,
    this.text = '',
    this.indent = 0,
  });

  ContentNode copyWith({
    String? text,
    int? indent,
  }) {
    return ContentNode(
      id: id,
      text: text ?? this.text,
      indent: indent ?? this.indent,
    );
  }
}
extension TemplateClone on SectionNode {
  /// Export a template snapshot of this section.
  ///
  /// includeContent = false -> keep only SectionNode children (structure-only)
  /// includeContent = true  -> keep SectionNode + ContentNode children (text content)
  ///
  /// Images are not stored in nodes, so they are never included.
  SectionNode toTemplateNode({required bool includeContent}) {
    final outChildren = <Node>[];

    for (final child in children) {
      if (child is SectionNode) {
        outChildren.add(
          child.toTemplateNode(includeContent: includeContent),
        );
      } else if (includeContent && child is ContentNode) {
        outChildren.add(child);
      }
      // else: drop non-section nodes (and drop content when structure-only)
    }

    return SectionNode(
      id: id,
      title: title,
      collapsed: collapsed,
      style: style,
      inputType: inputType,
      options: options,
      showInPdf: showInPdf,
      addToRecords: addToRecords,
      allowOptionalNote: allowOptionalNote,
      note: '',
      conditionalParentSectionId: conditionalParentSectionId,
      conditionalEquals: conditionalEquals,
      indent: indent,
      children: outChildren,
    );
  }
}
extension ReportClone on SectionNode {
  SectionNode cloneNodeTree() {
    return SectionNode(
      id: id,
      title: title,
      collapsed: collapsed,
      style: style,
      inputType: inputType,
      options: options,
      showInPdf: showInPdf,
      addToRecords: addToRecords,
      allowOptionalNote: allowOptionalNote,
      note: note,
      conditionalParentSectionId: conditionalParentSectionId,
      conditionalEquals: conditionalEquals,
      indent: indent,
      children: children.map((n) {
        if (n is SectionNode) return n.cloneNodeTree();
        if (n is ContentNode) {
          return ContentNode(
            id: n.id,
            text: n.text,
            indent: n.indent,
          );
        }
        return n; // if you have other Node types, we can explicitly clone them too
      }).toList(growable: false),
    );
  }
}
