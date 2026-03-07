import '../models/report_doc.dart';

class PageOnePlan {
  final List<ImageAttachment> inlineImages;

  const PageOnePlan({
    required this.inlineImages,
  });
}

class FinalContentPlan {
  final List<ImageAttachment> spillInlineImages;

  const FinalContentPlan({
    required this.spillInlineImages,
  });
}

class AttachmentPagePlan {
  final List<ImageAttachment> images;

  const AttachmentPagePlan({required this.images});
}

class PdfPlan {
  final String title;
  final bool inlineEnabled;
  final PageOnePlan pageOne;
  final FinalContentPlan finalContent;
  final List<AttachmentPagePlan> attachmentPages;

  const PdfPlan({
    required this.title,
    required this.inlineEnabled,
    required this.pageOne,
    required this.finalContent,
    required this.attachmentPages,
  });
}
