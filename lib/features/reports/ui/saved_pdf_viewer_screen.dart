import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class SavedPdfViewerScreen extends StatelessWidget {
  final String title;
  final Future<Uint8List?> pdfBytesFuture;

  const SavedPdfViewerScreen({
    super.key,
    required this.title,
    required this.pdfBytesFuture,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<Uint8List?>(
        future: pdfBytesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) {
            return const Center(child: Text('No saved PDF found.'));
          }
          return PdfPreview(
            build: (_) async => bytes,
            allowPrinting: true,
            allowSharing: true,
          );
        },
      ),
    );
  }
}
