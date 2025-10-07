// lib/providers/notificacion_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/notificacion.dart';
import '../providers/auth_provider.dart';

/// Filtros disponibles para la bandeja de notificaciones.
enum NotiFiltro { todas, noLeidas, proyectos, observaciones, sistema }

/// Provider que gestiona el stream en tiempo real de notificaciones desde Firestore.
/// - Se suscribe por `uid` del usuario actual (AuthProvider.currentUserId)
/// - Aplica filtros simples por tipo / leído
/// - Expone lista inmutable para la UI
class NotificacionProvider with ChangeNotifier {
  final FirebaseFirestore _db;
  final AuthProvider _auth;

  NotificacionProvider(this._db, this._auth);

  final List<Notificacion> _items = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  NotiFiltro _filtro = NotiFiltro.todas;

  /// Lista de notificaciones (solo lectura)
  List<Notificacion> get items => List.unmodifiable(_items);

  /// Filtro activo
  NotiFiltro get filtro => _filtro;

  /// Cambia el filtro y vuelve a suscribirse.
  void setFiltro(NotiFiltro f) {
    if (_filtro == f) return;
    _filtro = f;
    _resuscribir();
  }

  /// Arranca/actualiza la suscripción (puedes llamarlo tras login).
  void start() => _resuscribir();

  /// Detiene la suscripción (útil en logout o dispose global).
  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  /// Marca una notificación como leída/no leída.
  Future<void> marcarLeida(String id, {bool value = true}) async {
    await _db.collection('notificaciones').doc(id).update({'leida': value});
  }

  void _resuscribir() {
    _sub?.cancel();

    final uid = _auth.currentUserId; // <- requiere getter en AuthProvider
    if (uid == null) {
      _items.clear();
      notifyListeners();
      return;
    }

    // Base query por usuario
    Query<Map<String, dynamic>> q = _db
        .collection('notificaciones')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(100);

    // Aplica filtro adicional
    switch (_filtro) {
      case NotiFiltro.noLeidas:
        q = q.where('leida', isEqualTo: false);
        break;
      case NotiFiltro.proyectos:
        q = q.where('tipo',
            whereIn: const ['proy.asignado', 'proy.editado', 'proy.estado']);
        break;
      case NotiFiltro.observaciones:
        q = q.where('tipo',
            whereIn: const ['obs.creada', 'obs.aprobada', 'obs.rechazada', 'obs.comentada']);
        break;
      case NotiFiltro.sistema:
        q = q.where('tipo',
            whereIn: const ['rol.cambiado', 'cuenta.estado', 'sistema.info']);
        break;
      case NotiFiltro.todas:
      // sin filtro adicional
        break;
    }

    _sub = q.snapshots().listen((snap) {
      _items
        ..clear()
        ..addAll(snap.docs.map((d) => Notificacion.fromDoc(d)));
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
