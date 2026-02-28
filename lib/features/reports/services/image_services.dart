import 'dart:io';
import 'package:image_picker/image_picker.dart';
//import '.../features/services/image_services.dart';

class ImageService {
  final ImagePicker _picker = ImagePicker();

  /// Pick multiple images from gallery
  Future<List<File>> pickFromGallery() async {
    final images = await _picker.pickMultiImage(imageQuality: 85);
    return images.map((e) => File(e.path)).toList();
  }

    // ✅ Alias so your editor can call this name too
  Future<List<File>> pickMultiFromGallery() => pickFromGallery();

  /// Capture image from camera
  Future<File?> pickFromCamera() async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (image == null) return null;
    return File(image.path);
  }
}
