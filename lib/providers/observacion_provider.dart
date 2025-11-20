import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:faunadmin2/models/observacion.dart';
import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/services/firestore_service.dart';
import 'package:faunadmin2/utils/app_error.dart';
import 'package:faunadmin2/services/permisos_service.dart';
import 'package:faunadmin2/services/notificacion_service.dart';
import 'package:faunadmin2/services/proyecto_service.dart';
import 'package:faunadmin2/utils/notificaciones_constants.dart';

/// ====== MÍNIMOS PARA ENVIAR A REVISIÓN (única fuente de verdad) ======
class MinimosObs {
  /// Devuelve lista de faltantes legibles según tu política actual:
  /// - ≥1 foto
  /// - fecha/hora de captura (fecha_captura o fechaHoraCaptura)
  /// - tipo_lugar
  /// - lugar o municipio
  /// - lat & lng
  /// - condicion (si es 'rastro', requiere rastro_tipo o rastro_detalle)
  static List<String> validar(Map<String, dynamic> raw) {
    final List<String> faltan = [];

    bool _has(dynamic v) =>
        v != null &&
            !(v is String && v.trim().isEmpty) &&
            !(v is Iterable && v.isEmpty) &&
            !(v is Map && v.isEmpty);

    // Fotos (al menos 1)
    final media = raw['media'];
    final mediaCount = (raw['media_count'] is num)
        ? (raw['media_count'] as num).toInt()
        : (media is List ? media.length : 0);
    if (mediaCount < 1) faltan.add('Al menos 1 fotografía');

    // Fecha/hora de captura
    final tieneFecha =
        _has(raw['fecha_captura']) || _has(raw['fechaHoraCaptura']);
    if (!tieneFecha) faltan.add('Fecha/hora de captura');

    // Tipo de lugar
    if (!_has(raw['tipo_lugar'])) faltan.add('Tipo de lugar');

    // Lugar o municipio
    final tieneLugar = _has(raw['lugar']) || _has(raw['municipio']);
    if (!tieneLugar) faltan.add('Lugar o municipio');

    // Coordenadas
    if (!_has(raw['lat']) || !_has(raw['lng'])) faltan.add('Coordenadas');

    // Condición
    final condicion = (raw['condicion'] ?? '').toString().trim().toLowerCase();
    if (condicion.isEmpty) {
      faltan.add('Condición del animal');
    } else if (condicion == 'rastro') {
      final tieneDetalleRastro =
          _has(raw['rastro_tipo']) || _has(raw['rastro_detalle']);
      if (!tieneDetalleRastro) faltan.add('Detalle de rastro');
    }

    return faltan;
  }

  static bool cumple(Map<String, dynamic> raw) => validar(raw).isEmpty;
}

/// ====== CANONIZACIÓN DE NOMBRE CIENTÍFICO ======
class CanonCientifico {
  static String? _cap(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (t.isEmpty) return null;
    return t[0].toUpperCase() + t.substring(1).toLowerCase();
  }

  static String? _low(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (t.isEmpty) return null;
    return t.toLowerCase();
  }

  /// Normaliza: "Género epíteto..." / "Género sp."
  static String? canonizar(String? raw) {
    if (raw == null) return null;
    final parts =
    raw.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;

    final genero = _cap(parts.first);
    if (parts.length == 1) {
      return genero; // solo género
    }

    if (parts.length == 2 && parts[1].toLowerCase() == 'sp.') {
      return '$genero sp.';
    }

    final resto = parts.skip(1).map(_low).whereType<String>().join(' ');
    return '$genero $resto';
  }
}

/// ======== Orquestador de Observaciones ========
class ObservacionProvider with ChangeNotifier {
  final FirestoreService _fs;
  final AuthProvider _auth;
  ObservacionProvider(this._fs, this._auth);

  // ====== Estado local UI ======
  final List<Observacion> _observaciones = [];
  bool _isLoading = false;
  String? _lastMessage;
  String? _lastError;

  List<Observacion> get observaciones => List.unmodifiable(_observaciones);
  bool get isLoading => _isLoading;
  String? get lastMessage => _lastMessage;
  String? get lastError => _lastError;

