import 'package:cloud_firestore/cloud_firestore.dart';

/// =========================
/// Estados y catálogos
/// =========================
class EstadosObs {
  static const borrador     = 'borrador';
  static const pendiente    = 'pendiente';
  static const revisarNuevo = 'revisar_nuevo';
  static const aprobado     = 'aprobado';
  static const rechazado    = 'rechazado';
  static const archivado    = 'archivado';

  /// Guardada solo en el dispositivo
  static const localDraft   = 'local_draft';

  static String normalize(String? v) {
    final s = (v ?? borrador).trim().toLowerCase();
    switch (s) {
      case borrador:
      case pendiente:
      case revisarNuevo:
      case aprobado:
      case rechazado:
      case archivado:
      case localDraft:
        return s;
      default:
        return borrador;
    }
  }
}

class EstadosAnimal {
  static const vivo   = 'vivo';
  static const muerto = 'muerto';
  static const rastro = 'rastro';
}

class TiposRastro {
  static const huellas         = 'huellas';
  static const huesosParciales = 'huesos_parciales';
  static const huesosCompletos = 'huesos_completos';
  static const plumas          = 'plumas';
  static const excretas        = 'excretas';
  static const nido            = 'nido';
  static const madriguera      = 'madriguera';
  static const otros           = 'otros';
}

class AiSuggestion {
  final String nombre;
  final String? taxonId;
  final double? score;

  AiSuggestion({required this.nombre, this.taxonId, this.score});

  Map<String, dynamic> toMap() => {
    'nombre': nombre,
    if (taxonId != null) 'taxonId': taxonId,
    if (score != null) 'score': score,
  };

  factory AiSuggestion.fromMap(Map m) => AiSuggestion(
    nombre: (m['nombre'] ?? '').toString(),
    taxonId: (m['taxonId'] as String?)?.trim(),
    score: (m['score'] is num)
        ? (m['score'] as num).toDouble()
        : double.tryParse(m['score']?.toString() ?? ''),
  );
}

/// ==========================================================
///                       OBSERVACION
/// ==========================================================
class Observacion {
  // Identidad
  final String? id;

  // Proyecto / Autor / Estado
  final String? idProyecto;
  final String uidUsuario;
  final String estado;

  /// Rol con el que se capturó / creó la observación
  /// (p.ej. 'RECOLECTOR', 'DUENO_PROYECTO', etc.)
  final String? ctxRol;

  // Categoría (FK)
  final int? idCategoria;

  // Captura
  final DateTime? fechaCaptura;
  final int? edadAproximada; // años o unidad acordada

  // Especie
  final String? especieNombreCientifico;
  final String? especieNombreComun;
  final String? especieId;
  final bool? especieFueraCatalogo;
  final String? especieSlug;

  // Lugar / contexto
  final String? lugarNombre;
  final String? lugarTipo;
  final String? municipio; // display corto
  final String? municipioDisplay; // espejo para UI
  final String? estadoPais; // compat legacy (UPPER)

  // Geo
  final double? lat;
  final double? lng;
  final double? altitud;

  // Notas
  final String? notas;

  // Condición / rastro
  final String? condicionAnimal;
  final String? rastroTipo;
  final String? rastroDetalle;

  // Taxonomía auto (UI / catálogo)
  final String? taxoClase;
  final String? taxoOrden;
  final String? taxoFamilia;

  // Ubicación canónica derivada del municipio (auto)
  final String? ubicEstado;
  final String? ubicRegion;
  final String? ubicDistrito;

  // IA
  final String? aiStatus;
  final List<AiSuggestion>? aiTopSuggestions;
  final String? aiModel;
  final String? aiError;

  // Auditoría
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? updatedAt;
  final String? updatedBy;
  final DateTime? ultimaModificacion;

  // Revisión
  final DateTime? submittedAt;
  final String? submittedBy;
  final String? authorRoleAtSubmission;
  final DateTime? validatedAt; // aprobado/rechazado
  final String? validatedBy;
  final String? validatedByRol;
  final String? rejectionReason;
  final bool? conflictOfInterest;

