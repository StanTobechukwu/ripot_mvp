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
    final remainingAfterPageOne = doc.images.skip(pageOneInline.length).toList(growable: false);

    final spillAllowance = (metrics.maxTotalInlineImages - pageOneInline.length)
        .clamp(0, metrics.maxSpillInlineSlots);
    final spillInline = remainingAfterPageOne.take(spillAllowance).toList(growable: false);
    final attachmentImages = remainingAfterPageOne.skip(spillInline.length).toList(growable: false);

    return PdfPlan(
      title: title,
      inlineEnabled: true,
      pageOne: PageOnePlan(inlineImages: pageOneInline),
      finalContent: FinalContentPlan(spillInlineImages: spillInline),
      attachmentPages: [
        for (final chunk in chunked(attachmentImages, metrics.attachmentImagesPerPage))
          AttachmentPagePlan(images: chunk),
      ],
    );
  }
}
