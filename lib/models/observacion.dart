// lib/models/observacion.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class EstadosObs {
  static const borrador  = 'borrador';
  static const pendiente = 'pendiente';
  static const aprobado  = 'aprobado';
  static const rechazado = 'rechazado';
  static const archivado = 'archivado';
}

/// Estado/condición del animal observado
class EstadosAnimal {
  static const vivo   = 'vivo';
  static const muerto = 'muerto';
  static const rastro = 'rastro'; // huellas, huesos, plumas, excretas, nido, etc.
}

/// Clasificación opcional del rastro (cuando condicion_animal == 'rastro')
class TiposRastro {
  static const huellas          = 'huellas';
  static const huesosParciales  = 'huesos_parciales';
  static const huesosCompletos  = 'huesos_completos';
  static const plumas           = 'plumas';
  static const excretas         = 'excretas';
  static const nido             = 'nido';
  static const madriguera       = 'madriguera';
  static const otros            = 'otros';
}

class AiSuggestion {
  final String nombre;
  final String? taxonId;
  final double? score;

  AiSuggestion({
    required this.nombre,
    this.taxonId,
    this.score,
  });

  Map<String, dynamic> toMap() => {
    'nombre': nombre,
    'taxonId': taxonId,
    'score': score,
  };

  factory AiSuggestion.fromMap(Map<String, dynamic> m) => AiSuggestion(
    nombre: (m['nombre'] ?? '') as String,
    taxonId: m['taxonId'] as String?,
    score: (m['score'] is num) ? (m['score'] as num).toDouble() : null,
  );
}

class Observacion {
  // Identidad
  final String? id;

  // Proyecto / Autor / Estado
  /// null => sin proyecto (permitido)
  final String? idProyecto;
  final String uidUsuario;
  final String estado;

  // Captura
  final DateTime? fechaCaptura;
  final int? edadAproximada;

  // Especie (libre + catalogada)
  final String? especieNombre; // texto libre
  final String? especieId;     // id del catálogo (opcional)

  // Ubicación / contexto
  final String? lugarNombre;
  final String? lugarTipo;
  final String? municipio;
  final String? estadoPais;
  final double? lat;
  final double? lng;
  final double? altitud;

  // Notas libres
  final String? notas;

  // ✨ NUEVO: estado/condición del animal y detalle de rastro
  /// EstadosAnimal.vivo | EstadosAnimal.muerto | EstadosAnimal.rastro
  final String? condicionAnimal;

  /// TiposRastro.* (solo aplica si condicionAnimal == 'rastro')
  final String? rastroTipo;

  /// Texto libre para detallar el rastro (p. ej., "huesos casi completos")
  final String? rastroDetalle;

  // IA (plan)
  final String? aiStatus;
  final List<AiSuggestion>? aiTopSuggestions;
  final String? aiModel;
  final String? aiError;

  // Auditoría (creación/actualización)
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? updatedAt;
  final String? updatedBy;
  final DateTime? ultimaModificacion;

  // Revisión (envío y validación)
  final DateTime? submittedAt;
  final String? submittedBy;
  /// 'recolector' | 'colaborador' | 'supervisor' | 'owner' | 'admin'
  final String? authorRoleAtSubmission;

  final DateTime? validatedAt;
  final String? validatedBy;
  /// rol del revisor al validar (p.ej. 'supervisor'/'owner'/'admin')
  final String? validatedByRol;
  final String? rejectionReason;
  final bool? conflictOfInterest;

  // Denormalizaciones / utilidades
  final int? mediaCount;
  final String? capturaKey; // para anti-duplicados entre proyectos

  Observacion({
    this.id,
    required this.uidUsuario,
    required this.estado,
    this.idProyecto,
    this.fechaCaptura,
    this.edadAproximada,
    this.especieNombre,
    this.especieId,
    this.lugarNombre,
    this.lugarTipo,
    this.municipio,
    this.estadoPais,
    this.lat,
    this.lng,
    this.altitud,
    this.notas,
    // nuevos
    this.condicionAnimal,
    this.rastroTipo,
    this.rastroDetalle,
    // IA
    this.aiStatus,
    this.aiTopSuggestions,
    this.aiModel,
    this.aiError,
    // auditoría/envío/validación
    this.createdAt,
    this.createdBy,
    this.updatedAt,
    this.updatedBy,
    this.ultimaModificacion,
    this.submittedAt,
    this.submittedBy,
    this.authorRoleAtSubmission,
    this.validatedAt,
    this.validatedBy,
    this.validatedByRol,
    this.rejectionReason,
    this.conflictOfInterest,
    // denormalizados
    this.mediaCount,
    this.capturaKey,
  });