  // Media
  final String? coverUrl;
  final String? primaryMediaId;

  // Denormalizaciones / utilidades
  final int? mediaCount;
  final String? capturaKey;

  // Denormalizados UI
  final String? autorNombre;
  final String? proyectoNombre;
  final String? categoriaNombre;

  // Identificador principal (humano)
  final String? identificadorUid;
  final String? identificadorNombre;

  // Listas de media
  final List<String> mediaUrls;
  final List<String> mediaStoragePaths;

  // Control de rondas de revisión
  final int? reviewRound; // 1=primera, 2=reenviada, ...
  final bool? wasRejected; // si viene de un rechazo anterior
  final DateTime? firstSubmittedAt;
  final DateTime? lastSubmittedAt;

  Observacion({
    this.id,
    required this.uidUsuario,
    required this.estado,
    this.idProyecto,
    this.ctxRol,
    this.idCategoria,
    this.fechaCaptura,
    this.edadAproximada,
    this.especieNombreCientifico,
    this.especieNombreComun,
    this.especieId,
    this.especieFueraCatalogo,
    this.especieSlug,
    this.lugarNombre,
    this.lugarTipo,
    this.municipio,
    this.municipioDisplay,
    this.estadoPais,
    this.lat,
    this.lng,
    this.altitud,
    this.notas,
    this.condicionAnimal,
    this.rastroTipo,
    this.rastroDetalle,
    this.taxoClase,
    this.taxoOrden,
    this.taxoFamilia,
    this.ubicEstado,
    this.ubicRegion,
    this.ubicDistrito,
    this.aiStatus,
    this.aiTopSuggestions,
    this.aiModel,
    this.aiError,
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
    this.coverUrl,
    this.primaryMediaId,
    this.mediaCount,
    this.capturaKey,
    this.autorNombre,
    this.proyectoNombre,
    this.categoriaNombre,
    this.identificadorUid,
    this.identificadorNombre,
    List<String>? mediaUrls,
    List<String>? mediaStoragePaths,
    this.reviewRound,
    this.wasRejected,
    this.firstSubmittedAt,
    this.lastSubmittedAt,
  })  : mediaUrls = _cleanStringList(mediaUrls),
        mediaStoragePaths = _cleanStringList(mediaStoragePaths);

