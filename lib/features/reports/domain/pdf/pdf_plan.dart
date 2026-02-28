import '../models/report_doc.dart';

class AttachmentPagePlan {
  final List<ImageAttachment> images;
  const AttachmentPagePlan(this.images);
}

class PdfPlan {
  final List<ImageAttachment> page1InlineImages; // 0..4
  final List<AttachmentPagePlan> attachmentPages; // up to 8 per page
  final bool mustEndWithFinalContentPage;

  const PdfPlan({
    required this.page1InlineImages,
    required this.attachmentPages,
    required this.mustEndWithFinalContentPage,
  });
}

PdfPlan buildPdfPlan(ReportDoc doc) {
  final inline = doc.placementChoice == ImagePlacementChoice.inlinePage1
      ? doc.images.take(4).toList()
      : <ImageAttachment>[];

  final remaining = doc.images.skip(inline.length).toList();

  const perPage = 8;
  final pages = <AttachmentPagePlan>[];
  for (var i = 0; i < remaining.length; i += perPage) {
    pages.add(AttachmentPagePlan(
      remaining.sublist(i, (i + perPage).clamp(0, remaining.length)),
    ));
  }

  return PdfPlan(
    page1InlineImages: inline,
    attachmentPages: pages,
    mustEndWithFinalContentPage: true,
  );
}