  // ---------- Aliases de compatibilidad para UI vieja ----------
  String? get nombreLugar   => lugarNombre;
  String? get tipoLugar     => lugarTipo;
  double? get latitud       => lat;
  double? get longitud      => lng;
  String? get observaciones => notas;

  // ---------- Serialización ----------
  Map<String, dynamic> toMap() => {
    'id_proyecto': idProyecto,
    'uid_usuario': uidUsuario,
    'estado': estado,
    'fecha_captura': fechaCaptura,
    'edad_aproximada': edadAproximada,
    'especie_nombre': especieNombre,
    'especie_id': especieId,
    'lugar_nombre': lugarNombre,
    'lugar_tipo': lugarTipo,
    'municipio': municipio,
    'estado_pais': estadoPais,
    'lat': lat,
    'lng': lng,
    'altitud': altitud,
    'notas': notas,
    // nuevos
    'condicion_animal': condicionAnimal,
    'rastro_tipo': rastroTipo,
    'rastro_detalle': rastroDetalle,
    // IA
    'ai_status': aiStatus,
    'ai_top_suggestions': aiTopSuggestions?.map((e) => e.toMap()).toList(),
    'ai_model': aiModel,
    'ai_error': aiError,
    // auditoría/envío/validación (los serverTimestamp los pone el service)
    'createdAt': createdAt,
    'createdBy': createdBy,
    'updatedAt': updatedAt,
    'updatedBy': updatedBy,
    'ultima_modificacion': ultimaModificacion,
    'submittedAt': submittedAt,
    'submittedBy': submittedBy,
    'authorRoleAtSubmission': authorRoleAtSubmission,
    'validatedAt': validatedAt,
    'validatedBy': validatedBy,
    'validatedByRol': validatedByRol,
    'rejectionReason': rejectionReason,
    'conflictOfInterest': conflictOfInterest,
    // denormalizados
    'media_count': mediaCount,
    'captura_key': capturaKey,
  };

