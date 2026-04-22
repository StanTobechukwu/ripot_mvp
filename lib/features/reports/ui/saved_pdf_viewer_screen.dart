import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/web/file_download.dart';
import '../services/pdf_actions_service.dart';

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
          final isNativeDesktop = ripotIsNativeDesktop;
          final preview = PdfPreview(
            build: (_) async => bytes,
            pdfFileName: pdfFileName,
            allowPrinting: !isNativeDesktop,
            allowSharing: !isDesktopWeb && !isNativeDesktop,
          );

          if (!isDesktopWeb && !isNativeDesktop) return preview;

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: const Color(0xFFF8FAFC),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(
                      isDesktopWeb
                          ? 'On desktop web, use Download PDF, then share the file from your downloads.'
                          : 'Use the Ripot buttons for Download, Print, and Share on desktop.',
                      style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () async {
                            try {
                              if (kIsWeb) {
                                await downloadBytes(bytes: bytes, fileName: pdfFileName);
                                return;
                              }
                              final file = await ripotDownloadPdf(bytes: bytes, fileName: pdfFileName);
                              if (!context.mounted) return;
                              if (file == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Download cancelled')),
                                );
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('PDF saved to: ${file.path}')),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Download failed: $e')),
                              );
                            }
                          },
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Download PDF'),
                        ),
                        if (isNativeDesktop) ...[
                          OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                await ripotPrintPdf(bytes: bytes, fileName: pdfFileName);
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Print failed: $e')),
                                );
                              }
                            },
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Print PDF'),
                          ),
                          FilledButton.icon(
                            onPressed: () async {
                              try {
                                await ripotSharePdf(bytes: bytes, fileName: pdfFileName);
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Share failed: $e')),
                                );
                              }
                            },
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('Share PDF'),
                          ),
                        ],
                      ],
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
