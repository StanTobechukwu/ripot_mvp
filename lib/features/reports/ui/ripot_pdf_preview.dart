import 'dart:async';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/services/engagement_service.dart';

/// Shared by the draft and saved-PDF screens so every preview share is counted.
class RipotPdfPreview extends StatelessWidget {
  const RipotPdfPreview({
    super.key,
    required this.buildDocument,
    required this.pdfFileName,
    this.allowPrinting = true,
    this.allowSharing = true,
  });

  final LayoutCallback buildDocument;
  final String pdfFileName;
  final bool allowPrinting;
  final bool allowSharing;

  @override
  Widget build(BuildContext context) => PdfPreview(
    build: buildDocument,
    pdfFileName: pdfFileName,
    allowPrinting: allowPrinting,
    // printing 5.14.3 forwards its built-in share event to onPrinted instead of
    // onShared. Use the actual share action's callback; counting print events
    // as a workaround would request reviews for the wrong action.
    allowSharing: false,
    actions: [
      if (allowSharing)
        PdfShareAction(
          filename: pdfFileName,
          icon: const Tooltip(message: 'Share PDF', child: Icon(Icons.share)),
          onShared: () => unawaited(EngagementService.reportShared()),
        ),
    ],
  );
}
