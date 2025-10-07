// lib/services/notificacion_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:faunadmin2/models/notificacion.dart';
import 'package:faunadmin2/utils/notificaciones_constants.dart';

/// Service para emitir y consultar notificaciones internas.
/// Esquema alineado a Notificacion:
/// uid | proyectoId | obsId | tipo | nivel | titulo | mensaje | leida | createdAt | meta
class NotificacionService {
  final FirebaseFirestore _db;
  NotificacionService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('notificaciones');

  /// Crea una notificación.
  /// Requiere al menos `uid` o `proyectoId` (uno de los dos).
  Future<void> push({
    String? uid,
    String? proyectoId,
    String? obsId,
    required String tipo,   // usa NotiTipo.*
    required String nivel,  // usa NotiNivel.*
    required String titulo,
    required String mensaje,
    Map<String, dynamic>? meta,
  }) async {
    assert(uid != null || proyectoId != null,
    'Debes especificar uid o proyectoId');

    await _col.add({
      'uid': uid,
      'proyectoId': proyectoId,
      'obsId': obsId,
      'tipo': tipo,
      'nivel': nivel,
      'titulo': titulo,
      'mensaje': mensaje,
      'leida': false,
      'createdAt': FieldValue.serverTimestamp(),
      'meta': meta,
    });
  }

  /// Marca una notificación por ID como leída/no leída.
  Future<void> marcarLeida(String notifId, {bool value = true}) async {
    await _col.doc(notifId).update({'leida': value});
  }

  /// Marca TODAS las notificaciones de un usuario como leídas (lote).
  Future<void> marcarTodasLeidasPorUid(String uid, {int batchLimit = 500}) async {
    final qs = await _col
        .where('uid', isEqualTo: uid)
        .where('leida', isEqualTo: false)
        .limit(batchLimit)
        .get();

    if (qs.docs.isEmpty) return;

    final batch = _db.batch();
    for (final d in qs.docs) {
      batch.update(d.reference, {'leida': true});
    }
    await batch.commit();
  }

  /// Stream por UID (más recientes primero), con filtros opcionales por grupo.
  /// Si pasas `tiposIn`, filtra por esos tipos (ej. NotiTipo.grupoObservaciones.toList()).
  Stream<List<Notificacion>> streamPorUid(
      String uid, {
        List<String>? tiposIn,
        bool? soloNoLeidas,
        int limit = 100,
      }) {
    Query<Map<String, dynamic>> q = _col
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (soloNoLeidas == true) {
      q = q.where('leida', isEqualTo: false);
    }
    if (tiposIn != null && tiposIn.isNotEmpty) {
      q = q.where('tipo', whereIn: tiposIn);
    }

    return q.snapshots().map(
          (snap) => snap.docs.map((d) => Notificacion.fromDoc(d)).toList(),
    );
  }

  /// Stream por proyecto (útil para bandejas de equipo, si lo usas).
  Stream<List<Notificacion>> streamPorProyecto(
      String proyectoId, {
        List<String>? tiposIn,
        bool? soloNoLeidas,
        int limit = 100,
      }) {
    Query<Map<String, dynamic>> q = _col
        .where('proyectoId', isEqualTo: proyectoId)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (soloNoLeidas == true) {
      q = q.where('leida', isEqualTo: false);
    }
    if (tiposIn != null && tiposIn.isNotEmpty) {
      q = q.where('tipo', whereIn: tiposIn);
    }

    return q.snapshots().map(
          (snap) => snap.docs.map((d) => Notificacion.fromDoc(d)).toList(),
    );
  }

  // --- Helpers de conveniencia basados en tus constantes ---

  /// Observaciones del usuario (todas o solo no leídas).
  Stream<List<Notificacion>> streamObsDeUid(String uid, {bool soloNoLeidas = false}) {
    return streamPorUid(
      uid,
      tiposIn: NotiTipo.grupoObservaciones.toList(),
      soloNoLeidas: soloNoLeidas,
    );
  }

  /// Proyectos del usuario (todas o solo no leídas).
  Stream<List<Notificacion>> streamProyDeUid(String uid, {bool soloNoLeidas = false}) {
    return streamPorUid(
      uid,
      tiposIn: NotiTipo.grupoProyectos.toList(),
      soloNoLeidas: soloNoLeidas,
    );
  }

  /// Roles/URP del usuario (todas o solo no leídas).
  Stream<List<Notificacion>> streamRolesDeUid(String uid, {bool soloNoLeidas = false}) {
    return streamPorUid(
      uid,
      tiposIn: NotiTipo.grupoRoles.toList(),
      soloNoLeidas: soloNoLeidas,
    );
  }
}
