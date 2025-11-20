import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipo de medio asociado a la observación
class MediaType {
  static const photo = 'photo';
  static const video = 'video';
}

/// Origen del medio (para políticas de confianza)
class MediaSource {
  static const camera = 'camera';
  static const gallery = 'gallery';
  static const external = 'external';
}

/// Veredictos del análisis de autenticidad/calidad a nivel foto
class MediaVerdict {
  // autenticidad
  static const genuine = 'genuine';
  static const suspect = 'suspect';
  static const manipulated = 'manipulated';
  static const unknown = 'unknown';

  // calidad
  static const good = 'good';
  static const low = 'low';
  static const unusable = 'unusable';
}

/// Flags de revisión automática por foto (no bloquean por sí mismas)
class MediaFlags {
  static const notAnimal = 'not_animal';
  static const multipleAnimals = 'multiple_animals';
  static const facesDetected = 'faces_detected';
  static const watermark = 'watermark';
  static const noMetadata = 'no_metadata';
  static const stockLike = 'stock_like';
  static const duplicate = 'duplicate';
}

class PhotoMedia {
  // Identidad / FK
  final String? id;               // id del doc en la subcolección
  final String observacionId;     // FK (por conveniencia en cliente)

  // Identificador humano legible (ej: 00125_RMGU_PI / 00125_RMGU_PI1)
  final String? photoId;

  // Básicos
  final String type;              // MediaType.photo|video
  final String source;            // MediaSource.*
  final String storagePath;       // fullPath en Storage (ej: fotos/2025/XX/ID.jpg)
  final String? url;              // URL https de descarga para Image.network
  final String? thumbnailPath;    // miniatura (opcional)
  final int? width;               // px
  final int? height;              // px
  final int? fileSize;            // bytes

  // EXIF / captura
  final DateTime? capturedAt;     // fecha original EXIF si existe
  final double? gpsLat;           // EXIF si existe
  final double? gpsLng;           // EXIF si existe
  final double? altitude;         // metros (EXIF GPS Altitude)
  final String? cameraModel;      // EXIF Model
  final double? aperture;         // f-number; ej 1.8
  final String? exposureTime;     // ej "1/1000"
  final int? iso;                 // ej 200
  final double? focalLength;      // mm
  final String? exposureMode;     // "auto" | "manual" | otros
  final bool? flashUsed;          // true/false
  final String? orientation;      // "horizontal"|"vertical" o EXIF (1..8)

  // Sistema / archivo
  final String? originalFileName; // IMG_20230415_123456.jpg
  final String? originalFileId;   // id del SO / media store / asignado por app
  final String? sha256;           // hash del archivo para anti-duplicados
  final bool? edited;             // si la imagen fue editada
  final List<String>? editHistory;// ["crop","filter","enhance",...]

  // Enriquecimiento
  final String? address;          // dirección aproximada (reverse geocoding)

  // Metadatos IPTC/XMP crudos (opcional)
  final Map<String, dynamic>? iptc;
  final Map<String, dynamic>? xmp;

  // Resultados de análisis (IA o heurística local)
  final String? authenticity;     // MediaVerdict.{genuine|suspect|manipulated|unknown}
  final String? quality;          // MediaVerdict.{good|low|unusable}
  final double? confidence;       // 0..1
  final List<String>? flags;      // MediaFlags.*

  // Auditoría
  final DateTime? createdAt;
  final String? createdBy;

  PhotoMedia({
    this.id,
    required this.observacionId,
    this.photoId,
    required this.type,
    required this.source,
    required this.storagePath,
    this.url,
    this.thumbnailPath,
    this.width,
    this.height,
    this.fileSize,
    this.capturedAt,
    this.gpsLat,
    this.gpsLng,
    this.altitude,
    this.cameraModel,
    this.aperture,
    this.exposureTime,
    this.iso,
    this.focalLength,
    this.exposureMode,
    this.flashUsed,
    this.orientation,
    this.originalFileName,
    this.originalFileId,
    this.sha256,
    this.edited,
    this.editHistory,
    this.address,
    this.iptc,
    this.xmp,
    this.authenticity,
    this.quality,
    this.confidence,
    this.flags,
    this.createdAt,
    this.createdBy,
  });

