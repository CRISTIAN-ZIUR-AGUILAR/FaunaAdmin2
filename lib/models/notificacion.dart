// lib/models/notificacion.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Modelo base para notificaciones en la app.
/// Un doc típico en /notificaciones:
/// {
///   uid: "USER_ID",
///   proyectoId: "ABC123",        // opcional
///   obsId: "OBS123",             // opcional
///   tipo: "obs.aprobada",        // clave para lógica/colores
///   nivel: "success",            // 'success' | 'warning' | 'info' | 'error'
///   titulo: "Observación aprobada",
///   mensaje: "La obs #OBS123 fue aprobada.",
///   leida: false,
///   createdAt: <serverTimestamp>,
///   meta: { ... }                // opcional
/// }
class Notificacion {
  final String id;
  final String? uid;
  final String? proyectoId;
  final String? obsId;
  final String tipo;
  final String nivel;
  final String titulo;
  final String mensaje;
  final bool leida;
  final DateTime createdAt;
  final Map<String, dynamic>? meta;

  const Notificacion({
    required this.id,
    this.uid,
    this.proyectoId,
    this.obsId,
    required this.tipo,
    required this.nivel,
    required this.titulo,
    required this.mensaje,
    required this.leida,
    required this.createdAt,
    this.meta,
  });

  /// Crea desde un DocumentSnapshot (colección `notificaciones`)
  factory Notificacion.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final ts = d['createdAt'];

    DateTime _parseCreatedAt(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed;
      }
      // Fallback seguro si el campo aún no llegó por latency-compensation
      return DateTime.now();
    }

    return Notificacion(
      id: doc.id,
      uid: d['uid'] as String?,
      proyectoId: d['proyectoId'] as String?,
      obsId: d['obsId'] as String?,
      tipo: (d['tipo'] as String?)?.trim() ?? 'info',
      nivel: (d['nivel'] as String?)?.trim() ?? 'info',
      titulo: (d['titulo'] as String?)?.trim() ?? '',
      mensaje: (d['mensaje'] as String?)?.trim() ?? '',
      leida: (d['leida'] as bool?) ?? false,
      createdAt: _parseCreatedAt(ts),
      meta: (d['meta'] is Map) ? Map<String, dynamic>.from(d['meta'] as Map) : null,
    );
  }

  /// Útil si necesitas construir una notificación local antes de persistirla
  Map<String, dynamic> toMapForCreate() {
    return {
      'uid': uid,
      'proyectoId': proyectoId,
      'obsId': obsId,
      'tipo': tipo,
      'nivel': nivel,
      'titulo': titulo,
      'mensaje': mensaje,
      'leida': leida,
      'createdAt': FieldValue.serverTimestamp(),
      'meta': meta,
    };
  }

  Notificacion copyWith({
    String? id,
    String? uid,
    String? proyectoId,
    String? obsId,
    String? tipo,
    String? nivel,
    String? titulo,
    String? mensaje,
    bool? leida,
    DateTime? createdAt,
    Map<String, dynamic>? meta,
  }) {
    return Notificacion(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      proyectoId: proyectoId ?? this.proyectoId,
      obsId: obsId ?? this.obsId,
      tipo: tipo ?? this.tipo,
      nivel: nivel ?? this.nivel,
      titulo: titulo ?? this.titulo,
      mensaje: mensaje ?? this.mensaje,
      leida: leida ?? this.leida,
      createdAt: createdAt ?? this.createdAt,
      meta: meta ?? this.meta,
    );
  }
}

