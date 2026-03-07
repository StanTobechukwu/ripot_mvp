import '../models/report_doc.dart';

class AttachmentPagePlan {
  final List<ImageAttachment> images;
  const AttachmentPagePlan(this.images);
}

class PdfPlan {
  /// Candidate inline images for page 1.
  /// Renderer may show fewer if space is tight.
  final List<ImageAttachment> page1InlineCandidates; // up to 4

  /// Candidate inline images for spill content page.
  /// Only used if text spills.
  final List<ImageAttachment> spillInlineCandidates; // up to 4

  /// Attachment pages, up to 8 images per page.
  final List<AttachmentPagePlan> attachmentPages;

  final bool mustEndWithFinalContentPage;

  const PdfPlan({
    required this.page1InlineCandidates,
    required this.spillInlineCandidates,
    required this.attachmentPages,
    required this.mustEndWithFinalContentPage,
  });
}

PdfPlan buildPdfPlan(ReportDoc doc) {
  // Attachments-only mode
  if (doc.placementChoice != ImagePlacementChoice.inlinePage1) {
    return PdfPlan(
      page1InlineCandidates: const [],
      spillInlineCandidates: const [],
      attachmentPages: _chunkAttachments(doc.images),
      mustEndWithFinalContentPage: true,
    );
  }

  // Inline mode
  final page1 = doc.images.take(4).toList();
  final remaining = doc.images.skip(page1.length).toList();

  // Your final rule:
  // - page1 gets up to 4 candidates
  // - spill page can only take candidates if remaining <= 4
  // - if remaining > 4, all remaining become attachments
  final spillInline =
      remaining.length <= 4 ? remaining : <ImageAttachment>[];
  final attachments =
      remaining.length <= 4 ? <ImageAttachment>[] : remaining;

  return PdfPlan(
    page1InlineCandidates: page1,
    spillInlineCandidates: spillInline,
    attachmentPages: _chunkAttachments(attachments),
    mustEndWithFinalContentPage: true,
  );
}

List<AttachmentPagePlan> _chunkAttachments(List<ImageAttachment> images) {
  const perPage = 8;
  final pages = <AttachmentPagePlan>[];

  for (var i = 0; i < images.length; i += perPage) {
    pages.add(
      AttachmentPagePlan(
        images.sublist(i, (i + perPage).clamp(0, images.length)),
      ),
    );
  }

  return pages;
}