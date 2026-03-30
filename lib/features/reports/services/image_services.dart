import 'package:image_picker/image_picker.dart';

import 'media_ref.dart';

class ImageService {
  final ImagePicker _picker = ImagePicker();

  Future<List<String>> pickFromGallery() async {
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
