// lib/providers/observacion_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:faunadmin2/models/observacion.dart';
import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/services/firestore_service.dart';
import 'package:faunadmin2/utils/app_error.dart';
import 'package:faunadmin2/services/permisos_service.dart';

// Notificaciones y resolución de destinatarios
import 'package:faunadmin2/models/notificacion.dart';
import 'package:faunadmin2/services/notificacion_service.dart';
import 'package:faunadmin2/services/proyecto_service.dart';
import 'package:faunadmin2/utils/notificaciones_constants.dart'; // 👈 tipos/niveles

/// Orquestador de Observaciones
class ObservacionProvider with ChangeNotifier {
  final FirestoreService _fs;
  final AuthProvider _auth;
  ObservacionProvider(this._fs, this._auth);

  // ============== Estado básico UI ==============
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

  // ============== Stream management ==============
  StreamSubscription<List<Observacion>>? _sub;
  String? _currentProyectoId; // null => sin proyecto
  String? _currentEstado;     // null => todos

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
    _currentProyectoId = (proyectoId?.trim().isEmpty ?? true) ? null : proyectoId;
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

    if (permisos.isAdminUnico) {
      final s = _fs.streamObservacionesByScope(
        scope: ObsScope.all,
        estado: _currentEstado,
        limit: limit,
      );
      await _bind(s);
      return;
    }

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

  Future<void> watchProyectosModerables({
    required List<String> projectIds,
    String? estado,
    bool includeSinProyecto = false,
    int limit = 200,
  }) async {
    _currentProyectoId = null;
    _currentEstado = (estado?.trim().isEmpty ?? true) ? null : estado;

    final s = _fs.streamObservacionesByScope(
      scope: ObsScope.byProjects,
      estado: _currentEstado,
      projectIds: projectIds,
      includeSinProyecto: includeSinProyecto,
      limit: limit,
    );
    await _bind(s);
  }

  Future<void> setEstadoFiltro(String? estado) async {
    _currentEstado = (estado?.trim().isEmpty ?? true) ? null : estado;

    if (_currentProyectoId != null) {
      await watchProyecto(proyectoId: _currentProyectoId, estado: _currentEstado);
    } else {
      await watchAuto(estado: _currentEstado);
    }
  }

