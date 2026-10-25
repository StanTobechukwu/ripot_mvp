import 'package:flutter/foundation.dart';
import 'nodes.dart';
import 'report_doc.dart';
import 'subject_info_def.dart';

@immutable
class TemplateDoc {
  final String templateId;
  final DateTime updatedAt;
  final String name;
  final String groupName;
  final String sourceSlug;
  final String sourceVersion;
  final String contributor;
  final bool recordsConfigured;
  final List<SectionNode> roots;
  final SubjectInfoBlockDef subjectInfo;
  final SignatureBlock signature;

  const TemplateDoc({
    required this.templateId,
    required this.updatedAt,
    required this.name,
    this.groupName = '',
    this.sourceSlug = '',
    this.sourceVersion = '',
    this.contributor = '',
    this.recordsConfigured = false,
    required this.roots,
    SubjectInfoBlockDef? subjectInfo,
    this.signature = const SignatureBlock(),
  }) : subjectInfo = subjectInfo ?? SubjectInfoBlockDef.kDefaults;

  TemplateDoc copyWith({
    DateTime? updatedAt,
    String? name,
    String? groupName,
    String? sourceSlug,
    String? sourceVersion,
    String? contributor,
    bool? recordsConfigured,
    List<SectionNode>? roots,
    SubjectInfoBlockDef? subjectInfo,
    SignatureBlock? signature,
  }) {
    return TemplateDoc(
      templateId: templateId,
      updatedAt: updatedAt ?? this.updatedAt,
      name: name ?? this.name,
      groupName: groupName ?? this.groupName,
      sourceSlug: sourceSlug ?? this.sourceSlug,
      sourceVersion: sourceVersion ?? this.sourceVersion,
      contributor: contributor ?? this.contributor,
      recordsConfigured: recordsConfigured ?? this.recordsConfigured,
      roots: roots ?? this.roots,
      subjectInfo: subjectInfo ?? this.subjectInfo,
      signature: signature ?? this.signature,
    );
  }
}