  // ---------- Serialización ----------
  static DateTime? _dt(dynamic v) =>
      v is Timestamp ? v.toDate() : (v as DateTime?);
  static int? _i(dynamic v) => v is num ? v.toInt() : null;
  static double? _d(dynamic v) => v is num ? v.toDouble() : null;
  static List<String>? _strList(dynamic v) =>
      (v is List) ? v.whereType<String>().toList() : null;
  static Map<String, dynamic>? _map(dynamic v) =>
      (v is Map) ? v.cast<String, dynamic>() : null;

  Map<String, dynamic> toMap() => {
    'observacion_id': observacionId,
    if (photoId != null) 'photo_id': photoId,
    'type': type,
    'source': source,
    'storage_path': storagePath,
    if (url != null) 'url': url,
    if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (fileSize != null) 'file_size': fileSize,

    // EXIF / captura
    if (capturedAt != null) 'captured_at': capturedAt,
    if (gpsLat != null) 'gps_lat': gpsLat,
    if (gpsLng != null) 'gps_lng': gpsLng,
    if (altitude != null) 'altitude': altitude,
    if (cameraModel != null) 'camera_model': cameraModel,
    if (aperture != null) 'aperture': aperture,
    if (exposureTime != null) 'exposure_time': exposureTime,
    if (iso != null) 'iso': iso,
    if (focalLength != null) 'focal_length': focalLength,
    if (exposureMode != null) 'exposure_mode': exposureMode,
    if (flashUsed != null) 'flash_used': flashUsed,
    if (orientation != null) 'orientation': orientation,

    // Sistema / archivo
    if (originalFileName != null) 'original_file_name': originalFileName,
    if (originalFileId != null) 'original_file_id': originalFileId,
    if (sha256 != null) 'sha256': sha256,
    if (edited != null) 'edited': edited,
    if (editHistory != null) 'edit_history': editHistory,

    // Enriquecimiento
    if (address != null) 'address': address,

    // IPTC/XMP
    if (iptc != null) 'iptc': iptc,
    if (xmp != null) 'xmp': xmp,

    // Análisis
    if (authenticity != null) 'authenticity': authenticity,
    if (quality != null) 'quality': quality,
    if (confidence != null) 'confidence': confidence,
    if (flags != null) 'flags': flags,

    // Auditoría
    if (createdAt != null) 'createdAt': createdAt,
    if (createdBy != null) 'createdBy': createdBy,
  };

  factory PhotoMedia.fromMap(Map<String, dynamic> m, String id) => PhotoMedia(
    id: id,
    observacionId: (m['observacion_id'] ?? '') as String,
    photoId: m['photo_id'] as String?,
    type: (m['type'] ?? MediaType.photo) as String,
    source: (m['source'] ?? MediaSource.gallery) as String,
    storagePath: (m['storage_path'] ?? '') as String,
    url: m['url'] as String?,
    thumbnailPath: m['thumbnail_path'] as String?,
    width: _i(m['width']),
    height: _i(m['height']),
    fileSize: _i(m['file_size']),

    // EXIF / captura
    capturedAt: _dt(m['captured_at']),
    gpsLat: _d(m['gps_lat']),
    gpsLng: _d(m['gps_lng']),
    altitude: _d(m['altitude']),
    cameraModel: m['camera_model'] as String?,
    aperture: _d(m['aperture']),
    exposureTime: m['exposure_time'] as String?,
    iso: _i(m['iso']),
    focalLength: _d(m['focal_length']),
    exposureMode: m['exposure_mode'] as String?,
    flashUsed: m['flash_used'] as bool?,
    orientation: m['orientation'] as String?,

    // Sistema / archivo
    originalFileName: m['original_file_name'] as String?,
    originalFileId: m['original_file_id'] as String?,
    sha256: m['sha256'] as String?,
    edited: m['edited'] as bool?,
    editHistory: _strList(m['edit_history']),

    // Enriquecimiento
    address: m['address'] as String?,

    // IPTC/XMP
    iptc: _map(m['iptc']),
    xmp: _map(m['xmp']),

    // Análisis
    authenticity: m['authenticity'] as String?,
    quality: m['quality'] as String?,
    confidence: _d(m['confidence']),
    flags: _strList(m['flags']),

    // Auditoría (acepta createdAt o created_at)
    createdAt: _dt(m['createdAt']) ?? _dt(m['created_at']),
    createdBy: m['createdBy'] as String?,
  );

