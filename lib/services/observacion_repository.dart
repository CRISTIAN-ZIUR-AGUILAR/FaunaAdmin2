import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:faunadmin2/models/observacion.dart';

/// Centraliza la escritura en Firestore para Observaciones.
/// Evita repetir `FirebaseFirestore.instance...` por toda la UI.
/// Maneja campos de auditoría (submittedAt, reviewRound, etc.).
class ObservacionRepository {
  ObservacionRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance,
        _col = (db ?? FirebaseFirestore.instance).collection('observaciones');

  final FirebaseFirestore _db;
  final CollectionReference<Map<String, dynamic>> _col;

  /// Cambiar estado con extras opcionales.
  Future<void> actualizarEstado(
      String id,
      String nuevoEstado, {
        Map<String, dynamic>? extra,
      }) async {
    final doc = _col.doc(id);
    final payload = <String, dynamic>{
      'estado': nuevoEstado,
      if (extra != null) ...extra,
    };
    await doc.update(payload);
  }

  /// Enviar un BORRADOR a PENDIENTE.
  /// - Sella submittedAt / lastSubmittedAt (server time)
  /// - Sella firstSubmittedAt si aún no existe
  /// - Inicializa reviewRound en 1 si no existe
  /// - Opcionalmente setea submittedBy si se provee `uid`
  Future<void> enviarAPendiente(
      Observacion obs, {
        String? uid,
      }) async {
    if (obs.id == null || obs.id!.isEmpty) {
      throw StateError('Observación sin ID.');
    }
    if (obs.estado != EstadosObs.borrador) {
      throw StateError('Solo se puede enviar a revisión desde BORRADOR.');
    }
    if (!_datosCompletos(obs)) {
      throw StateError('Datos incompletos: se requiere fecha, geo y al menos una foto.');
    }

    final docRef = _col.doc(obs.id);
    await _db.runTransaction((txn) async {
      final snap = await txn.get(docRef);
      if (!snap.exists) throw StateError('Observación no encontrada.');

      final data = snap.data()!;
      final tieneFirst = data['firstSubmittedAt'] != null;

      final update = <String, dynamic>{
        'estado': EstadosObs.pendiente,
        'submittedAt': FieldValue.serverTimestamp(),
        'lastSubmittedAt': FieldValue.serverTimestamp(),
        if (!tieneFirst) 'firstSubmittedAt': FieldValue.serverTimestamp(),
        // Si no existe review_round, arranca en 1
        'review_round': data['review_round'] is num ? data['review_round'] : 1,
        // bandera histórica (no afecta permisos)
        'was_rejected': data['was_rejected'] ?? false,
        if (uid != null && uid.isNotEmpty) 'submittedBy': uid,
      };

      // Si ya existía review_round y era 0/nulo, lo normalizamos a 1.
      if (data['review_round'] == null ||
          (data['review_round'] is num && data['review_round'] == 0)) {
        update['review_round'] = 1;
      }

      txn.update(docRef, update);
    });
  }

  /// Reenviar una observación RECHAZADA a REVISIÓN (reenvío).
  /// - Requiere que haya sido editada después del rechazo (seguridad en UI)
  /// - Cambia estado a `revisar_nuevo`
  /// - Incrementa reviewRound de forma atómica
  /// - Actualiza lastSubmittedAt (y submittedAt como sello actual)
  /// - Mantiene firstSubmittedAt
  Future<void> reenviarRevision(
      Observacion obs, {
        String? uid,
      }) async {
    if (obs.id == null || obs.id!.isEmpty) {
      throw StateError('Observación sin ID.');
    }
    if (obs.estado != EstadosObs.rechazado) {
      throw StateError('Solo se puede reenviar si la observación está RECHAZADA.');
    }
    // Esta validación fuerte se hace en el repo por si alguien intenta saltarse la UI:
    if (!_fueEditadaDespuesDeRechazo(obs)) {
      throw StateError('Debes editar la observación después del rechazo antes de reenviar.');
    }

    final docRef = _col.doc(obs.id);
    await _db.runTransaction((txn) async {
      final snap = await txn.get(docRef);
      if (!snap.exists) throw StateError('Observación no encontrada.');

      final data = snap.data()!;
      final roundActual =
      (data['review_round'] is num) ? (data['review_round'] as num).toInt() : 1;

      final update = <String, dynamic>{
        // 👇 aquí está el cambio importante
        'estado': EstadosObs.revisarNuevo,
        'submittedAt': FieldValue.serverTimestamp(),
        'lastSubmittedAt': FieldValue.serverTimestamp(),
        'review_round': roundActual + 1,
        'was_rejected': true, // deja traza histórica
        if (uid != null && uid.isNotEmpty) 'submittedBy': uid,
      };

      txn.update(docRef, update);
    });
  }

  /// Eliminar observación (usa permisos en capa superior).
  Future<void> eliminarObservacion(Observacion obs) async {
    if (obs.id == null || obs.id!.isEmpty) {
      throw StateError('Observación sin ID.');
    }
    await _col.doc(obs.id).delete();
  }

  // ================= Helpers internos =================

  /// Misma lógica que usas en la UI: fecha + geo + foto.
  static bool _datosCompletos(Observacion o) {
    final tieneFecha = o.fechaCaptura != null;
    final tieneGeo = o.lat != null && o.lng != null;
    final tieneFoto = (() {
      if (o.mediaUrls.isNotEmpty) return true;
      try {
        // Por compatibilidad con datos legacy si alguien aún llama toMap()['fotos']
        final raw = o.toMap()['fotos'];
        if (raw is List && raw.whereType<String>().isNotEmpty) return true;
      } catch (_) {}
      return false;
    })();
    return tieneFecha && tieneGeo && tieneFoto;
  }

  /// Considera que fue editada después del rechazo si:
  /// - validatedAt (momento del rechazo) existe
  /// - updatedAt existe y es posterior a validatedAt
  static bool _fueEditadaDespuesDeRechazo(Observacion o) {
    final rechazadoEn = o.validatedAt;
    final editadoEn = o.updatedAt ?? o.ultimaModificacion;
    if (rechazadoEn == null || editadoEn == null) return false;
    return editadoEn.isAfter(rechazadoEn);
  }
}
