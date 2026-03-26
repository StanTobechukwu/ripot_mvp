import '../models/report_doc.dart';
import 'pdf_estimates.dart';
import 'pdf_layout_metrics.dart';
import 'pdf_plan.dart';

class PdfPlanBuilder {
  const PdfPlanBuilder();

  PdfPlan build(
    ReportDoc doc, {
    required PdfLayoutMetrics metrics,
  }) {
    final title = effectiveReportTitle(doc);
    final inlineEnabled = doc.placementChoice == ImagePlacementChoice.inlinePage1;

    if (!inlineEnabled) {
      return PdfPlan(
        title: title,
        inlineEnabled: false,
        pageOne: const PageOnePlan(inlineImages: []),
        finalContent: const FinalContentPlan(spillInlineImages: []),
        attachmentPages: [
          for (final chunk in chunked(doc.images, metrics.attachmentImagesPerPage))
            AttachmentPagePlan(images: chunk),
        ],
      );
    }

    final pageOneInline = doc.images.take(metrics.maxPage1InlineSlots).toList(growable: false);
    final attachmentImages = doc.images.skip(pageOneInline.length).toList(growable: false);

    return PdfPlan(
      title: title,
      inlineEnabled: true,
      pageOne: PageOnePlan(inlineImages: pageOneInline),
      finalContent: const FinalContentPlan(spillInlineImages: []),
      attachmentPages: [
        for (final chunk in chunked(attachmentImages, metrics.attachmentImagesPerPage))
          AttachmentPagePlan(images: chunk),
      ],
    );
  }
}
