import 'package:pdf/pdf.dart';

class PdfLayoutMetrics {
  final PdfPageFormat pageFormat;
  final double pageMargin;
  final double headerReserve;
  final double footerReserve;
  final double inlineColumnWidth;
  final double inlineSlotHeight;
  final double inlineSlotGap;
  final double inlineToTextGap;
  final int maxPage1InlineSlots;
  final int maxSpillInlineSlots;
  final int maxTotalInlineImages;
  final int attachmentImagesPerPage;

  const PdfLayoutMetrics({
    this.pageFormat = PdfPageFormat.a4,
    this.pageMargin = 28.0,
    this.headerReserve = 0.0,
    this.footerReserve = 0.0,
    this.inlineColumnWidth = 160.0,
    this.inlineSlotHeight = 95.0,
    this.inlineSlotGap = 10.0,
    this.inlineToTextGap = 12.0,
    this.maxPage1InlineSlots = 4,
    this.maxSpillInlineSlots = 4,
    this.maxTotalInlineImages = 8,
    this.attachmentImagesPerPage = 8,
  });

  double get usableHeight =>
      pageFormat.height - (pageMargin * 2) - headerReserve - footerReserve;

  double get bodyWidth => pageFormat.width - (pageMargin * 2);

  double get page1TextWidth =>
      bodyWidth - inlineColumnWidth - inlineToTextGap;

  PdfLayoutMetrics copyWith({
    PdfPageFormat? pageFormat,
    double? pageMargin,
    double? headerReserve,
    double? footerReserve,
    double? inlineColumnWidth,
    double? inlineSlotHeight,
    double? inlineSlotGap,
    double? inlineToTextGap,
    int? maxPage1InlineSlots,
    int? maxSpillInlineSlots,
    int? maxTotalInlineImages,
    int? attachmentImagesPerPage,
  }) {
    return PdfLayoutMetrics(
      pageFormat: pageFormat ?? this.pageFormat,
      pageMargin: pageMargin ?? this.pageMargin,
      headerReserve: headerReserve ?? this.headerReserve,
      footerReserve: footerReserve ?? this.footerReserve,
      inlineColumnWidth: inlineColumnWidth ?? this.inlineColumnWidth,
      inlineSlotHeight: inlineSlotHeight ?? this.inlineSlotHeight,
      inlineSlotGap: inlineSlotGap ?? this.inlineSlotGap,
      inlineToTextGap: inlineToTextGap ?? this.inlineToTextGap,
      maxPage1InlineSlots: maxPage1InlineSlots ?? this.maxPage1InlineSlots,
      maxSpillInlineSlots: maxSpillInlineSlots ?? this.maxSpillInlineSlots,
      maxTotalInlineImages: maxTotalInlineImages ?? this.maxTotalInlineImages,
      attachmentImagesPerPage:
          attachmentImagesPerPage ?? this.attachmentImagesPerPage,
    );
  }
}
