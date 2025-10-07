// lib/services/media_service.dart
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class MediaService {
  static final ImagePicker _picker = ImagePicker();

  /// Abre la cámara o galería y guarda la imagen en almacenamiento interno de la app.
  /// Devuelve el File final (copiado) o null si el usuario canceló.
  static Future<File?> pickAndSaveLocal({required bool fromCamera}) async {
    final xfile = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 85, // reduce tamaño
    );
    if (xfile == null) return null;

    final appDir = await getApplicationDocumentsDirectory();
    final fileName = 'obs_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final savedPath = '${appDir.path}/$fileName';

    final savedFile = await File(xfile.path).copy(savedPath);
    return savedFile;
  }
}
