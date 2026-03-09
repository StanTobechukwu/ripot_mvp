import 'dart:math';

import '../models/report_doc.dart';
import 'pdf_layout_metrics.dart';

String effectiveReportTitle(ReportDoc doc) {
  final title = doc.reportTitle.trim();
  return title;
}

double estimateTitleReserve({
  required String title,
  required double fontScale,
}) {
  if (title.trim().isEmpty) return 0.0;
  final contentFontSize = 11.0 * fontScale;
  final lineHeight = contentFontSize * 1.35;
  return lineHeight + 12.0;
}

double estimateSubjectInfoHeight(
  ReportDoc doc, {
  required double fontScale,
}) {
  final def = doc.subjectInfoDef;
  final fields = def.orderedFields;
  if (!def.enabled || fields.isEmpty) return 0.0;

  final cols = max(1, def.columns);
  final rows = (fields.length / cols).ceil();
  final headerHeight = 24.0 * fontScale;
  final rowHeight = 22.0 * fontScale;
  final verticalGap = 6.0 * fontScale;
  final containerPadding = 20.0;

  return headerHeight + (rows * rowHeight) + ((rows - 1) * verticalGap) + containerPadding;
}

double estimateSubjectInfoReserve(
  ReportDoc doc, {
  required double fontScale,
}) {
  final h = estimateSubjectInfoHeight(doc, fontScale: fontScale);
  return h <= 0 ? 0.0 : h + 12.0;
}

double estimateSignatureHeight({
  required double fontScale,
}) {
  return max(120.0, 135.0 * fontScale);
}

int computeInlineSlotsThatFit({
  required double availableHeight,
  required double fontScale,
  required PdfLayoutMetrics metrics,
  int? maxSlots,
}) {
  final slotHeight = metrics.inlineSlotHeight * fontScale;
  final gap = metrics.inlineSlotGap * fontScale;
  final limit = maxSlots ?? metrics.maxPage1InlineSlots;

  int fit = 0;
  double used = 0;
  for (int i = 0; i < limit; i++) {
    final needed = used + slotHeight + (i == 0 ? 0 : gap);
    if (needed <= availableHeight) {
      used = needed;
      fit++;
    } else {
      break;
    }
  }
  return fit.clamp(0, limit);
}

int estimateSmartFirstPageCharBudget({
  required double usableHeight,
  required double availableMainHeight,
  required bool inlineEnabled,
  required int inlineSlotsUsed,
  required double fontScale,
}) {
  final base = inlineEnabled ? 900 : 1400;
  final heightFactor = usableHeight <= 0
      ? 1.0
      : (availableMainHeight / usableHeight).clamp(0.25, 1.0);

  final slotBonus = inlineEnabled ? (4 - inlineSlotsUsed) * 90 : 0;
  final scaled = ((base * heightFactor) + slotBonus) / max(0.7, fontScale);
  return scaled.round().clamp(350, 2200);
}

List<List<T>> chunked<T>(List<T> items, int size) {
  final chunks = <List<T>>[];
  for (var i = 0; i < items.length; i += size) {
    chunks.add(items.sublist(i, (i + size).clamp(0, items.length)));
  }
  return chunks;
}
