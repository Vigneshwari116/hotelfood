import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Handles menu-item images.
///
/// Supports:
/// - Camera
/// - Gallery / Albums
///
/// The selected image is copied into the application's
/// persistent support directory so the path remains available
/// after restarting the application.
class ImageService {
  static final ImagePicker _picker = ImagePicker();

  // ============================================================
  // CAMERA
  // ============================================================

  static Future<String?> pickFromCamera({
    required String forId,
  }) async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1200,
      imageQuality: 85,
    );

    if (picked == null) {
      return null;
    }

    return _saveImage(
      picked,
      forId,
    );
  }

  // ============================================================
  // GALLERY / ALBUM
  // ============================================================

  static Future<String?> pickFromGallery({
    required String forId,
  }) async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 85,
    );

    if (picked == null) {
      return null;
    }

    return _saveImage(
      picked,
      forId,
    );
  }

  // ============================================================
  // SAVE IMAGE PERMANENTLY
  // ============================================================

  static Future<String> _saveImage(
      XFile picked,
      String forId,
      ) async {
    final directory =
    await getApplicationSupportDirectory();

    final imagesDirectory = Directory(
      p.join(
        directory.path,
        'images',
      ),
    );

    if (!await imagesDirectory.exists()) {
      await imagesDirectory.create(
        recursive: true,
      );
    }

    String extension =
    p.extension(picked.path);

    if (extension.isEmpty) {
      extension = '.jpg';
    }

    final fileName =
        '$forId${DateTime.now().millisecondsSinceEpoch}$extension';

    final destinationPath = p.join(
      imagesDirectory.path,
      fileName,
    );

    final bytes = await picked.readAsBytes();

    final destinationFile =
    File(destinationPath);

    await destinationFile.writeAsBytes(
      bytes,
      flush: true,
    );

    return destinationPath;
  }

  // ============================================================
  // DELETE IMAGE
  // ============================================================

  static Future<void> delete(
      String? path,
      ) async {
    if (path == null || path.isEmpty) {
      return;
    }

    final file = File(path);

    if (await file.exists()) {
      await file.delete();
    }
  }
}
