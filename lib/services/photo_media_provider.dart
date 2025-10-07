// lib/service/photo_media_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:faunadmin2/models/photo_media.dart';

/// Administra los PhotoMedia de una observación:
/// - Stream de la subcolección `observaciones/{obsId}/media`
/// - Estado de carga / mensajes / errores para la UI
/// - Operaciones básicas: add, patch, delete
/// - Atajos para actualizar veredictos/flags
class PhotoMediaProvider with ChangeNotifier {
  final FirebaseFirestore _db;

  PhotoMediaProvider(this._db);

  // ===== UI State =====
  final List<PhotoMedia> _items = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  bool _isLoading = false;
  String? _lastMessage;
  String? _lastError;
  String? _currentObsId;

  List<PhotoMedia> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  String? get lastMessage => _lastMessage;
  String? get lastError => _lastError;
  String? get currentObservacionId => _currentObsId;

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  void _msg(String? m) {
    _lastMessage = m;
    notifyListeners();
  }

  void _err(Object e, {String fallback = 'Ocurrió un error'}) {
    _lastError = (e is FirebaseException) ? e.message : fallback;
    notifyListeners();
  }

  void clearToasts() {
    _lastMessage = null;
    _lastError = null;
    notifyListeners();
  }

  // ===== Streaming =====

  /// Comienza/rehace el stream sobre `observaciones/{obsId}/media`
  Future<void> watch(String observacionId) async {
    await stop();
    _currentObsId = observacionId;
    _setLoading(true);

    final col = _db
        .collection('observaciones')
        .doc(observacionId)
        .collection('media')
        .orderBy('createdAt', descending: true);

    _sub = col.snapshots().listen((snap) {
      _items
        ..clear()
        ..addAll(snap.docs.map((d) => PhotoMedia.fromMap(d.data(), d.id)));
      _setLoading(false);
    }, onError: (e) {
      _err(e);
      _setLoading(false);
    });
  }

  /// Detiene el stream actual
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ===== CRUD =====

  /// Agrega un media ya armado (por si lo creas manualmente).
  /// Normalmente subirás con FotoService y luego solo caerá por stream.
  Future<String?> add(String observacionId, PhotoMedia media, {bool toast = true}) async {
    try {
      final ref = await _db
          .collection('observaciones')
          .doc(observacionId)
          .collection('media')
          .add(media.toMap());
      if (toast) _msg('Foto agregada');
      return ref.id;
    } catch (e) {
      _err(e);
      return null;
    }
  }

  /// Parchea campos de un media (null -> FieldValue.delete()).
  Future<bool> patch(String observacionId, String mediaId, Map<String, dynamic> patch,
      {bool toast = true}) async {
    try {
      final data = Map<String, dynamic>.from(patch)
        ..updateAll((k, v) => v == null ? FieldValue.delete() : v);

      await _db
          .collection('observaciones')
          .doc(observacionId)
          .collection('media')
          .doc(mediaId)
          .update(data);

      if (toast) _msg('Cambios guardados');
      return true;
    } catch (e) {
      _err(e);
      return false;
    }
  }

  /// Elimina una foto
  Future<bool> delete(String observacionId, String mediaId, {bool toast = true}) async {
    try {
      await _db
          .collection('observaciones')
          .doc(observacionId)
          .collection('media')
          .doc(mediaId)
          .delete();
      if (toast) _msg('Foto eliminada');
      return true;
    } catch (e) {
      _err(e);
      return false;
    }
  }

  // ===== Atajos de negocio =====

  /// Actualizar veredicto de autenticidad/calidad y confianza
  Future<bool> setVerdict({
    required String observacionId,
    required String mediaId,
    String? authenticity, // MediaVerdict.genuine|suspect|manipulated|unknown
    String? quality,      // MediaVerdict.good|low|unusable
    double? confidence,   // 0..1
  }) {
    return patch(observacionId, mediaId, {
      if (authenticity != null) 'authenticity': authenticity,
      if (quality != null) 'quality': quality,
      if (confidence != null) 'confidence': confidence,
    });
  }

  /// Reemplaza por completo el arreglo de flags
  Future<bool> setFlags({
    required String observacionId,
    required String mediaId,
    required List<String> flags,
  }) {
    return patch(observacionId, mediaId, {'flags': flags});
  }

  /// Añade un flag si no existe
  Future<bool> addFlag({
    required String observacionId,
    required String mediaId,
    required String flag,
  }) async {
    try {
      final ref = _db
          .collection('observaciones')
          .doc(observacionId)
          .collection('media')
          .doc(mediaId);

      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final m = snap.data() ?? {};
        final current = (m['flags'] is List)
            ? (m['flags'] as List).whereType<String>().toList()
            : <String>[];
        if (!current.contains(flag)) current.add(flag);
        tx.update(ref, {'flags': current});
      });
      _msg('Flag agregado');
      return true;
    } catch (e) {
      _err(e);
      return false;
    }
  }

  /// Quita un flag si existe
  Future<bool> removeFlag({
    required String observacionId,
    required String mediaId,
    required String flag,
  }) async {
    try {
      final ref = _db
          .collection('observaciones')
          .doc(observacionId)
          .collection('media')
          .doc(mediaId);

      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final m = snap.data() ?? {};
        final current = (m['flags'] is List)
            ? (m['flags'] as List).whereType<String>().toList()
            : <String>[];
        current.remove(flag);
        tx.update(ref, {'flags': current});
      });
      _msg('Flag eliminado');
      return true;
    } catch (e) {
      _err(e);
      return false;
    }
  }
}
