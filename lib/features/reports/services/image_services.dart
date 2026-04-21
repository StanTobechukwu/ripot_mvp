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

  Future<List<String>> pickFromGallery() async {
    if (_useDesktopFilePicker) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return [];

      return result.files
          .map((f) => f.path)
          .whereType<String>()
          .where((p) => p.trim().isNotEmpty)
          .toList();
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
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (image == null) return null;
    return xFileToPortableRef(image, fileStem: 'cam');
  }
}