  void clearToasts() {
    _lastMessage = null;
    _lastError = null;
    notifyListeners();
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  void _setMessage(String? m) {
    _lastMessage = m;
    notifyListeners();
  }

  void _setError(Object e, {String? fallback}) {
    if (e is AppError) {
      final msg = (e.message).toString();
      _lastError = (msg.isEmpty) ? (fallback ?? 'Ocurrió un error') : msg;
    } else if (e is String) {
      _lastError = e;
    } else {
      _lastError = fallback ?? 'Ocurrió un error inesperado';
    }
    notifyListeners();
  }

  // ====== Stream management ======
  StreamSubscription<List<Observacion>>? _sub;
  String? _currentProyectoId;
  String? _currentEstado;

  Future<void> _bind(Stream<List<Observacion>> stream) async {
    await stop();
    _setLoading(true);
    _sub = stream.listen((list) {
      _observaciones
        ..clear()
        ..addAll(list);
      _setLoading(false);
    }, onError: (e) {
      _setError(e);
      _setLoading(false);
    });
  }

  Future<void> watchProyecto({
    required String? proyectoId,
    String? estado,
    int limit = 100,
  }) async {
    _currentProyectoId =
    (proyectoId?.trim().isEmpty ?? true) ? null : proyectoId;
    _currentEstado = (estado?.trim().isEmpty ?? true) ? null : estado;

    final s = _fs.streamObservacionesByProyecto(
      proyectoId: _currentProyectoId,
      estado: _currentEstado,
      limit: limit,
    );
    await _bind(s);
  }

  Future<void> watchAuto({
    String? estado,
    bool incluirSinProyectoParaModeradores = false,
    int limit = 200,
  }) async {
    _currentProyectoId = null;
    _currentEstado = (estado?.trim().isEmpty ?? true) ? null : estado;

    final uid = _auth.uid;
    if (uid == null) {
      _observaciones.clear();
      notifyListeners();
      return;
    }

    final permisos = PermisosService(_auth);

    // 1) Admin único → ve todo
    if (permisos.isAdminUnico) {
      final s = _fs.streamObservacionesByScope(
        scope: ObsScope.all,
        estado: _currentEstado,
        limit: limit,
      );
      await _bind(s);
      return;
    }

    // 2) Recolector sin proyecto → solo sus propias observaciones
    //    (obs con y sin proyecto, pero filtradas por uid)
    final sel = _auth.selectedRolProyecto;
    final sinProyectoEnContexto =
        sel == null || sel.idProyecto == null || sel.idProyecto!.trim().isEmpty;

    if (permisos.isRecolector && sinProyectoEnContexto) {
      final s = _fs.streamObservacionesByScope(
        scope: ObsScope.own,
        estado: _currentEstado,
        uid: uid,
        limit: limit,
      );
      await _bind(s);
      return;
    }

    // 3) Moderadores (supervisor / dueño) → por proyectos moderables
    final moderables = await _fs.projectIdsModerablesPor(uid);
    if (moderables.isNotEmpty) {
      final s = _fs.streamObservacionesByScope(
        scope: ObsScope.byProjects,
        estado: _currentEstado,
        projectIds: moderables,
        includeSinProyecto: incluirSinProyectoParaModeradores,
        limit: limit,
      );
      await _bind(s);
      return;
    }

    // 4) Resto de usuarios → solo las suyas
    final s = _fs.streamObservacionesByScope(
      scope: ObsScope.own,
      estado: _currentEstado,
      uid: uid,
      limit: limit,
    );
    await _bind(s);
  }

  Future<void> watchMisObservaciones({
    String? estado,
    int limit = 150,
  }) async {
    final uid = _auth.uid;
    if (uid == null) return;
    _currentProyectoId = null;
    _currentEstado = (estado?.trim().isEmpty ?? true) ? null : estado;

    final s = _fs.streamObservacionesByScope(
      scope: ObsScope.own,
      estado: _currentEstado,
      uid: uid,
      limit: limit,
    );
    await _bind(s);
  }

  Future<void> stop({bool clear = false}) async {
    await _sub?.cancel();
    _sub = null;
    if (clear) {
      _observaciones.clear();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ====== Creación ======
  Future<String?> crearEnProyecto({
    required String proyectoId,
    required Observacion data,
    bool toast = true,
  }) async {
    try {
      final uid = _auth.uid ?? '';
      final needsUid = (data.uidUsuario.trim().isEmpty);
      final safeData = needsUid ? data.copyWith(uidUsuario: uid) : data;

      final id = await _fs.createObservacion(
        auth: _auth,
        proyectoId: proyectoId,
        data: safeData,
      );

      if (id.trim().isEmpty) {
        throw Exception('createObservacion devolvió null/empty');
      }

      if (toast) _setMessage('Observación creada');
      debugPrint('[OBS_PROV] crearEnProyecto($proyectoId) -> id=$id');

      return id;
    } catch (e, st) {
      _setError(e);
      debugPrint('[OBS_PROV] ERROR crearEnProyecto: $e\n$st');
      // dejamos que el error suba para que la UI vea el motivo real
      rethrow;
    }
  }

  Future<String?> crearSinProyecto({
    required Observacion data,
    bool toast = true,
  }) async {
    try {
      final uid = _auth.uid ?? '';
      final needsUid = (data.uidUsuario.trim().isEmpty);
      final safeData = needsUid ? data.copyWith(uidUsuario: uid) : data;

      final id = await _fs.createObservacionSinProyecto(
        auth: _auth,
        data: safeData,
      );

      if (id == null || id.trim().isEmpty) {
        throw Exception('createObservacionSinProyecto devolvió null/empty');
      }

      if (toast) _setMessage('Observación creada (sin proyecto)');
      debugPrint('[OBS_PROV] crearSinProyecto -> id=$id');

      return id;
    } catch (e, st) {
      _setError(e);
      debugPrint('[OBS_PROV] ERROR crearSinProyecto: $e\n$st');
      // igual, dejamos que el error suba
      rethrow;
    }
  }

  Future<bool> patch({
    required String observacionId,
    required Map<String, dynamic> patch,
    bool toast = true,
  }) async {
    try {
      final data = Map<String, dynamic>.from(patch);

      // === Canonización de nombre científico ===
      // Acepta todas las variantes que usamos en UI/Remoto:
      // - nombre_cientifico / nombreCientifico
      // - especie_nombre_cientifico / especieNombreCientifico
      for (final key in [
        'nombre_cientifico',
        'nombreCientifico',
        'especie_nombre_cientifico',
        'especieNombreCientifico',
      ]) {
        if (data.containsKey(key) && data[key] is String) {
          final canon = CanonCientifico.canonizar(data[key] as String?);
          if (canon == null || canon.trim().isEmpty) {
            // si viene vacío, elimina esa(s) clave(s)
            data.remove(key);
          } else {
            // Persistimos ambas familias en snake_case, por compatibilidad:
            // - nombre_cientifico (si tu UI legada la usa)
            // - especie_nombre_cientifico (la que estamos usando ahora)
            data['nombre_cientifico'] = canon;
            data['especie_nombre_cientifico'] = canon;

            // limpiamos las variantes camelCase si llegaron
            data.remove('nombreCientifico');
            data.remove('especieNombreCientifico');
          }
        }
      }
      // === Limpieza: null => DELETE (mantén FieldValue tal cual)
      data.updateAll((k, v) => v == null ? FieldValue.delete() : v);
      // debugPrint('[patch $observacionId] keys=${data.keys.toList()}');
      await _fs.patchObservacion(
        auth: _auth,
        observacionId: observacionId,
        patch: data,
      );

      if (toast) _setMessage('Cambios guardados');
      return true;
    } catch (e) {
      _setError(e);
      return false;
    }
  }

  // ====== Cambios de estado (UNIFICADOS) ======

  Future<bool> enviarAPendiente(String observacionId,
      {bool toast = true}) async =>
      _enviarRevisionCore(
        observacionId: observacionId,
        estadoDestino: EstadosObs.pendiente,
        toast: toast,
        tituloNoti: 'Observación enviada a revisión',
        mensajeNoti: 'Observación',
        metaExtra: null,
      );

  /// 🔁 Reenviar observación RECHAZADA a revisión (usa revisar_nuevo)
  Future<bool> reenviarRevision(String observacionId,
      {bool toast = true}) async {
    // Valida estado y autor, luego usa el core con estado revisar_nuevo
    try {
      final obsDoc = await FirebaseFirestore.instance
          .collection('observaciones')
          .doc(observacionId)
          .get();

      if (!obsDoc.exists || obsDoc.data() == null) {
        _setError('No existe la observación');
        return false;
      }

      final raw = obsDoc.data()!;
      final estadoActual = (raw['estado'] ?? '').toString();
      if (estadoActual != EstadosObs.rechazado) {
        _setError('Solo las observaciones rechazadas pueden reenviarse');
        return false;
      }

      final autorUid = _readString(raw, ['uid_usuario', 'uidUsuario']);
      if (autorUid != _auth.uid) {
        _setError('Solo el autor puede reenviar su observación');
        return false;
      }
    } catch (e) {
      _setError(e);
      return false;
    }

    return _enviarRevisionCore(
      observacionId: observacionId,
      estadoDestino: EstadosObs.revisarNuevo,
      toast: toast,
      tituloNoti: 'Observación reenviada a revisión',
      mensajeNoti: 'Observación',
      metaExtra: {'reenvio': true},
    );
  }

  Future<bool> aprobar(String id, {bool toast = true}) =>
      _cambiarEstadoNotificando(
          id, EstadosObs.aprobado, 'aprobada', toast ? 'Aprobada' : null);

  Future<bool> rechazar(String id,
      {required String motivo, bool toast = true}) async {
    // Marca telemetría antes del cambio de estado
    try {
      await _fs.patchObservacion(
        auth: _auth,
        observacionId: id,
        patch: {
          'was_rejected': true,
          'rejectionReason': motivo,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': _auth.uid,
        },
      );
    } catch (_) {}
    return _cambiarEstadoNotificando(
      id,
      EstadosObs.rechazado,
      'rechazada',
      toast ? 'Rechazada' : null,
      rejectionReason: motivo,
    );
  }

  Future<bool> archivar(String id, {bool toast = true}) =>
      _cambiarEstadoNotificando(
          id, EstadosObs.archivado, 'archivada', toast ? 'Archivada' : null);

  Future<bool> revertirABorrador(String id, {bool toast = true}) =>
      _cambiarEstadoNotificando(
          id, EstadosObs.borrador, 'borrador', toast ? 'Borrador' : null);

  Future<bool> _cambiarEstadoNotificando(
      String id,
      String nuevoEstado,
      String accion,
      String? toastOk, {
        String? rejectionReason,
      }) async {
    try {
      await _fs.changeEstadoObservacion(
        auth: _auth,
        observacionId: id,
        nuevoEstado: nuevoEstado,
        rejectionReason: rejectionReason,
      );
      if (toastOk != null) _setMessage('Observación $toastOk');
      return true;
    } catch (e) {
      _setError(e);
      return false;
    }
  }

  /// ----- Núcleo unificado para enviar/re-enviar a revisión -----
  Future<bool> _enviarRevisionCore({
    required String observacionId,
    required String estadoDestino, // EstadosObs.pendiente o EstadosObs.revisarNuevo
    bool toast = true,
    required String tituloNoti,
    required String mensajeNoti,
    Map<String, dynamic>? metaExtra,
  }) async {
    try {
      final docRef =
      FirebaseFirestore.instance.collection('observaciones').doc(observacionId);
      final snap = await docRef.get();
      if (!snap.exists || snap.data() == null) {
        _setError('No existe la observación');
        return false;
      }
      final raw = snap.data()!;
      final autorUid = _readString(raw, ['uid_usuario', 'uidUsuario']);
      final proyectoId = _readString(raw, ['id_proyecto', 'idProyecto']);

      // Permisos básicos: autor o admin
      final soyAutor = autorUid == _auth.uid;
      if (!soyAutor && !_auth.isAdmin) {
        _setError('Sin permiso para enviar a revisión');
        return false;
      }

      // Telemetría de rondas
      final int roundPrev =
      (raw['review_round'] is num) ? (raw['review_round'] as num).toInt() : 0;
      final bool fueRechazada = (raw['estado'] ?? '') == EstadosObs.rechazado;

      final now = FieldValue.serverTimestamp();

      // Patch de envío/reenvío
      final patch = <String, dynamic>{
        'estado': estadoDestino,
        'rejectionReason': null,
        'was_rejected': fueRechazada,
        'lastSubmittedAt': now,
        'firstSubmittedAt': raw['firstSubmittedAt'] ?? now,
        'review_round': fueRechazada
            ? (roundPrev <= 0 ? 2 : (roundPrev + 1))
            : (roundPrev <= 0 ? 1 : roundPrev),
        'updatedAt': now,
        'updatedBy': _auth.uid,
        'submittedAt': now,
        'submittedBy': _auth.uid,
      };

      await _fs.patchObservacion(
        auth: _auth,
        observacionId: observacionId,
        patch: patch,
      );

      if (toast) _setMessage('Enviada a revisión');

      // Notificaciones
      if (proyectoId != null && proyectoId.isNotEmpty) {
        final recipients = await ProyectoService().resolveRecipients(
          proyectoId: proyectoId,
          includeDueno: true,
          includeSupervisores: true,
        );
        for (final uid in recipients) {
          if (uid == autorUid) continue;
          await NotificacionService().push(
            uid: uid,
            proyectoId: proyectoId,
            obsId: observacionId,
            tipo: NotiTipo.obsAsignadaRevision,
            nivel: NotiNivel.info,
            titulo: tituloNoti,
            mensaje: '$mensajeNoti ${_shortId(observacionId)}',
            meta: {
              'estado': estadoDestino,
              'autorUid': autorUid,
              if (metaExtra != null) ...metaExtra,
            },
          );
        }
      }
      return true;
    } catch (e) {
      _setError(e);
      return false;
    }
  }

  // ====== UTILIDADES PÚBLICAS PARA SYNC/UI ======

  /// Valida mínimos a partir de un map crudo del doc
  List<String> validarMinimosRaw(Map<String, dynamic> raw) =>
      MinimosObs.validar(raw);

  /// Valida mínimos por ID (lee Firestore)
  Future<List<String>> validarMinimosPorId(String observacionId) async {
    final snap = await FirebaseFirestore.instance
        .collection('observaciones')
        .doc(observacionId)
        .get();
    if (!snap.exists || snap.data() == null) {
      return ['Observación no encontrada'];
    }
    return MinimosObs.validar(snap.data()!);
  }

  /// Borradores del usuario listos para revisión (cumplen mínimos)
  Future<List<DocumentSnapshot<Map<String, dynamic>>>>
  queryBorradoresListosParaRevision(String uid) async {
    final col = FirebaseFirestore.instance.collection('observaciones');
    final q = await col
        .where('uid_usuario', isEqualTo: uid)
        .where('estado', isEqualTo: EstadosObs.borrador)
        .limit(200)
        .get();

    return q.docs.where((d) => MinimosObs.cumple(d.data())).toList();
  }

  /// Intenta pasar a 'pendiente' si cumple mínimos; si no, queda en 'borrador'
  Future<bool> intentarEnviarAPendienteSiCumple(String observacionId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('observaciones')
          .doc(observacionId)
          .get();
      if (!snap.exists || snap.data() == null) return false;

      final raw = snap.data()!;
      final faltan = MinimosObs.validar(raw);
      if (faltan.isEmpty) {
        return await enviarAPendiente(observacionId, toast: false);
      }
      return false;
    } catch (e) {
      _setError(e);
      return false;
    }
  }

  // ====== Helpers ======
  String? _readString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  String _shortId(String id) => id.length <= 6 ? id : id.substring(0, 6);
}
