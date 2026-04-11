
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
  static const Object _unset = Object();

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

  /// Optional hierarchy indentation for subsection titles in block/aligned layout.
  final bool indentHierarchy;

  /// Show a colon after titles that directly own content.
  final bool showColonAfterTitlesWithContent;

  /// Global font scale applied everywhere
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
    this.indentHierarchy = true,
    this.showColonAfterTitlesWithContent = false,
    this.fontScale = 1.05,
    this.signature = const SignatureBlock(),
    this.applyLetterhead = false,
    this.letterheadId,
    SubjectInfoBlockDef? subjectInfoDef,
    SubjectInfoValues? subjectInfo,
  })  : subjectInfoDef = subjectInfoDef ?? SubjectInfoBlockDef.kDefaults,
        subjectInfo = subjectInfo ?? const SubjectInfoValues({});

  int get maxImages =>
      placementChoice == ImagePlacementChoice.inlinePage1 ? 12 : 12;

  ReportDoc copyWith({
    String? createdAtIso,
    String? updatedAtIso,
    String? reportTitle,
    List<SectionNode>? roots,
    List<ImageAttachment>? images,
    ImagePlacementChoice? placementChoice,
    ReportLayout? reportLayout,
    bool? indentContent,
    bool? indentHierarchy,
    bool? showColonAfterTitlesWithContent,
    double? fontScale,
    SignatureBlock? signature,
    SubjectInfoBlockDef? subjectInfoDef,
    SubjectInfoValues? subjectInfo,
    bool? applyLetterhead,
    Object? letterheadId = _unset,
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
      indentHierarchy: indentHierarchy ?? this.indentHierarchy,
      showColonAfterTitlesWithContent: showColonAfterTitlesWithContent ?? this.showColonAfterTitlesWithContent,
      fontScale: fontScale ?? this.fontScale,
      signature: signature ?? this.signature,
      subjectInfoDef: subjectInfoDef ?? this.subjectInfoDef,
      subjectInfo: subjectInfo ?? this.subjectInfo,
      applyLetterhead: applyLetterhead ?? this.applyLetterhead,
      letterheadId: identical(letterheadId, _unset)
          ? this.letterheadId
          : letterheadId as String?,
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
  final String label;

  const ImageAttachment({
    required this.id,
    required this.filePath,
    this.label = '',
  });

  ImageAttachment copyWith({
    String? id,
    String? filePath,
    String? label,
  }) {
    return ImageAttachment(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      label: label ?? this.label,
    );
  }
}

const Object _unsetSignaturePath = Object();

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
    Object? signatureFilePath = _unsetSignaturePath,
  }) {
    return SignatureBlock(
      roleTitle: roleTitle ?? this.roleTitle,
      name: name ?? this.name,
      credentials: credentials ?? this.credentials,
      signatureFilePath: identical(signatureFilePath, _unsetSignaturePath)
          ? this.signatureFilePath
          : signatureFilePath as String?,
    );
  }
}