  static DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return v is DateTime ? v : null;
  }

  static int? _toInt(dynamic v) => (v is num) ? v.toInt() : null;
  static double? _toDouble(dynamic v) => (v is num) ? v.toDouble() : null;

  factory Observacion.fromMap(Map<String, dynamic> m, String id) {
    return Observacion(
      id: id,
      idProyecto: m['id_proyecto'] as String?, // puede ser null
      uidUsuario: (m['uid_usuario'] ?? '') as String,
      estado: ((m['estado'] ?? EstadosObs.borrador) as String).toLowerCase(),
      fechaCaptura: _toDate(m['fecha_captura']),
      edadAproximada: _toInt(m['edad_aproximada']),
      especieNombre: m['especie_nombre'] as String?,
      especieId: m['especie_id'] as String?,
      lugarNombre: m['lugar_nombre'] as String?,
      lugarTipo: m['lugar_tipo'] as String?,
      municipio: m['municipio'] as String?,
      estadoPais: m['estado_pais'] as String?,
      lat: _toDouble(m['lat']),
      lng: _toDouble(m['lng']),
      altitud: _toDouble(m['altitud']),
      notas: m['notas'] as String?,
      // nuevos
      condicionAnimal: m['condicion_animal'] as String?,
      rastroTipo: m['rastro_tipo'] as String?,
      rastroDetalle: m['rastro_detalle'] as String?,
      // IA
      aiStatus: m['ai_status'] as String?,
      aiTopSuggestions: (m['ai_top_suggestions'] is List)
          ? (m['ai_top_suggestions'] as List)
          .whereType<Map<String, dynamic>>()
          .map(AiSuggestion.fromMap)
          .toList()
          : null,
      aiModel: m['ai_model'] as String?,
      aiError: m['ai_error'] as String?,
      // auditoría/envío/validación
      createdAt: _toDate(m['createdAt']),
      createdBy: m['createdBy'] as String?,
      updatedAt: _toDate(m['updatedAt']),
      updatedBy: m['updatedBy'] as String?,
      ultimaModificacion: _toDate(m['ultima_modificacion']),
      submittedAt: _toDate(m['submittedAt']),
      submittedBy: m['submittedBy'] as String?,
      authorRoleAtSubmission: m['authorRoleAtSubmission'] as String?,
      validatedAt: _toDate(m['validatedAt']),
      validatedBy: m['validatedBy'] as String?,
      validatedByRol: m['validatedByRol'] as String?,
      rejectionReason: m['rejectionReason'] as String?,
      conflictOfInterest: m['conflictOfInterest'] as bool?,
      // denormalizados
      mediaCount: _toInt(m['media_count']),
      capturaKey: m['captura_key'] as String?,
    );
  }

  factory Observacion.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snap,
      ) =>
      Observacion.fromMap(snap.data() ?? const {}, snap.id);

  Observacion copyWith({
    String? id,
    String? idProyecto,
    String? uidUsuario,
    String? estado,
    DateTime? fechaCaptura,
    int? edadAproximada,
    String? especieNombre,
    String? especieId,
    String? lugarNombre,
    String? lugarTipo,
    String? municipio,
    String? estadoPais,
    double? lat,
    double? lng,
    double? altitud,
    String? notas,
    // nuevos
    String? condicionAnimal,
    String? rastroTipo,
    String? rastroDetalle,
    // IA
    String? aiStatus,
    List<AiSuggestion>? aiTopSuggestions,
    String? aiModel,
    String? aiError,
    // auditoría/envío/validación
    DateTime? createdAt,
    String? createdBy,
    DateTime? updatedAt,
    String? updatedBy,
    DateTime? ultimaModificacion,
    DateTime? submittedAt,
    String? submittedBy,
    String? authorRoleAtSubmission,
    DateTime? validatedAt,
    String? validatedBy,
    String? validatedByRol,
    String? rejectionReason,
    bool? conflictOfInterest,
    // denormalizados
    int? mediaCount,
    String? capturaKey,
  }) {
    return Observacion(
      id: id ?? this.id,
      idProyecto: idProyecto ?? this.idProyecto,
      uidUsuario: uidUsuario ?? this.uidUsuario,
      estado: estado ?? this.estado,
      fechaCaptura: fechaCaptura ?? this.fechaCaptura,
      edadAproximada: edadAproximada ?? this.edadAproximada,
      especieNombre: especieNombre ?? this.especieNombre,
      especieId: especieId ?? this.especieId,
      lugarNombre: lugarNombre ?? this.lugarNombre,
      lugarTipo: lugarTipo ?? this.lugarTipo,
      municipio: municipio ?? this.municipio,
      estadoPais: estadoPais ?? this.estadoPais,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      altitud: altitud ?? this.altitud,
      notas: notas ?? this.notas,
      // nuevos
      condicionAnimal: condicionAnimal ?? this.condicionAnimal,
      rastroTipo: rastroTipo ?? this.rastroTipo,
      rastroDetalle: rastroDetalle ?? this.rastroDetalle,
      // IA
      aiStatus: aiStatus ?? this.aiStatus,
      aiTopSuggestions: aiTopSuggestions ?? this.aiTopSuggestions,
      aiModel: aiModel ?? this.aiModel,
      aiError: aiError ?? this.aiError,
      // auditoría/envío/validación
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      ultimaModificacion: ultimaModificacion ?? this.ultimaModificacion,
      submittedAt: submittedAt ?? this.submittedAt,
      submittedBy: submittedBy ?? this.submittedBy,
      authorRoleAtSubmission:
      authorRoleAtSubmission ?? this.authorRoleAtSubmission,
      validatedAt: validatedAt ?? this.validatedAt,
      validatedBy: validatedBy ?? this.validatedBy,
      validatedByRol: validatedByRol ?? this.validatedByRol,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      conflictOfInterest: conflictOfInterest ?? this.conflictOfInterest,
      // denormalizados
      mediaCount: mediaCount ?? this.mediaCount,
      capturaKey: capturaKey ?? this.capturaKey,
    );
  }
}

