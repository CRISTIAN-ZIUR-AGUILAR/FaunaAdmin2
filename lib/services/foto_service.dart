// lib/services/foto_service.dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io' as io show File;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:exif/exif.dart';
import 'package:crypto/crypto.dart';

import 'package:faunadmin2/models/photo_media.dart';

class FotoService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ✅ Storage: usa bucket explícito SOLO en Web (el que sí existe y tiene CORS).
  //    En móvil/desktop sigue usando el default de la app.
  late final FirebaseStorage _st = kIsWeb
      ? FirebaseStorage.instanceFor(bucket: 'gs://fauna2admin.firebasestorage.app')
      : FirebaseStorage.instance;

  final _picker = ImagePicker();

  FotoService() {
    // Aumenta tiempos de reintento para depurar conexiones lentas
    _st.setMaxUploadRetryTime(const Duration(minutes: 10));
    _st.setMaxOperationRetryTime(const Duration(minutes: 10));
    _st.setMaxDownloadRetryTime(const Duration(minutes: 10));

    // Log útil para verificar que quedó el bucket correcto
    // (En Web debe imprimir: fauna2admin.firebasestorage.app)
    // ignore: avoid_print
    print('[STORAGE] Using bucket="${_st.bucket}" kIsWeb=$kIsWeb');
  }

  // =========================
  // Helpers de ID / texto
  // =========================
  String _initials(String nombre) => nombre
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase())
      .join();

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
    final suf = (indiceContexto != null && indiceContexto > 0)
        ? '$sufijoBase$indiceContexto'
        : sufijoBase;
    return '${seq}_${a2}_${iniciales}_$suf';
  }

  // =========================
  // Logging centralizado
  // =========================
  void _logStorageError(Object e, StackTrace st, {
    required String operacion,
    required String path,
    String? contentType,
  }) {
    print('❌ STORAGE $operacion FAILED');
    print('   • path=$path  contentType=$contentType');
    if (e is FirebaseException) {
      print('   • plugin=${e.plugin}  code=${e.code}');
      print('   • message=${e.message}');
    } else {
      print('   • error=$e');
    }
    print('   • stack=$st');
  }

  // =========================
  // MIME / extensión
  // =========================
  String _guessMimeFromName(String? name) {
    final n = (name ?? '').toLowerCase();
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.heic')) return 'image/heic';
    if (n.endsWith('.heif')) return 'image/heif';
    if (n.endsWith('.avif')) return 'image/avif';
    return 'application/octet-stream';
  }

  String _guessMimeFromBytes(Uint8List bytes, {String? fallbackName}) {
    // JPEG FF D8
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'image/jpeg';
    }
    // PNG 89 50 4E 47 0D 0A 1A 0A
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    // WEBP "RIFF....WEBP"
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return 'image/webp';
    }
    // Si no se puede inferir, usamos el nombre como pista.
    return _guessMimeFromName(fallbackName);
  }

  String _extFromMime(String mime) {
    switch (mime) {
      case 'image/jpeg':
        return '.jpg';
      case 'image/png':
        return '.png';
      case 'image/webp':
        return '.webp';
      case 'image/heic':
        return '.heic';
      case 'image/heif':
        return '.heif';
      case 'image/avif':
        return '.avif';
      default:
      // por compatibilidad, forzamos .jpg si es desconocido
        return '.jpg';
    }
  }

  // =========================
  // Dimensiones / EXIF / hash
  // =========================
  Future<List<int>?> _inferSizeFromBytes(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final fi = await codec.getNextFrame();
      return [fi.image.width, fi.image.height];
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _leerExifYHash(io.File file) async {
    final bytes = await file.readAsBytes();
    return _leerExifYHashFromBytes(bytes);
  }

  Future<Map<String, dynamic>> _leerExifYHashFromBytes(Uint8List bytes) async {
    final tags = await readExifFromBytes(bytes);

    // Fecha
    DateTime fecha = DateTime.now();
    final dt = tags['EXIF DateTimeOriginal']?.printable ??
        tags['Image DateTime']?.printable;
    if (dt != null) {
      try {
        final norm1 = dt.replaceFirst(' ', 'T');
        fecha = DateTime.tryParse(norm1) ??
            DateTime.tryParse(norm1.replaceAll(':', '-')) ??
            fecha;
      } catch (_) {}
    }

    // GPS
    double? _parseCoord(String? values, String? ref) {
      if (values == null || ref == null) return null;
      double _num(String t) {
        if (t.contains('/')) {
          final p = t.split('/');
          final a = double.tryParse(p[0]) ?? 0;
          final b = double.tryParse(p[1]) ?? 1;
          return b == 0 ? 0 : a / b;
        }
        return double.tryParse(t) ?? 0;
      }

      final parts = RegExp(r'(\d+(?:\.\d+)?(?:/\d+)?)')
          .allMatches(values)
          .map((m) => m.group(1)!)
          .toList();
      if (parts.length < 3) return null;
      final d = _num(parts[0]);
      final m = _num(parts[1]);
      final s2 = _num(parts[2]);
      double val = d + (m / 60.0) + (s2 / 3600.0);
      final r = ref.trim().toUpperCase();
      if (r == 'S' || r == 'W') val = -val;
      return val;
    }

    final lat = _parseCoord(
        tags['GPS GPSLatitude']?.printable, tags['GPS GPSLatitudeRef']?.printable);
    final lng = _parseCoord(
        tags['GPS GPSLongitude']?.printable, tags['GPS GPSLongitudeRef']?.printable);

    // Hash
    final sha = sha256.convert(bytes).toString();

    // Cámara / dimensiones
    final make = tags['Image Make']?.printable?.trim();
    final model = tags['Image Model']?.printable?.trim();
    final width = int.tryParse(tags['EXIF ExifImageWidth']?.printable ?? '');
    final height = int.tryParse(tags['EXIF ExifImageLength']?.printable ?? '');

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
      'bytes': bytes,
    };
  }

  // =========================
  // Resolver HTTPS desde cualquier forma (https|gs|path)
  // =========================
  Future<String> resolveHttpsFromAny(String s) async {
    if (s.startsWith('http')) return s;
    if (s.startsWith('gs://')) {
      final idx = s.indexOf('/', 5);
      final path = (idx > 0) ? s.substring(idx + 1) : s.replaceFirst('gs://', '');
      return _st.ref(path).getDownloadURL();
    }
    return _st.ref(s).getDownloadURL();
  }

  // =========================
  // Subir UNA (desde File) – móvil/desktop
  // =========================
  Future<Map<String, dynamic>> capturarYGuardar({
    required String fotografoUid,
    required String fotografoNombre,
    required String contextoTipo,
    required String contextoNombre,
    String? observaciones,
    bool desdeGaleria = false,
    io.File? archivoLocal,
  }) async {
    final file = archivoLocal ??
        io.File(
          (await _picker.pickImage(
            source: desdeGaleria ? ImageSource.gallery : ImageSource.camera,
            imageQuality: 95,
          ))!.path,
        );

    final ex = await _leerExifYHash(file);
    final fecha = (ex['fechaLocal'] as DateTime);
    final anio = fecha.year;
    final iniciales = _initials(fotografoNombre);
    final seq = await _reservarConsecutivo(fotografoUid, anio);
    final sufBase = (contextoTipo == 'PROYECTO_INVESTIGACION')
        ? 'PI'
        : (contextoTipo == 'RESIDENCIA' ? 'RES' : 'OTRO');
    final indice = await _obtenerIndiceContexto(
      uid: fotografoUid, anio: anio, tipo: sufBase, nombre: contextoNombre,
    );

    final idFoto = _buildIdFoto(
      consecutivo: seq, anio: anio, iniciales: iniciales,
      sufijoBase: sufBase, indiceContexto: indice,
    );

    final storagePath = 'fotos/$anio/$iniciales/$idFoto.jpg';
    final ref = _st.ref(storagePath);

    try {
      print('[STORAGE] putFile -> bucket=${_st.bucket} path=$storagePath');
      final task = ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));

      task.snapshotEvents.listen((s) {
        final pct = (s.totalBytes == 0)
            ? 0
            : (s.bytesTransferred * 100 ~/ s.totalBytes);
        print('[STORAGE] progress($idFoto) state=${s.state} '
            'bytes=${s.bytesTransferred}/${s.totalBytes} ($pct%)');
      }, onError: (err, st) {
        _logStorageError(err, st, operacion: 'snapshotEvents', path: storagePath, contentType: 'image/jpeg');
      });

      final snap = await task.timeout(const Duration(minutes: 5));
      print('[STORAGE] upload complete($idFoto) state=${snap.state} bytes=${snap.bytesTransferred}');

      final httpsUrl = await ref.getDownloadURL();
      print('[STORAGE] getDownloadURL OK ($idFoto) -> $httpsUrl');

      final gps = (ex['gps'] as Map<String, dynamic>);
      final doc = {
        'idFoto': idFoto,
        'archivoPath': storagePath,
        'archivoUrl': httpsUrl,
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

      print('[FIRESTORE] set(fotos/$idFoto) ...');
      await _db.collection('fotos').doc(idFoto).set(doc, SetOptions(merge: true));
      print('[FIRESTORE] set OK(fotos/$idFoto)');

      return {
        'idFoto': idFoto,
        'url': httpsUrl,
        'storagePath': storagePath,
        'anio': anio,
        'doc': doc,
      };
    } on TimeoutException catch (e, st) {
      _logStorageError(e, st, operacion: 'putFile TIMEOUT', path: storagePath, contentType: 'image/jpeg');
      rethrow;
    } catch (e, st) {
      _logStorageError(e, st, operacion: 'putFile', path: storagePath, contentType: 'image/jpeg');
      rethrow;
    }
  }

  // =========================
  // Subir UNA (desde BYTES) – Web
  // =========================
  Future<Map<String, dynamic>> capturarYGuardarFromBytes({
    required String fotografoUid,
    required String fotografoNombre,
    required String contextoTipo,
    required String contextoNombre,
    required Uint8List bytes,
    String? fileName,
    String? observaciones,
    bool desdeGaleria = false,
  }) async {
    final ex = await _leerExifYHashFromBytes(bytes);
    final fecha = (ex['fechaLocal'] as DateTime);
    final anio = fecha.year;
    final iniciales = _initials(fotografoNombre);
    final seq = await _reservarConsecutivo(fotografoUid, anio);
    final sufBase = (contextoTipo == 'PROYECTO_INVESTIGACION')
        ? 'PI'
        : (contextoTipo == 'RESIDENCIA' ? 'RES' : 'OTRO');
    final indice = await _obtenerIndiceContexto(
      uid: fotografoUid, anio: anio, tipo: sufBase, nombre: contextoNombre,
    );

    final idFoto = _buildIdFoto(
      consecutivo: seq, anio: anio, iniciales: iniciales,
      sufijoBase: sufBase, indiceContexto: indice,
    );

    var contentType = _guessMimeFromBytes(bytes, fallbackName: fileName);
    if (contentType == 'application/octet-stream' || contentType.isEmpty) {
      contentType = 'image/jpeg';
    }
    final ext = _extFromMime(contentType);
    final storagePath = 'fotos/$anio/$iniciales/$idFoto$ext';
    final ref = _st.ref(storagePath);

    try {
      print('[STORAGE] putData -> bucket=${_st.bucket} path=$storagePath '
          '(${bytes.length} bytes, $contentType)');
      final task = ref.putData(bytes, SettableMetadata(contentType: contentType));

      task.snapshotEvents.listen((s) {
        final pct = (s.totalBytes == 0)
            ? 0
            : (s.bytesTransferred * 100 ~/ s.totalBytes);
        print('[STORAGE] progress($idFoto) state=${s.state} '
            'bytes=${s.bytesTransferred}/${s.totalBytes} ($pct%)');
      }, onError: (err, st) {
        _logStorageError(err, st, operacion: 'snapshotEvents', path: storagePath, contentType: contentType);
      });

      final snap = await task.timeout(const Duration(minutes: 5));
      print('[STORAGE] upload complete($idFoto) state=${snap.state} bytes=${snap.bytesTransferred}');

      final httpsUrl = await ref.getDownloadURL();
      print('[STORAGE] getDownloadURL OK ($idFoto) -> $httpsUrl');

      final gps = (ex['gps'] as Map<String, dynamic>);
      final doc = {
        'idFoto': idFoto,
        'archivoPath': storagePath,
        'archivoUrl': httpsUrl,
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
        'originalFileName': fileName,
        'aiModel': null,
        'aiVersion': null,
        'aiSuggestions': [],
        'aiChosenLabel': null,
        'aiReviewed': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      print('[FIRESTORE] set(fotos/$idFoto) ...');
      await _db.collection('fotos').doc(idFoto).set(doc, SetOptions(merge: true));
      print('[FIRESTORE] set OK(fotos/$idFoto)');

      return {
        'idFoto': idFoto,
        'url': httpsUrl,
        'storagePath': storagePath,
        'anio': anio,
        'doc': doc,
      };
    } on TimeoutException catch (e, st) {
      _logStorageError(e, st, operacion: 'putData TIMEOUT', path: storagePath, contentType: contentType);
      rethrow;
    } catch (e, st) {
      _logStorageError(e, st, operacion: 'putData', path: storagePath, contentType: contentType);
      rethrow;
    }
  }

  // =========================
  // Calidad / flags / duplicados
  // =========================
  Map<String, dynamic> _buildQualityAndFlags({
    required int? width,
    required int? height,
    required String? cameraModel,
    required double? lat,
    required double? lng,
  }) {
    final flags = <String>[];
    final hasExifBasic =
        (cameraModel != null && cameraModel.trim().isNotEmpty) ||
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

  // =========================
  // PRIVADO: Subir VARIAS (Files) – móvil/desktop
  // =========================
  Future<List<PhotoMedia>> _subirVariasFiles({
    required String fotografoUid,
    required String fotografoNombre,
    required String contextoTipo,
    required String contextoNombre,
    required String observacionId,
    required List<io.File> archivos,
    String? observaciones,
    bool desdeGaleria = false,
  }) async {
    print('[BATCH] _subirVariasFiles count=${archivos.length} obs=$observacionId');
    final resultados = <PhotoMedia>[];
    final urlsParaObs = <String>[];
    final pathsParaObs = <String>[];

    for (final f in archivos) {
      print('[BATCH] item -> ${f.path}');
      Map<String, dynamic> r;
      try {
        r = await capturarYGuardar(
          fotografoUid: fotografoUid,
          fotografoNombre: fotografoNombre,
          contextoTipo: contextoTipo,
          contextoNombre: contextoNombre,
          observaciones: observaciones,
          archivoLocal: f,
          desdeGaleria: desdeGaleria,
        );
      } catch (e) {
        print('❌ capturarYGuardar(File) falló -> $e');
        continue;
      }

      final httpsUrl = r['url'] as String;
      final storagePath = r['storagePath'] as String;
      urlsParaObs.add(httpsUrl);
      pathsParaObs.add(storagePath);

      // 2) EXIF / hash / dimensiones
      final ex = await _leerExifYHash(f);
      final gps = ex['gps'] as Map<String, dynamic>;
      final cam = ex['camera_model'] as String?;
      final width = ex['width'] as int?;
      final height = ex['height'] as int?;
      final bytes = ex['bytes'] as Uint8List;
      final fileSize = bytes.lengthInBytes;
      final lat = gps['lat'] as double?;
      final lng = gps['lng'] as double?;

      // 3) Flags / duplicado
      final qf = _buildQualityAndFlags(
        width: width, height: height, cameraModel: cam, lat: lat, lng: lng,
      );
      final shaHex = ex['sha256'] as String;
      final dup = await _existsDuplicateShaInObservation(
        observacionId: observacionId, sha256hex: shaHex,
      );
      final flags = <String>[...(qf['flags'] as List<String>)];
      if (dup) flags.add('duplicate');

      // 4) Espejo en subcolección
      final media = PhotoMedia(
        id: null,
        observacionId: observacionId,
        type: MediaType.photo,
        source: desdeGaleria ? MediaSource.gallery : MediaSource.camera,
        storagePath: storagePath,
        url: httpsUrl,
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
      print('[BATCH] item OK -> $storagePath');
    }

    // 5) Actualizar agregados
    final obsRef = _db.collection('observaciones').doc(observacionId);
    print('[BATCH] updating agregados obs=$observacionId urls+=${urlsParaObs.length}');
    await _db.runTransaction((tx) async {
      final snap = await tx.get(obsRef);
      final prevUrls = ((snap.data()?['media_urls']) as List?)?.cast<String>() ?? <String>[];
      final prevPaths = ((snap.data()?['media_storage_paths']) as List?)?.cast<String>() ?? <String>[];
      final newUrls = [...prevUrls, ...urlsParaObs];
      final newPaths = [...prevPaths, ...pathsParaObs];
      tx.update(obsRef, {
        'media_urls': newUrls,
        'media_storage_paths': newPaths,
        'media_count': newUrls.length,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    print('[BATCH] agregados OK');

    return resultados;
  }

  // =========================
  // Subir VARIAS (BYTES) – Web
  // =========================
  Future<List<PhotoMedia>> subirVariasFromBytes({
    required String fotografoUid,
    required String fotografoNombre,
    required String contextoTipo,
    required String contextoNombre,
    required String observacionId,
    required List<Uint8List> archivosBytes,
    List<String>? fileNames,
    String? observaciones,
    bool desdeGaleria = false,
  }) async {
    print('[BATCH] subirVariasFromBytes count=${archivosBytes.length} obs=$observacionId');
    final resultados = <PhotoMedia>[];
    final urlsParaObs = <String>[];
    final pathsParaObs = <String>[];

    for (var i = 0; i < archivosBytes.length; i++) {
      final bytes = archivosBytes[i];
      final name = (fileNames != null && i < fileNames.length)
          ? fileNames[i]
          : 'web_$i.jpg';

      print('[BATCH] item($i) -> $name (${bytes.length} bytes)');

      Map<String, dynamic> r;
      try {
        r = await capturarYGuardarFromBytes(
          fotografoUid: fotografoUid,
          fotografoNombre: fotografoNombre,
          contextoTipo: contextoTipo,
          contextoNombre: contextoNombre,
          bytes: bytes,
          fileName: name,
          observaciones: observaciones,
          desdeGaleria: desdeGaleria,
        );
      } catch (e) {
        print('❌ capturarYGuardarFromBytes(web) falló -> $e');
        continue;
      }

      final httpsUrl = r['url'] as String;
      final storagePath = r['storagePath'] as String;
      urlsParaObs.add(httpsUrl);
      pathsParaObs.add(storagePath);

      // 2) EXIF / hash / dimensiones
      final ex = await _leerExifYHashFromBytes(bytes);
      final gps = ex['gps'] as Map<String, dynamic>;
      final cam = ex['camera_model'] as String?;
      final width = ex['width'] as int?;
      final height = ex['height'] as int?;
      final fileSize = bytes.lengthInBytes;
      final lat = gps['lat'] as double?;
      final lng = gps['lng'] as double?;

      // 3) Flags / duplicado
      final qf = _buildQualityAndFlags(
        width: width, height: height, cameraModel: cam, lat: lat, lng: lng,
      );
      final shaHex = ex['sha256'] as String;
      final dup = await _existsDuplicateShaInObservation(
        observacionId: observacionId, sha256hex: shaHex,
      );
      final flags = <String>[...(qf['flags'] as List<String>)];
      if (dup) flags.add('duplicate');

      // 4) Espejo en subcolección
      final media = PhotoMedia(
        id: null,
        observacionId: observacionId,
        type: MediaType.photo,
        source: desdeGaleria ? MediaSource.gallery : MediaSource.camera,
        storagePath: storagePath,
        url: httpsUrl,
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
        originalFileName: name,
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
      print('[BATCH] item OK -> $storagePath');
    }

    // 5) Actualizar agregados
    final obsRef = _db.collection('observaciones').doc(observacionId);
    print('[BATCH] updating agregados obs=$observacionId urls+=${urlsParaObs.length}');
    await _db.runTransaction((tx) async {
      final snap = await tx.get(obsRef);
      final prevUrls = ((snap.data()?['media_urls']) as List?)?.cast<String>() ?? <String>[];
      final prevPaths = ((snap.data()?['media_storage_paths']) as List?)?.cast<String>() ?? <String>[];
      final newUrls = [...prevUrls, ...urlsParaObs];
      final newPaths = [...prevPaths, ...pathsParaObs];
      tx.update(obsRef, {
        'media_urls': newUrls,
        'media_storage_paths': newPaths,
        'media_count': newUrls.length,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    print('[BATCH] agregados OK');

    return resultados;
  }

  // =========================
  // PÚBLICO: enruta a web o files
  // =========================
  Future<List<PhotoMedia>> subirVarias({
    required String fotografoUid,
    required String fotografoNombre,
    required String contextoTipo,
    required String contextoNombre,
    required String observacionId,
    required List<dynamic> archivos, // XFile | File | Uint8List
    String? observaciones,
    bool desdeGaleria = false,
  }) async {
    if (kIsWeb) {
      final bytesList = <Uint8List>[];
      final names = <String>[];
      for (final a in archivos) {
        if (a is XFile) {
          print('[ROUTER] Web: XFile -> ${a.name}');
          bytesList.add(await a.readAsBytes());
          names.add(a.name);
        } else if (a is Uint8List) {
          print('[ROUTER] Web: Uint8List -> web_${bytesList.length}.jpg');
          bytesList.add(a);
          names.add('web_${bytesList.length}.jpg');
        } else {
          print('⚠️ Ignorando item no soportado en web: ${a.runtimeType}');
        }
      }
      return subirVariasFromBytes(
        fotografoUid: fotografoUid,
        fotografoNombre: fotografoNombre,
        contextoTipo: contextoTipo,
        contextoNombre: contextoNombre,
        observacionId: observacionId,
        archivosBytes: bytesList,
        fileNames: names,
        observaciones: observaciones,
        desdeGaleria: desdeGaleria,
      );
    } else {
      final files = archivos.whereType<io.File>().toList();
      print('[ROUTER] Mobile/Desktop: Files=${files.length}');
      return _subirVariasFiles(
        fotografoUid: fotografoUid,
        fotografoNombre: fotografoNombre,
        contextoTipo: contextoTipo,
        contextoNombre: contextoNombre,
        observacionId: observacionId,
        archivos: files,
        observaciones: observaciones,
        desdeGaleria: desdeGaleria,
      );
    }
  }
}



