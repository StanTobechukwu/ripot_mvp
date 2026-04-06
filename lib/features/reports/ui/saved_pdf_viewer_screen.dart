import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/web/file_download.dart';

class SavedPdfViewerScreen extends StatelessWidget {
  final String title;
  final String pdfFileName;
  final Future<Uint8List?> pdfBytesFuture;

  const SavedPdfViewerScreen({
    super.key,
    required this.title,
    required this.pdfFileName,
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

          final mq = MediaQuery.of(context);
          final isDesktopWeb = kIsWeb && mq.size.width >= 900;
          final preview = PdfPreview(
            build: (_) async => bytes,
            pdfFileName: pdfFileName,
            allowPrinting: true,
            allowSharing: !isDesktopWeb,
          );

          if (!isDesktopWeb) return preview;

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: const Color(0xFFF8FAFC),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'On desktop web, use Download PDF, then share the file from your downloads.',
                        style: TextStyle(fontSize: 12.5, color: Colors.black54),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => downloadBytes(bytes: bytes, fileName: pdfFileName),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Download PDF'),
                    ),
                  ],
                ),
              ),
              Expanded(child: preview),
            ],
          );
        },
      ),
    );
  }
}