  factory PhotoMedia.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snap) =>
      PhotoMedia.fromMap(snap.data() ?? const {}, snap.id);

  PhotoMedia copyWith({
    String? id,
    String? observacionId,
    String? photoId,
    String? type,
    String? source,
    String? storagePath,
    String? url,
    String? thumbnailPath,
    int? width,
    int? height,
    int? fileSize,
    DateTime? capturedAt,
    double? gpsLat,
    double? gpsLng,
    double? altitude,
    String? cameraModel,
    double? aperture,
    String? exposureTime,
    int? iso,
    double? focalLength,
    String? exposureMode,
    bool? flashUsed,
    String? orientation,
    String? originalFileName,
    String? originalFileId,
    String? sha256,
    bool? edited,
    List<String>? editHistory,
    String? address,
    Map<String, dynamic>? iptc,
    Map<String, dynamic>? xmp,
    String? authenticity,
    String? quality,
    double? confidence,
    List<String>? flags,
    DateTime? createdAt,
    String? createdBy,
  }) {
    return PhotoMedia(
      id: id ?? this.id,
      observacionId: observacionId ?? this.observacionId,
      photoId: photoId ?? this.photoId,
      type: type ?? this.type,
      source: source ?? this.source,
      storagePath: storagePath ?? this.storagePath,
      url: url ?? this.url,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      width: width ?? this.width,
      height: height ?? this.height,
      fileSize: fileSize ?? this.fileSize,
      capturedAt: capturedAt ?? this.capturedAt,
      gpsLat: gpsLat ?? this.gpsLat,
      gpsLng: gpsLng ?? this.gpsLng,
      altitude: altitude ?? this.altitude,
      cameraModel: cameraModel ?? this.cameraModel,
      aperture: aperture ?? this.aperture,
      exposureTime: exposureTime ?? this.exposureTime,
      iso: iso ?? this.iso,
      focalLength: focalLength ?? this.focalLength,
      exposureMode: exposureMode ?? this.exposureMode,
      flashUsed: flashUsed ?? this.flashUsed,
      orientation: orientation ?? this.orientation,
      originalFileName: originalFileName ?? this.originalFileName,
      originalFileId: originalFileId ?? this.originalFileId,
      sha256: sha256 ?? this.sha256,
      edited: edited ?? this.edited,
      editHistory: editHistory ?? this.editHistory,
      address: address ?? this.address,
      iptc: iptc ?? this.iptc,
      xmp: xmp ?? this.xmp,
      authenticity: authenticity ?? this.authenticity,
      quality: quality ?? this.quality,
      confidence: confidence ?? this.confidence,
      flags: flags ?? this.flags,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  /// Helper para construir el ID humano de la foto.
  /// prog = consecutivo (>=1), date = fecha (se usa YY), initials = ej. "RMGU", project = "PI","RS","TF","EC","AC","OT"
  /// ej: buildPhotoId(1, 2025-03-10, "RMGU", "PI") => "00125_RMGU_PI"
  /// ej: buildPhotoId(1, 2025-03-10, "RMGU", "PI", extraIndex: 1) => "00125_RMGU_PI1"
  static String buildPhotoId({
    required int progressive,
    required DateTime date,
    required String initials,
    required String project,
    int? extraIndex,
  }) {
    final yy = (date.year % 100).toString().padLeft(2, '0');
    final prog = progressive.toString().padLeft(3, '0');
    final base = '${prog}${yy}_${initials.toUpperCase()}_${project.toUpperCase()}';
    if (extraIndex != null && extraIndex > 0) {
      return '$base${extraIndex}';
    }
    return base;
  }
}
