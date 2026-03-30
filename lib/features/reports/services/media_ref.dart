import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'platforms/file_loader.dart';
import 'platforms/media_store.dart';

bool isDataUri(String ref) => ref.startsWith('data:');

String bytesToDataUri(Uint8List bytes, {String mimeType = 'application/octet-stream'}) {
  return 'data:$mimeType;base64,${base64Encode(bytes)}';
}

Uint8List? bytesFromDataUri(String ref) {
  if (!isDataUri(ref)) return null;
  final comma = ref.indexOf(',');
  if (comma == -1 || comma == ref.length - 1) return null;
  try {
    return base64Decode(ref.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

Future<String> persistBytesAsRef(
  Uint8List bytes, {
  required String fileStem,
  String extension = 'bin',
  String mimeType = 'application/octet-stream',
}) async {
  return savePortableBytes(
    bytes,
    fileStem: fileStem,
    extension: extension,
    mimeType: mimeType,
  );
}

Future<String> xFileToPortableRef(
  XFile file, {
  required String fileStem,
}) async {
  if (!kIsWeb && file.path.isNotEmpty) {
    return file.path;
  }

  final bytes = await file.readAsBytes();
  final lower = file.name.toLowerCase();
  final mime = lower.endsWith('.png')
      ? 'image/png'
      : lower.endsWith('.webp')
          ? 'image/webp'
          : 'image/jpeg';
  final ext = lower.endsWith('.png')
      ? 'png'
      : lower.endsWith('.webp')
          ? 'webp'
          : 'jpg';
  return persistBytesAsRef(bytes, fileStem: fileStem, extension: ext, mimeType: mime);
}

class RefImage extends StatelessWidget {
  final String ref;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const RefImage(
    this.ref, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: readFileBytes(ref),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            width: width,
            height: height,
            child: placeholder ?? const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return SizedBox(
            width: width,
            height: height,
            child: errorWidget ?? const Icon(Icons.broken_image_outlined),
          );
        }

        return Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          gaplessPlayback: true,
        );
      },
    );
  }
}
