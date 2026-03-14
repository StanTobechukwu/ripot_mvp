import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class SavedPdfViewerScreen extends StatelessWidget {
  final String title;
  final File pdfFile;

  const SavedPdfViewerScreen({
    super.key,
    required this.title,
    required this.pdfFile,
  });

  Future<Uint8List> _loadBytes() => pdfFile.readAsBytes();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PdfPreview(
        build: (_) => _loadBytes(),
        allowPrinting: true,
        allowSharing: true,
      ),
    );
  }
}