  // ---------------------- Helpers de parseo ----------------------
  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static bool? _toBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().toLowerCase().trim();
    if (s == 'true') return true;
    if (s == 'false') return false;
    return null;
  }

  static List<String> _cleanStringList(List<String>? v) {
    final raw = v ?? const <String>[];
    final out = <String>{};
    for (final e in raw) {
      final s = (e).toString().trim();
      if (s.isNotEmpty) out.add(s);
    }
    return out.toList(growable: false);
  }

  static List<String> _toStringList(dynamic v) {
    if (v is List) {
      return _cleanStringList(v.map((e) => e?.toString() ?? '').toList());
    }
    return const <String>[];
  }

  static String? _toTrimmedString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  // ==========================================================
  //              SERIALIZACIÓN (ONLINE)
  // ==========================================================
  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'id_proyecto': idProyecto,
      'uid_usuario': uidUsuario,
      'estado': EstadosObs.normalize(estado),
      'ctx_rol': _toTrimmedString(ctxRol),

      if (idCategoria != null) 'id_categoria': idCategoria,
      'fecha_captura': fechaCaptura,
      'edad_aproximada': edadAproximada,

      // especie
      'especie_nombre_cientifico': _toTrimmedString(especieNombreCientifico),
      'especie_nombre_comun': _toTrimmedString(especieNombreComun),
      'especie_id': _toTrimmedString(especieId),
      if (especieFueraCatalogo != null)
        'especie_fuera_catalogo': especieFueraCatalogo,
      if (especieSlug != null) 'especie_slug': especieSlug,

      // lugar
      'lugar_nombre': _toTrimmedString(lugarNombre),
      'lugar_tipo': _toTrimmedString(lugarTipo),

      // municipio enriquecido
      'municipio': _toTrimmedString(municipio),
      'municipio_display': _toTrimmedString(municipioDisplay),
      'estado_pais': _toTrimmedString(estadoPais),

      // geo
      'lat': lat,
      'lng': lng,
      'altitud': altitud,

      // otros
      'notas': _toTrimmedString(notas),
      'condicion_animal': _toTrimmedString(condicionAnimal),
      'rastro_tipo': _toTrimmedString(rastroTipo),
      'rastro_detalle': _toTrimmedString(rastroDetalle),

      // taxo
      'taxo_clase': _toTrimmedString(taxoClase),
      'taxo_orden': _toTrimmedString(taxoOrden),
      'taxo_familia': _toTrimmedString(taxoFamilia),

      // ubic
      'ubic_estado': _toTrimmedString(ubicEstado),
      'ubic_region': _toTrimmedString(ubicRegion),
      'ubic_distrito': _toTrimmedString(ubicDistrito),

      // IA
      'ai_status': _toTrimmedString(aiStatus),
      if (aiTopSuggestions != null)
        'ai_top_suggestions': aiTopSuggestions!.map((e) => e.toMap()).toList(),
      'ai_model': _toTrimmedString(aiModel),
      'ai_error': _toTrimmedString(aiError),

      // auditoría
      'createdAt': createdAt,
      'createdBy': _toTrimmedString(createdBy),
      'updatedAt': updatedAt,
      'updatedBy': _toTrimmedString(updatedBy),
      'ultima_modificacion': ultimaModificacion,

      // revisión
      'submittedAt': submittedAt,
      'submittedBy': _toTrimmedString(submittedBy),
      'authorRoleAtSubmission': _toTrimmedString(authorRoleAtSubmission),
      'validatedAt': validatedAt,
      'validatedBy': _toTrimmedString(validatedBy),
      'validatedByRol': _toTrimmedString(validatedByRol),
      'rejectionReason': _toTrimmedString(rejectionReason),
      'conflictOfInterest': conflictOfInterest,

      // media
      'cover_url': _toTrimmedString(coverUrl),
      'primary_media_id': _toTrimmedString(primaryMediaId),
      'media_count': mediaCount,
      'captura_key': _toTrimmedString(capturaKey),

      // denorm UI
      'autor_nombre': _toTrimmedString(autorNombre),
      'proyecto_nombre': _toTrimmedString(proyectoNombre),
      'categoria_nombre': _toTrimmedString(categoriaNombre),

      // identificador humano
      'identificador_uid': _toTrimmedString(identificadorUid),
      'identificador_nombre': _toTrimmedString(identificadorNombre),

      // listas
      if (mediaUrls.isNotEmpty) 'media_urls': mediaUrls,
      if (mediaStoragePaths.isNotEmpty) 'media_storage_paths': mediaStoragePaths,

      // rondas
      if (reviewRound != null) 'review_round': reviewRound,
      if (wasRejected != null) 'was_rejected': wasRejected,
      'firstSubmittedAt': firstSubmittedAt,
      'lastSubmittedAt': lastSubmittedAt,
    };

    // limpia nulos / vacíos
    m.removeWhere((k, v) {
      if (v == null) return true;
      if (v is String && v.trim().isEmpty) return true;
      if (v is List && v.isEmpty) return true;
      return false;
    });
    return m;
  }

  factory Observacion.fromMap(Map<String, dynamic> m, String id) {
    // compat de portada
    final _coverUrl = (m['cover_url'] ?? m['imagenUrl'] ?? m['imageUrl']);

    // AI suggestions robusto
    List<AiSuggestion>? _aiSug;
    final rawAi = m['ai_top_suggestions'];
    if (rawAi is List) {
      _aiSug = rawAi
          .where((e) => e is Map)
          .map((e) => AiSuggestion.fromMap(e as Map))
          .toList();
      if (_aiSug.isEmpty) _aiSug = null;
    }

    // edad: acepta edad_aproximada | edad | edad_ejemplar
    final _edad = m.containsKey('edad_aproximada')
        ? m['edad_aproximada']
        : (m.containsKey('edad') ? m['edad'] : m['edad_ejemplar']);

    return Observacion(
      id: id,
      idProyecto: _toTrimmedString(m['id_proyecto']),
      uidUsuario: _toTrimmedString(m['uid_usuario']) ?? '',
      estado: EstadosObs.normalize(m['estado']),
      ctxRol: _toTrimmedString(m['ctx_rol'] ?? m['ctxRol']),

      idCategoria: _toInt(m['id_categoria']),

      fechaCaptura: _toDate(m['fecha_captura']),
      edadAproximada: _toInt(_edad),

      // especie
      especieNombreCientifico:
      _toTrimmedString(m['especie_nombre_cientifico'] ?? m['especie_nombre']),
      especieNombreComun: _toTrimmedString(m['especie_nombre_comun']),
      especieId: _toTrimmedString(m['especie_id']),
      especieFueraCatalogo: _toBool(m['especie_fuera_catalogo']),
      especieSlug: _toTrimmedString(m['especie_slug']),

      // lugar
      lugarNombre: _toTrimmedString(m['lugar_nombre']),
      lugarTipo: _toTrimmedString(m['lugar_tipo']),

      // municipio enriquecido
      municipio: _toTrimmedString(m['municipio']),
      municipioDisplay: _toTrimmedString(m['municipio_display']),
      estadoPais: _toTrimmedString(m['estado_pais']),

      // geo
      lat: _toDouble(m['lat'] ?? m['gps_lat']),
      lng: _toDouble(m['lng'] ?? m['gps_lng']),
      altitud: _toDouble(m['altitud'] ?? m['gps_alt_m']),

      // otros
      notas: _toTrimmedString(m['notas']),
      condicionAnimal: _toTrimmedString(m['condicion_animal']),
      rastroTipo: _toTrimmedString(m['rastro_tipo']),
      rastroDetalle: _toTrimmedString(m['rastro_detalle']),

      // taxo
      taxoClase: _toTrimmedString(m['taxo_clase']),
      taxoOrden: _toTrimmedString(m['taxo_orden']),
      taxoFamilia: _toTrimmedString(m['taxo_familia']),

      // ubic
      ubicEstado: _toTrimmedString(m['ubic_estado']),
      ubicRegion: _toTrimmedString(m['ubic_region']),
      ubicDistrito: _toTrimmedString(m['ubic_distrito']),

      // IA
      aiStatus: _toTrimmedString(m['ai_status']),
      aiTopSuggestions: _aiSug,
      aiModel: _toTrimmedString(m['ai_model']),
      aiError: _toTrimmedString(m['ai_error']),

      // auditoría
      createdAt: _toDate(m['createdAt']),
      createdBy: _toTrimmedString(m['createdBy']),
      updatedAt: _toDate(m['updatedAt']),
      updatedBy: _toTrimmedString(m['updatedBy']),
      ultimaModificacion: _toDate(m['ultima_modificacion']),

      // revisión
      submittedAt: _toDate(m['submittedAt']),
      submittedBy: _toTrimmedString(m['submittedBy']),
      authorRoleAtSubmission:
      _toTrimmedString(m['authorRoleAtSubmission']),
      validatedAt: _toDate(m['validatedAt']),
      validatedBy: _toTrimmedString(m['validatedBy']),
      validatedByRol: _toTrimmedString(m['validatedByRol']),
      rejectionReason: _toTrimmedString(m['rejectionReason']),
      conflictOfInterest: _toBool(m['conflictOfInterest']),

      // media
      coverUrl: _toTrimmedString(_coverUrl),
      primaryMediaId: _toTrimmedString(m['primary_media_id']),
      mediaCount: _toInt(m['media_count']),
      capturaKey: _toTrimmedString(m['captura_key']),

      // denorm UI
      autorNombre: _toTrimmedString(m['autor_nombre']),
      proyectoNombre: _toTrimmedString(m['proyecto_nombre']),
      categoriaNombre: _toTrimmedString(m['categoria_nombre']),

      // identificadores
      identificadorUid: _toTrimmedString(m['identificador_uid']),
      identificadorNombre: _toTrimmedString(m['identificador_nombre']),

      // listas (acepta media_urls o legacy 'fotos')
      mediaUrls: _toStringList(m['media_urls'] ?? m['fotos']),
      mediaStoragePaths: _toStringList(m['media_storage_paths']),

      // rondas
      reviewRound: _toInt(m['review_round']),
      wasRejected: _toBool(m['was_rejected']),
      firstSubmittedAt: _toDate(m['firstSubmittedAt']),
      lastSubmittedAt: _toDate(m['lastSubmittedAt']),
    );
  }

  /// Factory para draft local (almacenamiento en dispositivo)
  factory Observacion.emptyLocalDraft({
    required String uidUsuario,
    String? idProyecto,
    String? ctxRol,
  }) {
    final now = DateTime.now();
    return Observacion(
      id: null,
      uidUsuario: uidUsuario,
      estado: EstadosObs.localDraft,
      idProyecto: idProyecto,
      ctxRol: ctxRol,
      createdAt: now,
      updatedAt: now,
      ultimaModificacion: now,
      mediaUrls: const [],
      mediaStoragePaths: const [],
    );
  }

  /// --------- Factories auxiliares ----------
  factory Observacion.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snap,
      ) =>
      Observacion.fromMap(snap.data() ?? const {}, snap.id);

  // ---------------------- Helpers de dominio ----------------------
  bool get isBorrador => estado == EstadosObs.borrador;
  bool get isPendiente =>
      estado == EstadosObs.pendiente || estado == EstadosObs.revisarNuevo;
  bool get isAprobado => estado == EstadosObs.aprobado;
  bool get isRechazado => estado == EstadosObs.rechazado;
  bool get isArchivado => estado == EstadosObs.archivado;
  bool get isLocalDraft => estado == EstadosObs.localDraft;

  bool get hasGeo => lat != null && lng != null;
  bool get hasFecha => fechaCaptura != null;
  bool get hasFoto => mediaUrls.isNotEmpty;

  /// ¿Esta observación es visible para el rol actual?
  /// - Si `rolCodigo` es null → visible.
  /// - Si `ctxRol` es null (legacy) → visible.
  /// - En otro caso, solo si coincide.
  bool matchesCtxRol(String? rolCodigo) {
    if (rolCodigo == null) return true;
    if (ctxRol == null) return true; // compat con datos antiguos
    return ctxRol == rolCodigo;
  }

  /// Condición necesaria para mandar a pendiente (en nube), modo simple
  bool get datosCompletos => hasFecha && hasGeo && hasFoto;

  /// Útil para “reenviar a revisión” tras rechazo
  bool get wasEditedAfterRejection {
    if (!isRechazado) return false;
    if (validatedAt == null) return false;
    if (updatedAt == null) return false;
    return updatedAt!.isAfter(validatedAt!);
  }

  // ------ Getters de presentación ------
  String get displayNombreComun =>
      (especieNombreComun ?? '').trim().isNotEmpty
          ? especieNombreComun!.trim()
          : 'Sin nombre común';

  String get displayNombreCientifico =>
      (especieNombreCientifico ?? '').trim().isNotEmpty
          ? especieNombreCientifico!.trim()
          : (especieSlug ?? especieId ?? 'Sin especie');

  /// Ej: "Murciélago cola de perro — *Saccopteryx canina*"
  String get displayEspecieFull {
    final comun = (especieNombreComun ?? '').trim();
    final cient = displayNombreCientifico;
    if (comun.isEmpty || comun == 'Sin nombre común') return cient;
    return '$comun — $cient';
  }

  String get displayMunicipio =>
      (municipioDisplay ?? municipio ?? '').trim().isNotEmpty
          ? (municipioDisplay ?? municipio)!.trim()
          : 'Sin municipio';

  /// "Salina Cruz, Oaxaca" o "Oaxaca" o "—"
  String get displayUbicacionCorta {
    final muni = (municipioDisplay ?? municipio)?.trim();
    final edo = (estadoPais)?.trim();
    final partes = <String>[];
    if (muni != null && muni.isNotEmpty) partes.add(muni);
    if (edo != null && edo.isNotEmpty) partes.add(edo);
    return partes.isEmpty ? '—' : partes.join(', ');
  }

  /// "Región Istmo · Distrito Tehuantepec · Oaxaca"
  String get displayUbicacionCanonica {
    final p = <String>[];
    if ((ubicRegion ?? '').trim().isNotEmpty) p.add(ubicRegion!.trim());
    if ((ubicDistrito ?? '').trim().isNotEmpty) p.add(ubicDistrito!.trim());
    if ((ubicEstado ?? '').trim().isNotEmpty) p.add(ubicEstado!.trim());
    return p.isEmpty ? '—' : p.join(' · ');
  }

  /// Coordenadas "17.009553, -96.757147"
  String get displayCoords =>
      (lat != null && lng != null)
          ? '${lat!.toStringAsFixed(6)}, ${lng!.toStringAsFixed(6)}'
          : '—';

  /// Categoría visual: "Ecología II" o "#2" o "—"
  String get displayCategoria {
    if ((categoriaNombre ?? '').trim().isNotEmpty) {
      return categoriaNombre!.trim();
    }
    if (idCategoria != null) return '#$idCategoria';
    return '—';
  }

  /// Edad formateada para UI
  String get displayEdadAprox =>
      (edadAproximada == null) ? '—' : '$edadAproximada';

  /// Lugar formateado para UI
  String get displayLugar {
    final tipo = (lugarTipo ?? '').trim();
    final nom = (lugarNombre ?? '').trim();
    if (tipo.isEmpty && nom.isEmpty) return '—';
    if (tipo.isNotEmpty && nom.isNotEmpty) return '$tipo · $nom';
    return tipo.isNotEmpty ? tipo : nom;
  }

  /// Datos que faltan para cumplir mínimos
  List<String> get faltantesMinimos {
    final faltan = <String>[];
    if (!hasFecha) faltan.add('fecha_captura');
    if (!hasGeo) faltan.add('lat/lng');
    if (!hasFoto) faltan.add('media_urls');
    return faltan;
  }

  /// =========================
  ///  Reglas para ENVIAR A REVISIÓN
  /// =========================
  ///
  /// Devuelve una lista de "códigos" de campos faltantes:
  ///  - 'foto'            → falta al menos 1 foto
  ///  - 'fotos_exceso'    → excede el máximo permitido
  ///  - 'fecha_captura'   → falta fecha/hora
  ///  - 'lugar_tipo'      → falta tipo de lugar
  ///  - 'lugar_municipio' → falta nombre de lugar o municipio
  ///  - 'coords'          → faltan lat/lng
  ///  - 'condicion'       → condición inválida / no seleccionada
  ///  - 'rastro_detalle'  → si es rastro y falta tipo/detalle
  List<String> faltantesParaRevision({
    required int fotosCount,
    int maxFotos = 4,
  }) {
    final falt = <String>[];

    // Fotos
    if (fotosCount <= 0) {
      falt.add('foto');
    } else if (fotosCount > maxFotos) {
      falt.add('fotos_exceso');
    }

    // Fecha
    if (!hasFecha) {
      falt.add('fecha_captura');
    }

    // Tipo de lugar
    if ((lugarTipo ?? '').trim().isEmpty) {
      falt.add('lugar_tipo');
    }

    // Nombre de lugar o municipio/display
    final muniDisplay = (municipioDisplay ?? municipio ?? '').trim();
    final lugarNom = (lugarNombre ?? '').trim();
    final tieneLugarOMuni = muniDisplay.isNotEmpty || lugarNom.isNotEmpty;
    if (!tieneLugarOMuni) {
      falt.add('lugar_municipio');
    }

    // Coordenadas
    if (!hasGeo) {
      falt.add('coords');
    }

    // Condición
    final cond = (condicionAnimal ?? '').trim();
    final condValida = {
      EstadosAnimal.vivo,
      EstadosAnimal.muerto,
      EstadosAnimal.rastro,
    }.contains(cond);
    if (!condValida) {
      falt.add('condicion');
    }

    // Rastro: tipo o detalle obligatorio
    if (cond == EstadosAnimal.rastro) {
      final hasTipo = (rastroTipo ?? '').trim().isNotEmpty;
      final hasDetalle = (rastroDetalle ?? '').trim().isNotEmpty;
      if (!hasTipo && !hasDetalle) {
        falt.add('rastro_detalle');
      }
    }

    return falt;
  }

  /// Atajo: ¿cumple todo para revisión, dado un número de fotos?
  bool cumpleRequisitosRevision({
    required int fotosCount,
    int maxFotos = 4,
  }) {
    return faltantesParaRevision(
      fotosCount: fotosCount,
      maxFotos: maxFotos,
    ).isEmpty;
  }

  // ------ Labels de estado / condición / rastro ------
  String get estadoLabel {
    switch (estado) {
      case EstadosObs.borrador:
        return 'Borrador';
      case EstadosObs.pendiente:
        return 'Pendiente';
      case EstadosObs.revisarNuevo:
        return 'Revisar (nuevo envío)';
      case EstadosObs.aprobado:
        return 'Aprobado';
      case EstadosObs.rechazado:
        return 'Rechazado';
      case EstadosObs.archivado:
        return 'Archivado';
      case EstadosObs.localDraft:
        return 'Borrador local';
      default:
        return 'N/D';
    }
  }

  String get displayCondicion {
    final s = (condicionAnimal ?? '').trim().toLowerCase();
    switch (s) {
      case EstadosAnimal.vivo:
        return 'Vivo';
      case EstadosAnimal.muerto:
        return 'Muerto';
      case EstadosAnimal.rastro:
        return 'Rastro';
      default:
        return 'N/D';
    }
  }

  String get displayRastro {
    final s = (rastroTipo ?? '').trim().toLowerCase();
    switch (s) {
      case TiposRastro.huellas:
        return 'Huellas';
      case TiposRastro.huesosParciales:
        return 'Huesos parciales';
      case TiposRastro.huesosCompletos:
        return 'Huesos casi completos';
      case TiposRastro.plumas:
        return 'Plumas';
      case TiposRastro.excretas:
        return 'Excretas';
      case TiposRastro.nido:
        return 'Nido';
      case TiposRastro.madriguera:
        return 'Madriguera';
      case TiposRastro.otros:
        return 'Otros';
      default:
        return '—';
    }
  }

  // ---------------------- copyWith ----------------------
  Observacion copyWith({
    String? id,
    String? idProyecto,
    String? uidUsuario,
    String? estado,
    String? ctxRol,
    int? idCategoria,
    DateTime? fechaCaptura,
    int? edadAproximada,
    String? especieNombreCientifico,
    String? especieNombreComun,
    String? especieId,
    bool? especieFueraCatalogo,
    String? especieSlug,
    String? lugarNombre,
    String? lugarTipo,
    String? municipio,
    String? municipioDisplay,
    String? estadoPais,
    double? lat,
    double? lng,
    double? altitud,
    String? notas,
    String? condicionAnimal,
    String? rastroTipo,
    String? rastroDetalle,
    String? taxoClase,
    String? taxoOrden,
    String? taxoFamilia,
    String? ubicEstado,
    String? ubicRegion,
    String? ubicDistrito,
    String? aiStatus,
    List<AiSuggestion>? aiTopSuggestions,
    String? aiModel,
    String? aiError,
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
    String? coverUrl,
    String? primaryMediaId,
    int? mediaCount,
    String? capturaKey,
    String? autorNombre,
    String? proyectoNombre,
    String? categoriaNombre,
    String? identificadorUid,
    String? identificadorNombre,
    List<String>? mediaUrls,
    List<String>? mediaStoragePaths,
    int? reviewRound,
    bool? wasRejected,
    DateTime? firstSubmittedAt,
    DateTime? lastSubmittedAt,
  }) {
    return Observacion(
      id: id ?? this.id,
      idProyecto: idProyecto ?? this.idProyecto,
      uidUsuario: uidUsuario ?? this.uidUsuario,
      estado: estado != null ? EstadosObs.normalize(estado) : this.estado,
      ctxRol: ctxRol ?? this.ctxRol,
      idCategoria: idCategoria ?? this.idCategoria,
      fechaCaptura: fechaCaptura ?? this.fechaCaptura,
      edadAproximada: edadAproximada ?? this.edadAproximada,
      especieNombreCientifico:
      especieNombreCientifico ?? this.especieNombreCientifico,
      especieNombreComun: especieNombreComun ?? this.especieNombreComun,
      especieId: especieId ?? this.especieId,
      especieFueraCatalogo:
      especieFueraCatalogo ?? this.especieFueraCatalogo,
      especieSlug: especieSlug ?? this.especieSlug,
      lugarNombre: lugarNombre ?? this.lugarNombre,
      lugarTipo: lugarTipo ?? this.lugarTipo,
      municipio: municipio ?? this.municipio,
      municipioDisplay: municipioDisplay ?? this.municipioDisplay,
      estadoPais: estadoPais ?? this.estadoPais,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      altitud: altitud ?? this.altitud,
      notas: notas ?? this.notas,
      condicionAnimal: condicionAnimal ?? this.condicionAnimal,
      rastroTipo: rastroTipo ?? this.rastroTipo,
      rastroDetalle: rastroDetalle ?? this.rastroDetalle,
      taxoClase: taxoClase ?? this.taxoClase,
      taxoOrden: taxoOrden ?? this.taxoOrden,
      taxoFamilia: taxoFamilia ?? this.taxoFamilia,
      ubicEstado: ubicEstado ?? this.ubicEstado,
      ubicRegion: ubicRegion ?? this.ubicRegion,
      ubicDistrito: ubicDistrito ?? this.ubicDistrito,
      aiStatus: aiStatus ?? this.aiStatus,
      aiTopSuggestions: aiTopSuggestions ?? this.aiTopSuggestions,
      aiModel: aiModel ?? this.aiModel,
      aiError: aiError ?? this.aiError,
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
      coverUrl: coverUrl ?? this.coverUrl,
      primaryMediaId: primaryMediaId ?? this.primaryMediaId,
      mediaCount: mediaCount ?? this.mediaCount,
      capturaKey: capturaKey ?? this.capturaKey,
      autorNombre: autorNombre ?? this.autorNombre,
      proyectoNombre: proyectoNombre ?? this.proyectoNombre,
      categoriaNombre: categoriaNombre ?? this.categoriaNombre,
      identificadorUid: identificadorUid ?? this.identificadorUid,
      identificadorNombre:
      identificadorNombre ?? this.identificadorNombre,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      mediaStoragePaths: mediaStoragePaths ?? this.mediaStoragePaths,
      reviewRound: reviewRound ?? this.reviewRound,
      wasRejected: wasRejected ?? this.wasRejected,
      firstSubmittedAt: firstSubmittedAt ?? this.firstSubmittedAt,
      lastSubmittedAt: lastSubmittedAt ?? this.lastSubmittedAt,
    );
  }
}
