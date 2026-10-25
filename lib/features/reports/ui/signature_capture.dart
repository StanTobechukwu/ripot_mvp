import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../services/media_ref.dart';

class SignatureCaptureScreen extends StatefulWidget {
  const SignatureCaptureScreen({super.key});

  @override
  State<SignatureCaptureScreen> createState() => _SignatureCaptureScreenState();
}

class _SignatureCaptureScreenState extends State<SignatureCaptureScreen> {
  late final SignatureController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penStrokeWidth: 3,
      exportBackgroundColor: Colors.white,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<String?> _saveSignature() async {
    if (_controller.isEmpty) return null;

    final Uint8List? bytes = await _controller.toPngBytes();
    if (bytes == null) return null;

    return persistBytesAsRef(
      bytes,
      fileStem: 'signature',
      extension: 'png',
      mimeType: 'image/png',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Signature'),
        actions: [
          TextButton(
            onPressed: () async {
              final path = await _saveSignature();
              if (!context.mounted) return;

              if (path == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please sign before saving')),
                );
                return;
              }
              Navigator.pop(context, path);
            },
            child: const Text('Save'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Signature(
                controller: _controller,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              onPressed: _controller.clear,
              icon: const Icon(Icons.refresh),
              label: const Text('Clear'),
            ),
          ),
        ],
      ),
    );
  }
}
