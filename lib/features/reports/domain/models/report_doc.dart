import 'package:flutter/foundation.dart';

import 'nodes.dart';
import 'subject_info_def.dart';
import 'subject_info_value.dart';

// =========================================================
// Images
// =========================================================

enum ImagePlacementChoice { attachmentsOnly, inlinePage1 }

// =========================================================
// Global PDF layout
// =========================================================

/// Global PDF text layout option.
///
/// - [block]: section titles on their own line; content on subsequent lines.
/// - [inline]: leaf sections render as `Title: content` on one line.
/// - [aligned]: leaf sections try to align content to a common start column.
enum ReportLayout { block, inline, aligned }

enum LetterheadMode { none, digital, prePrinted }

enum PrePrintedTopSpacing { small, medium, large }

extension PrePrintedTopSpacingPoints on PrePrintedTopSpacing {
  double get points {
    switch (this) {
      case PrePrintedTopSpacing.small:
        return 80.0;
      case PrePrintedTopSpacing.medium:
        return 110.0;
      case PrePrintedTopSpacing.large:
        return 140.0;
    }
  }

  String get label {
    switch (this) {
      case PrePrintedTopSpacing.small:
        return 'Small';
      case PrePrintedTopSpacing.medium:
        return 'Medium';
      case PrePrintedTopSpacing.large:
        return 'Large';
    }
  }
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

  /// Required report/procedure date. Auto-filled on new reports and rendered
  /// near the report title, independent of Subject Info.
  final String reportDateIso;

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

  /// Letterhead selection lives under Letterhead settings, not general layout.
  /// Digital mode draws the saved header/footer. Pre-printed mode draws no
  /// header/footer and only reserves safe printable space.
  final LetterheadMode letterheadMode;
  final bool applyLetterhead;
  final String? letterheadId;
  final PrePrintedTopSpacing prePrintedTopSpacing;
  final bool reservePrePrintedFooter;

  const ReportDoc({
    required this.reportId,
    required this.createdAtIso,
    required this.updatedAtIso,
    this.reportTitle = '',
    String? reportDateIso,
    this.roots = const [],
    this.images = const [],
    this.placementChoice = ImagePlacementChoice.inlinePage1,
    this.reportLayout = ReportLayout.inline,
    this.indentContent = false,
    this.indentHierarchy = true,
    this.showColonAfterTitlesWithContent = true,
    this.fontScale = 1.05,
    this.signature = const SignatureBlock(),
    this.letterheadMode = LetterheadMode.none,
    this.applyLetterhead = false,
    this.letterheadId,
    this.prePrintedTopSpacing = PrePrintedTopSpacing.medium,
    this.reservePrePrintedFooter = false,
    SubjectInfoBlockDef? subjectInfoDef,
    SubjectInfoValues? subjectInfo,
  }) : reportDateIso = reportDateIso ?? createdAtIso,
       subjectInfoDef = subjectInfoDef ?? SubjectInfoBlockDef.kDefaults,
       subjectInfo = subjectInfo ?? const SubjectInfoValues({});

  int get maxImages =>
      placementChoice == ImagePlacementChoice.inlinePage1 ? 12 : 12;

  ReportDoc copyWith({
    String? createdAtIso,
    String? updatedAtIso,
    String? reportTitle,
    String? reportDateIso,
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
    LetterheadMode? letterheadMode,
    bool? applyLetterhead,
    Object? letterheadId = _unset,
    PrePrintedTopSpacing? prePrintedTopSpacing,
    bool? reservePrePrintedFooter,
  }) {
    return ReportDoc(
      reportId: reportId,
      createdAtIso: createdAtIso ?? this.createdAtIso,
      updatedAtIso: updatedAtIso ?? this.updatedAtIso,
      reportTitle: reportTitle ?? this.reportTitle,
      reportDateIso: reportDateIso ?? this.reportDateIso,
      roots: roots ?? this.roots,
      images: images ?? this.images,
      placementChoice: placementChoice ?? this.placementChoice,
      reportLayout: reportLayout ?? this.reportLayout,
      indentContent: indentContent ?? this.indentContent,
      indentHierarchy: indentHierarchy ?? this.indentHierarchy,
      showColonAfterTitlesWithContent:
          showColonAfterTitlesWithContent ??
          this.showColonAfterTitlesWithContent,
      fontScale: fontScale ?? this.fontScale,
      signature: signature ?? this.signature,
      subjectInfoDef: subjectInfoDef ?? this.subjectInfoDef,
      subjectInfo: subjectInfo ?? this.subjectInfo,
      letterheadMode: letterheadMode ?? this.letterheadMode,
      applyLetterhead: applyLetterhead ?? this.applyLetterhead,
      letterheadId: identical(letterheadId, _unset)
          ? this.letterheadId
          : letterheadId as String?,
      prePrintedTopSpacing: prePrintedTopSpacing ?? this.prePrintedTopSpacing,
      reservePrePrintedFooter:
          reservePrePrintedFooter ?? this.reservePrePrintedFooter,
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

  ImageAttachment copyWith({String? id, String? filePath, String? label}) {
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
  final String assistantLabel;
  final String assistantName;
  final String? signatureFilePath;

  const SignatureBlock({
    this.roleTitle = '',
    this.name = '',
    this.credentials = '',
    this.assistantLabel = 'Assistant',
    this.assistantName = '',
    this.signatureFilePath,
  });

  SignatureBlock copyWith({
    String? roleTitle,
    String? name,
    String? credentials,
    String? assistantLabel,
    String? assistantName,
    Object? signatureFilePath = _unsetSignaturePath,
  }) {
    return SignatureBlock(
      roleTitle: roleTitle ?? this.roleTitle,
      name: name ?? this.name,
      credentials: credentials ?? this.credentials,
      assistantLabel: assistantLabel ?? this.assistantLabel,
      assistantName: assistantName ?? this.assistantName,
      signatureFilePath: identical(signatureFilePath, _unsetSignaturePath)
          ? this.signatureFilePath
          : signatureFilePath as String?,
    );
  }
}
