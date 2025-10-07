// lib/services/foto_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui; // para dimensiones cuando no vienen en EXIF
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:exif/exif.dart';
import 'package:crypto/crypto.dart';

// 👇 importa el modelo para tipar fuerte
import 'package:faunadmin2/models/photo_media.dart';

class FotoService {
  final _db = FirebaseFirestore.instance;
  final _st = FirebaseStorage.instance;
  final _picker = ImagePicker();

  // ===== Helpers de ID / texto =====
  String _initials(String nombre) =>
      nombre.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).join();

  String _pad5(int n) => n.toString().padLeft(5, '0');
  String _yy(int y) => (y % 100).toString().padLeft(2, '0');

  Future<int> _reservarConsecutivo(String uid, int anio) async {
    final ref = _db.collection('contadores').doc('${uid}_$anio');
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final next = ((snap.data()?['nextSeq']) ?? 1) as int;
      tx.set(ref, {'nextSeq': next + 1}, SetOptions(merge: true));
      return next;
    });
  }

  Future<int> _obtenerIndiceContexto({
    required String uid,
    required int anio,
    required String tipo,   // "PI" | "RES" | "OTRO"
    required String nombre, // nombre del proyecto/residencia/otro
  }) async {
    final base = _db.collection('contextos').doc(uid).collection('$anio');
    final entries = base.doc('items').collection('entries');
    final itemRef = entries.doc('${tipo}_$nombre');
    final snap = await itemRef.get();
    if (snap.exists) return (snap.data()?['indice'] ?? 1) as int;

    final q = await entries.where('tipo', isEqualTo: tipo).get();
    final idx = (q.size) + 1;
    await itemRef.set({'tipo': tipo, 'nombre': nombre, 'indice': idx});
    return idx;
  }

  String _buildIdFoto({
    required int consecutivo,
    required int anio,
    required String iniciales,
    required String sufijoBase, // "PI" | "RES" | "OTRO"
    int? indiceContexto,        // 1..N si aplica
  }) {
    final seq = _pad5(consecutivo);
    final a2 = _yy(anio);
    final suf = (indiceContexto != null && indiceContexto > 0) ? '$sufijoBase$indiceContexto' : sufijoBase;
    return '${seq}_${a2}_${iniciales}_$suf';
  }

  // ===== Dimensiones a partir de bytes (fallback si EXIF no trae) =====
  Future<List<int>?> _inferSizeFromBytes(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final fi = await codec.getNextFrame();
      return [fi.image.width, fi.image.height];
    } catch (_) {
      return null;
    }
  }

  // ===== EXIF / hash =====
  Future<Map<String, dynamic>> _leerExifYHash(File file) async {
    final bytes = await file.readAsBytes();
    final tags = await readExifFromBytes(bytes);

    // Fecha
    DateTime fecha = DateTime.now();
    final dt = tags['EXIF DateTimeOriginal']?.printable ?? tags['Image DateTime']?.printable;
    if (dt != null) {
      try {
        final norm1 = dt.replaceFirst(' ', 'T');
        fecha = DateTime.tryParse(norm1) ?? DateTime.tryParse(norm1.replaceAll(':', '-')) ?? fecha;
      } catch (_) {}
    }

    // GPS
    double? _parseCoord(String? printableValues, String? printableRef) {
      if (printableValues == null || printableRef == null) return null;
      double _num(String t) {
        if (t.contains('/')) {
          final p = t.split('/');
          final a = double.tryParse(p[0]) ?? 0;
          final b = double.tryParse(p[1]) ?? 1;
          return b == 0 ? 0 : a / b;
        }
        return double.tryParse(t) ?? 0;
      }
      final parts = RegExp(r'(\d+(?:\.\d+)?(?:/\d+)?)').allMatches(printableValues).map((m) => m.group(1)!).toList();
      if (parts.length < 3) return null;
      final d = _num(parts[0]);
      final m = _num(parts[1]);
      final s2 = _num(parts[2]);
      double val = d + (m / 60.0) + (s2 / 3600.0);
      final ref = printableRef.trim().toUpperCase();
      if (ref == 'S' || ref == 'W') val = -val;
      return val;
    }

    final lat = _parseCoord(tags['GPS GPSLatitude']?.printable, tags['GPS GPSLatitudeRef']?.printable);
    final lng = _parseCoord(tags['GPS GPSLongitude']?.printable, tags['GPS GPSLongitudeRef']?.printable);

    // Hash SHA-256
    final sha = sha256.convert(bytes).toString();

    // Marca/Modelo y dimensiones
    final make   = tags['Image Make']?.printable?.trim();
    final model  = tags['Image Model']?.printable?.trim();
    final width  = int.tryParse(tags['EXIF ExifImageWidth']?.printable ?? '');
    final height = int.tryParse(tags['EXIF ExifImageLength']?.printable ?? '');

    // Fallback de dimensiones
    int? w = width, h = height;
    if (w == null || h == null) {
      final sz = await _inferSizeFromBytes(bytes);
      if (sz != null && sz.length == 2) {
        w = sz[0];
        h = sz[1];
      }
    }

    return {
      'fechaLocal': fecha.toLocal(),
      'gps': {'lat': lat, 'lng': lng},
      'sha256': sha,
      'camera_model': [make, model].where((e) => (e ?? '').isNotEmpty).join(' ').trim(),
      'width': w,
      'height': h,
      'bytes': bytes,  // para fileSize
    };
  }

  // ===== Subir UNA foto (catálogo general 'fotos') =====
  Future<Map<String, dynamic>> capturarYGuardar({
    required String fotografoUid,
    required String fotografoNombre,
    required String contextoTipo,   // "PROYECTO_INVESTIGACION" | "RESIDENCIA" | "OTRO"
    required String contextoNombre,
    String? observaciones,
    bool desdeGaleria = false,
    File? archivoLocal,
  }) async {
    final file = archivoLocal ??
        File((await _picker.pickImage(
          source: desdeGaleria ? ImageSource.gallery : ImageSource.camera,
          imageQuality: 95,
        ))!.path);

    final ex = await _leerExifYHash(file);
    final fecha = (ex['fechaLocal'] as DateTime);
    final anio = fecha.year;
    final iniciales = _initials(fotografoNombre);
    final seq  = await _reservarConsecutivo(fotografoUid, anio);
    final sufBase = (contextoTipo == 'PROYECTO_INVESTIGACION')
        ? 'PI' : (contextoTipo == 'RESIDENCIA' ? 'RES' : 'OTRO');
    final indice = await _obtenerIndiceContexto(
      uid: fotografoUid, anio: anio, tipo: sufBase, nombre: contextoNombre,
    );
    final idFoto = _buildIdFoto(
      consecutivo: seq, anio: anio, iniciales: iniciales,
      sufijoBase: sufBase, indiceContexto: indice,
    );

    final storagePath = 'fotos/$anio/$iniciales/$idFoto.jpg';
    final upload = await _st.ref(storagePath).putFile(
      file, SettableMetadata(contentType: 'image/jpeg'),
    );
    final url = await upload.ref.getDownloadURL();

    final gps = (ex['gps'] as Map<String, dynamic>);
    final doc = {
      'idFoto': idFoto,
      'archivoPath': storagePath,  // fullPath para SDK
      'archivoUrl': url,           // URL https para UI 👈
      'fotografoUid': fotografoUid,
      'fotografoNombre': fotografoNombre,
      'iniciales': iniciales,
      'contextoTipo': contextoTipo,
      'contextoNombre': contextoNombre,
      'contextoIndice': indice,
      'observaciones': observaciones ?? '',
      'fechaCaptura': Timestamp.fromDate(fecha.toUtc()),
      'anio': fecha.year,
      'mes': fecha.month,
      'dia': fecha.day,
      'gps': {'lat': gps['lat'], 'lng': gps['lng']},
      'exif': {
        'cameraModel': ex['camera_model'],
        'width': ex['width'],
        'height': ex['height'],
      },
      'hashArchivo': 'sha256:${ex['sha256']}',
      'aiModel': null,
      'aiVersion': null,
      'aiSuggestions': [],
      'aiChosenLabel': null,
      'aiReviewed': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _db.collection('fotos').doc(idFoto).set(doc, SetOptions(merge: true));
    return {'idFoto': idFoto, 'url': url, 'anio': anio, 'doc': doc};
  }

  // ===== Heurísticas simples de calidad/flags =====
  Map<String, dynamic> _buildQualityAndFlags({
    required int? width,
    required int? height,
    required String? cameraModel,
    required double? lat,
    required double? lng,
  }) {
    final flags = <String>[];

    final hasExifBasic = (cameraModel != null && cameraModel.trim().isNotEmpty) ||
        (lat != null && lng != null);
    if (!hasExifBasic) flags.add('no_metadata');

    String quality = 'good';
    if ((width ?? 0) < 800 || (height ?? 0) < 800) {
      quality = 'low';
    }

    return {'quality': quality, 'flags': flags};
  }

  Future<bool> _existsDuplicateShaInObservation({
    required String observacionId,
    required String sha256hex,
  }) async {
    final q = await _db
        .collection('observaciones')
        .doc(observacionId)
        .collection('media')
        .where('sha256', isEqualTo: sha256hex)
        .limit(1)
        .get();
    return q.docs.isNotEmpty;
  }

  // ===== Subir VARIAS y crear espejo en observaciones/{obsId}/media =====
  Future<List<PhotoMedia>> subirVarias({
    required String fotografoUid,
    required String fotografoNombre,
    required String contextoTipo,
    required String contextoNombre,
    required String observacionId,            // vínculo directo
    required List<File> archivos,
    String? observaciones,
    bool desdeGaleria = false,
  }) async {
    final resultados = <PhotoMedia>[];

    for (final f in archivos) {
      // 1) Sube y registra en colección general (consecutivo/ID humanos)
      final r = await capturarYGuardar(
        fotografoUid: fotografoUid,
        fotografoNombre: fotografoNombre,
        contextoTipo: contextoTipo,
        contextoNombre: contextoNombre,
        observaciones: observaciones,
        archivoLocal: f,
        desdeGaleria: desdeGaleria,
      );

      // 2) EXIF / hash / dimensiones
      final ex = await _leerExifYHash(f);
      final gps    = ex['gps'] as Map<String, dynamic>;
      final cam    = ex['camera_model'] as String?;
      final width  = ex['width'] as int?;
      final height = ex['height'] as int?;
      final bytes  = ex['bytes'] as Uint8List;
      final fileSize = bytes.lengthInBytes;
      final lat = gps['lat'] as double?;
      final lng = gps['lng'] as double?;

      // 3) Flags/quality
      final qf = _buildQualityAndFlags(
        width: width, height: height, cameraModel: cam, lat: lat, lng: lng,
      );
      final shaHex = ex['sha256'] as String;

      // 4) Duplicado en la misma observación
      final dup = await _existsDuplicateShaInObservation(
        observacionId: observacionId, sha256hex: shaHex,
      );
      final flags = <String>[...(qf['flags'] as List<String>)];
      if (dup) flags.add('duplicate');

      // 5) Construir PhotoMedia y guardar espejo en subcolección
      final media = PhotoMedia(
        id: null,
        observacionId: observacionId,
        type: MediaType.photo,
        source: desdeGaleria ? MediaSource.gallery : MediaSource.camera,
        storagePath: r['doc']['archivoPath'] as String,
        url: r['doc']['archivoUrl'] as String,      // 👈 listo para UI
        thumbnailPath: null,
        width: width,
        height: height,
        fileSize: fileSize,
        capturedAt: (r['doc']['fechaCaptura'] as Timestamp).toDate(),
        gpsLat: lat,
        gpsLng: lng,
        altitude: null,
        cameraModel: cam,
        aperture: null,
        exposureTime: null,
        iso: null,
        focalLength: null,
        exposureMode: null,
        flashUsed: null,
        orientation: null,
        originalFileName: f.path.split('/').last,
        originalFileId: null,
        sha256: shaHex,
        edited: null,
        editHistory: null,
        iptc: null,
        xmp: null,
        authenticity: 'unknown',
        quality: qf['quality'] as String,
        confidence: null,
        flags: flags,
        createdAt: DateTime.now(),
        createdBy: fotografoUid,
      );

      await _db
          .collection('observaciones')
          .doc(observacionId)
          .collection('media')
          .add(media.toMap());

      resultados.add(media);
    }

    return resultados;
  }
}