  Future<void> refresh() async {
    if (_sub == null) {
      await watchAuto(estado: _currentEstado);
      return;
    }
    if (_currentProyectoId != null) {
      await watchProyecto(proyectoId: _currentProyectoId, estado: _currentEstado);
    } else {
      await watchAuto(estado: _currentEstado);
    }
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

  // ============== Creación ==============
  Future<String?> crearEnProyecto({
    required String proyectoId,
    required Observacion data,
    bool toast = true,
  }) async {
    try {
      // Asegura uid_usuario
      final uid = _auth.uid ?? '';
      final needsUid = (data.uidUsuario == null || data.uidUsuario!.trim().isEmpty);
      final Observacion safeData = needsUid ? data.copyWith(uidUsuario: uid) : data;

      final id = await _fs.createObservacion(
        auth: _auth,
        proyectoId: proyectoId,
        data: safeData,
      );

      if (id == null || id.trim().isEmpty) {
        throw Exception('createObservacion devolvió null/empty (proyectoId=$proyectoId)');
      }

      if (toast) _setMessage('Observación creada');
      return id;
    } catch (e) {
      _setError(e);
      debugPrint('crearEnProyecto error: $e');
      return null;
    }
  }

  Future<String?> crearSinProyecto({
    required Observacion data,
    bool toast = true,
  }) async {
    try {
      // Asegura uid_usuario
      final uid = _auth.uid ?? '';
      final needsUid = (data.uidUsuario == null || data.uidUsuario!.trim().isEmpty);
      final Observacion safeData = needsUid ? data.copyWith(uidUsuario: uid) : data;

      final id = await _fs.createObservacionSinProyecto(
        auth: _auth,
        data: safeData,
      );

      if (id == null || id.trim().isEmpty) {
        throw Exception('createObservacionSinProyecto devolvió null/empty');
      }

      if (toast) _setMessage('Observación creada (sin proyecto)');
      return id;
    } catch (e) {
      _setError(e);
      debugPrint('crearSinProyecto error: $e');
      return null;
    }
  }

  // ============== Patch / Update ==============
  Future<bool> patch({
    required String observacionId,
    required Map<String, dynamic> patch,
    bool toast = true,
  }) async {
    try {
      final data = Map<String, dynamic>.from(patch);
      data.updateAll((k, v) => v == null ? FieldValue.delete() : v);

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

  // ============== Cambios de estado + Notificaciones ==============

  Future<bool> enviarAPendiente(String observacionId, {bool toast = true}) async {
    try {
      final obsDoc = await FirebaseFirestore.instance
          .collection('observaciones')
          .doc(observacionId)
          .get();

      if (!obsDoc.exists || obsDoc.data() == null) {
        _setError(AppError.unknown('No existe la observación'));
        return false;
      }
      final raw = obsDoc.data()!;
      final proyectoId = _readString(raw, ['id_proyecto', 'idProyecto', 'proyectoId']);
      final autorUid   = _readString(raw, ['uid_usuario', 'uidUsuario', 'autorUid']);

      // Cualquiera puede enviar su observación a pendiente, pero si no eres autor, requerimos permisos de moderador.
      final permisos = PermisosService(_auth);
      final soyAutor = autorUid == _auth.uid;
      if (!soyAutor) {
        final esAdmin = _auth.isAdmin || permisos.isAdminUnico;
        final same = (proyectoId != null &&
            _auth.selectedRolProyecto?.idProyecto == proyectoId);
        final supervisorODueno = same &&
            (permisos.isSupervisorEnContexto || permisos.isDuenoEnContexto);
        if (!(esAdmin || supervisorODueno)) {
          _setError('Sin permiso para enviar a revisión');
          return false;
        }
      }

      await _fs.changeEstadoObservacion(
        auth: _auth,
        observacionId: observacionId,
        nuevoEstado: EstadosObs.pendiente,
        rejectionReason: null,
      );
      if (toast) _setMessage('Enviada a revisión');

      // Notificar a dueños/supervisores del proyecto (esquema nuevo)
      if (proyectoId != null && proyectoId.isNotEmpty) {
        final recipients = await ProyectoService().resolveRecipients(
          proyectoId: proyectoId,
          includeDueno: true,
          includeSupervisores: true,
          includeColaboradores: false,
        );

        if (recipients.isNotEmpty) {
          final notif = NotificacionService();
          await Future.wait(recipients.map((uid) {
            if (uid == autorUid) return Future.value();
            return notif.push(
              uid: uid,
              proyectoId: proyectoId,
              obsId: observacionId,
              tipo: NotiTipo.obsAsignadaRevision,
              nivel: NotiNivel.info,
              titulo: 'Observación enviada a revisión',
              mensaje: 'Observación ${_shortId(observacionId)} enviada a revisión',
              meta: {
                'proyectoId': proyectoId,
                'estado': EstadosObs.pendiente,
                'autorUid': autorUid,
              },
            );
          }));
        }
      }

      return true;
    } catch (e) {
      _setError(e);
      return false;
    }
  }

  Future<bool> aprobar(String observacionId, {bool toast = true}) async {
    return _cambiarEstadoNotificando(
      observacionId: observacionId,
      nuevoEstado: EstadosObs.aprobado,
      accionNotif: 'aprobada',
      toastOk: toast ? 'Observación aprobada' : null,
      // precheck
      requireModerationPerms: true,
    );
  }

  Future<bool> rechazar(
      String observacionId, {
        required String motivo,
        bool toast = true,
      }) async {
    return _cambiarEstadoNotificando(
      observacionId: observacionId,
      nuevoEstado: EstadosObs.rechazado,
      accionNotif: 'rechazada',
      toastOk: toast ? 'Observación rechazada' : null,
      rejectionReason: motivo,
      extraBuilder: (base) => {...base, 'motivo': motivo},
      // precheck
      requireModerationPerms: true,
    );
  }

  Future<bool> archivar(String observacionId, {bool toast = true}) async {
    return _cambiarEstadoNotificando(
      observacionId: observacionId,
      nuevoEstado: EstadosObs.archivado,
      accionNotif: 'archivada',
      toastOk: toast ? 'Observación archivada' : null,
      // precheck
      requireModerationPerms: true,
    );
  }

  Future<bool> revertirABorrador(String observacionId, {bool toast = true}) async {
    return _cambiarEstadoNotificando(
      observacionId: observacionId,
      nuevoEstado: EstadosObs.borrador,
      accionNotif: 'borrador',
      toastOk: toast ? 'Devuelta a borrador' : null,
      // precheck: permitir al autor devolver a borrador; si no es autor, requiere moderación
      requireModerationPermsIfNotAuthor: true,
    );
  }

  /// Cambia estado, y notifica al AUTOR (excepto cuando se envía a 'pendiente').
  Future<bool> _cambiarEstadoNotificando({
    required String observacionId,
    required String nuevoEstado,
    required String accionNotif,
    String? rejectionReason,
    String? toastOk,
    Map<String, dynamic> Function(Map<String, dynamic> base)? extraBuilder,
    bool requireModerationPerms = false,
    bool requireModerationPermsIfNotAuthor = false,
  }) async {
    try {
      // Leer datos mínimos para notificar y validar permisos
      final obsDoc = await FirebaseFirestore.instance
          .collection('observaciones')
          .doc(observacionId)
          .get();

      if (!obsDoc.exists || obsDoc.data() == null) {
        _setError(AppError.unknown('No existe la observación'));
        return false;
      }
      final raw = obsDoc.data()!;
      final proyectoId = _readString(raw, ['id_proyecto', 'idProyecto', 'proyectoId']);
      final autorUid   = _readString(raw, ['uid_usuario', 'uidUsuario', 'autorUid']);

      // ===== PRE-CHECK DE PERMISOS (UI) =====
      final permisos = PermisosService(_auth);
      final esAdmin = _auth.isAdmin || permisos.isAdminUnico;
      final soyAutor = autorUid == _auth.uid;

      bool requiere = requireModerationPerms ||
          (requireModerationPermsIfNotAuthor && !soyAutor);

      if (requiere) {
        // Supervisor o Dueño en el MISMO proyecto y que no sea el autor.
        final same = (proyectoId != null &&
            _auth.selectedRolProyecto?.idProyecto == proyectoId);
        final supervisorODueno =
            same && (permisos.isSupervisorEnContexto || permisos.isDuenoEnContexto);

        final allowed = esAdmin || (supervisorODueno && !soyAutor);
        if (!allowed) {
          _setError('Sin permiso para moderar esta observación');
          return false;
        }
      }

      // ===== Cambio real (server-side vuelve a validar) =====
      await _fs.changeEstadoObservacion(
        auth: _auth,
        observacionId: observacionId,
        nuevoEstado: nuevoEstado,
        rejectionReason: rejectionReason,
      );
      if (toastOk != null) _setMessage(toastOk);

      // Notificar al autor (esquema nuevo)
      if ((autorUid ?? '').isNotEmpty) {
        final baseMeta = {
          'proyectoId': proyectoId,
          'estado': nuevoEstado,
        };
        final meta = extraBuilder != null ? extraBuilder(baseMeta) : baseMeta;

        final m = _mapNotifForAccion(accionNotif);

        await NotificacionService().push(
          uid: autorUid!,
          proyectoId: proyectoId,
          obsId: observacionId,
          tipo: m.tipo,      // NotiTipo.*
          nivel: m.nivel,    // NotiNivel.*
          titulo: m.titulo,
          mensaje: _mensajePorAccion(accionNotif, _shortId(observacionId)),
          meta: meta,
        );
      }

      return true;
    } catch (e) {
      _setError(e);
      return false;
    }
  }

  // ============== IA (sugerencias) ==============
  Future<bool> aplicarSugerenciaIA({
    required String observacionId,
    required Map<String, dynamic> suggestion,
    bool toast = true,
  }) async {
    try {
      await _fs.applyAiSuggestion(
        auth: _auth,
        observacionId: observacionId,
        suggestion: suggestion,
      );
      if (toast) _setMessage('Sugerencia aplicada');
      return true;
    } catch (e) {
      _setError(e);
      return false;
    }
  }

  // ============== KPIs ==============
  Future<int> contarEnProyecto(String proyectoId) =>
      _fs.countObservacionesProyecto(proyectoId);

  Future<int> contarSinProyecto() => _fs.countObservacionesSinProyecto();

  // ============== Helpers locales ==============

  /// Lee la primera clave no nula/ no vacía de la lista dada.
  String? _readString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  String _mensajePorAccion(String accion, String shortId) {
    switch (accion) {
      case 'aprobada':
        return 'Tu observación $shortId fue aprobada ✅';
      case 'rechazada':
        return 'Tu observación $shortId fue rechazada ❌';
      case 'archivada':
        return 'Tu observación $shortId fue archivada';
      case 'borrador':
        return 'Tu observación $shortId volvió a borrador';
      case 'enviada_revision':
        return 'Observación $shortId enviada a revisión';
      default:
        return 'Actualización en observación $shortId';
    }
  }

  String _shortId(String id) => id.length <= 6 ? id : id.substring(0, 6);
}

/// ====== Helper para mapear acciones → (tipo, nivel, título) ======
class _NotifMap {
  final String tipo;
  final String nivel;
  final String titulo;
  const _NotifMap(this.tipo, this.nivel, this.titulo);
}

_NotifMap _mapNotifForAccion(String accion) {
  switch (accion) {
    case 'aprobada':
      return _NotifMap(
        NotiTipo.obsAprobada,
        NotiNivel.success,
        'Observación aprobada',
      );
    case 'rechazada':
      return _NotifMap(
        NotiTipo.obsRechazada,
        NotiNivel.error,
        'Observación rechazada',
      );
    case 'archivada':
    // Si prefieres un tipo dedicado, agrega NotiTipo.obsArchivada
      return _NotifMap(
        NotiTipo.obsEditada,
        NotiNivel.info,
        'Observación archivada',
      );
    case 'borrador':
    // Si prefieres un tipo dedicado, agrega NotiTipo.obsDevueltaBorrador
      return _NotifMap(
        NotiTipo.obsEditada,
        NotiNivel.info,
        'Devuelta a borrador',
      );
    case 'enviada_revision':
      return _NotifMap(
        NotiTipo.obsAsignadaRevision,
        NotiNivel.info,
        'Observación enviada a revisión',
      );
    default:
      return _NotifMap(
        NotiTipo.obsEditada,
        NotiNivel.info,
        'Actualización de observación',
      );
  }
}

