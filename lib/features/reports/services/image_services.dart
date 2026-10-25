import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'media_ref.dart';

class ImageService {
  final ImagePicker _picker = ImagePicker();

  bool get _useDesktopFilePicker =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  Future<String> _persistDesktopPath(String path, {required String fileStem}) async {
    final bytes = await File(path).readAsBytes();
    final lower = path.toLowerCase();
    final ext = lower.endsWith('.png')
        ? 'png'
        : lower.endsWith('.webp')
            ? 'webp'
            : lower.endsWith('.gif')
                ? 'gif'
                : 'jpg';
    final mime = ext == 'png'
        ? 'image/png'
        : ext == 'webp'
            ? 'image/webp'
            : ext == 'gif'
                ? 'image/gif'
                : 'image/jpeg';
    return persistBytesAsRef(bytes, fileStem: fileStem, extension: ext, mimeType: mime);
  }

  Future<List<String>> pickFromGallery() async {
    if (_useDesktopFilePicker) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return [];

      final refs = <String>[];
      for (var i = 0; i < result.files.length; i++) {
        final file = result.files[i];
        if (file.path == null || file.path!.trim().isEmpty) continue;
        refs.add(await _persistDesktopPath(file.path!, fileStem: 'desk_img_$i'));
      }
      return refs;
    }

    final images = await _picker.pickMultiImage(imageQuality: 85);
    final refs = <String>[];
    for (var i = 0; i < images.length; i++) {
      refs.add(await xFileToPortableRef(images[i], fileStem: 'img_$i'));
    }
    return refs;
  }

  Future<List<String>> pickMultiFromGallery() => pickFromGallery();

  Future<String?> pickFromCamera() async {
    if (_useDesktopFilePicker) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      final path = (result != null && result.files.isNotEmpty) ? result.files.first.path : null;
      if (path == null || path.trim().isEmpty) return null;
      return _persistDesktopPath(path, fileStem: 'desk_cam');
    }

    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (image == null) return null;
    return xFileToPortableRef(image, fileStem: 'cam');
  }
}
