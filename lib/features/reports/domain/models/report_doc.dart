import 'package:flutter/foundation.dart';

import 'nodes.dart';
import 'subject_info_def.dart';
import 'subject_info_value.dart';

// =========================================================
// Images
// =========================================================

enum ImagePlacementChoice {
  attachmentsOnly,
  inlinePage1,
}

// =========================================================
// Global PDF layout
// =========================================================

/// Global PDF text layout option.
///
/// - [block]: section titles on their own line; content on subsequent lines.
/// - [inline]: leaf sections render as `Title: content` on one line.
/// - [aligned]: leaf sections try to align content to a common start column.
enum ReportLayout {
  block,
  inline,
  aligned,
}

// =========================================================
// Model
// =========================================================

@immutable
class ReportDoc {
  final String reportId;
  final String createdAtIso;
  final String updatedAtIso;

  final String reportTitle;

  final List<SectionNode> roots;
  final List<ImageAttachment> images;
  final ImagePlacementChoice placementChoice;

  /// Global PDF layout style
  final ReportLayout reportLayout;

  /// Optional global indentation toggle for content fields
  final bool indentContent;

  /// ✅ NEW: global font scale applied everywhere
  /// Editor + Form + Preview + PDF
  final double fontScale;

  final SignatureBlock signature;

  /// Subject Info schema + values
  final SubjectInfoBlockDef subjectInfoDef;
  final SubjectInfoValues subjectInfo;

  final bool applyLetterhead;
  final String? letterheadId;

  const ReportDoc({
    required this.reportId,
    required this.createdAtIso,
    required this.updatedAtIso,
    this.reportTitle = '',
    this.roots = const [],
    this.images = const [],
    this.placementChoice = ImagePlacementChoice.attachmentsOnly,
    this.reportLayout = ReportLayout.block,
    this.indentContent = true,
    this.fontScale = 1.0,
    this.signature = const SignatureBlock(),
    this.applyLetterhead = false,
    this.letterheadId,
    SubjectInfoBlockDef? subjectInfoDef,
    SubjectInfoValues? subjectInfo,
  })  : subjectInfoDef = subjectInfoDef ?? SubjectInfoBlockDef.kDefaults,
        subjectInfo = subjectInfo ?? const SubjectInfoValues({});

  int get maxImages =>
      placementChoice == ImagePlacementChoice.inlinePage1 ? 12 : 8;

  ReportDoc copyWith({
    String? createdAtIso,
    String? updatedAtIso,
    String? reportTitle,
    List<SectionNode>? roots,
    List<ImageAttachment>? images,
    ImagePlacementChoice? placementChoice,
    ReportLayout? reportLayout,
    bool? indentContent,
    double? fontScale,
    SignatureBlock? signature,
    SubjectInfoBlockDef? subjectInfoDef,
    SubjectInfoValues? subjectInfo,
    bool? applyLetterhead,
    String? letterheadId,
  }) {
    return ReportDoc(
      reportId: reportId,
      createdAtIso: createdAtIso ?? this.createdAtIso,
      updatedAtIso: updatedAtIso ?? this.updatedAtIso,
      reportTitle: reportTitle ?? this.reportTitle,
      roots: roots ?? this.roots,
      images: images ?? this.images,
      placementChoice: placementChoice ?? this.placementChoice,
      reportLayout: reportLayout ?? this.reportLayout,
      indentContent: indentContent ?? this.indentContent,
      fontScale: fontScale ?? this.fontScale,
      signature: signature ?? this.signature,
      subjectInfoDef: subjectInfoDef ?? this.subjectInfoDef,
      subjectInfo: subjectInfo ?? this.subjectInfo,
      applyLetterhead: applyLetterhead ?? this.applyLetterhead,
      letterheadId: letterheadId ?? this.letterheadId,
    );
  }
}

// =========================================================
// Supporting value types
// =========================================================

@immutable
class ImageAttachment {
  final String id;
  final String filePath;

  const ImageAttachment({
    required this.id,
    required this.filePath,
  });
}

@immutable
class SignatureBlock {
  final String roleTitle;
  final String name;
  final String credentials;
  final String? signatureFilePath;

  const SignatureBlock({
    this.roleTitle = '',
    this.name = '',
    this.credentials = '',
    this.signatureFilePath,
  });

  SignatureBlock copyWith({
    String? roleTitle,
    String? name,
    String? credentials,
    String? signatureFilePath,
  }) {
    return SignatureBlock(
      roleTitle: roleTitle ?? this.roleTitle,
      name: name ?? this.name,
      credentials: credentials ?? this.credentials,
      signatureFilePath: signatureFilePath ?? this.signatureFilePath,
    );
  }
}