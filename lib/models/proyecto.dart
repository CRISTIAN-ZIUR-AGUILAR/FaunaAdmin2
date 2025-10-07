// lib/models/proyecto.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Proyecto {
  /// ID del documento en Firestore (puede ser null al crear)
  final String? id;

  // Básicos
  final String nombre;
  final String descripcion;

  // Fechas (opcionales)
  final DateTime? fechaInicio;
  final DateTime? fechaFin;

  // Categoría (denormalizada)
  final int? idCategoria;
  final String? categoriaNombre;

  // Otros (opcionales)
  final bool? activo;
  final String? uidDueno;

  /// 👇 NUEVO: supervisor asignado por admin (uid del usuario)
  final String? uidSupervisor;

  Proyecto({
    required this.id,
    required this.nombre,
    required this.descripcion,
    this.fechaInicio,
    this.fechaFin,
    this.idCategoria,
    this.categoriaNombre,
    this.activo,
    this.uidDueno,
    this.uidSupervisor, // nuevo
  });

  factory Proyecto.fromMap(Map<String, dynamic> m, String id) {
    DateTime? _ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    bool? _bool(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      return null;
    }

    return Proyecto(
      id: id,
      nombre: (m['nombre'] as String?)?.trim() ?? '',
      descripcion: (m['descripcion'] as String?)?.trim() ?? '',
      fechaInicio: _ts(m['fecha_inicio'] ?? m['fechaInicio']),
      fechaFin: _ts(m['fecha_fin'] ?? m['fechaFin']),
      idCategoria: (m['id_categoria'] as num?)?.toInt(),
      categoriaNombre: (m['categoria_nombre'] as String?)?.trim(),
      activo: _bool(m['activo']),
      uidDueno: (m['uid_dueno'] as String?),
      uidSupervisor: (m['uid_supervisor'] as String?), // nuevo
    );
  }

  Map<String, dynamic> toMap() {
    final data = <String, dynamic>{
      'nombre': nombre.trim(),
      'descripcion': descripcion.trim(),
    };
    if (fechaInicio != null) data['fecha_inicio'] = fechaInicio;
    if (fechaFin != null) data['fecha_fin'] = fechaFin;
    if (idCategoria != null) data['id_categoria'] = idCategoria;
    if ((categoriaNombre ?? '').trim().isNotEmpty) {
      data['categoria_nombre'] = categoriaNombre!.trim();
    }
    if (activo != null) data['activo'] = activo;
    if ((uidDueno ?? '').isNotEmpty) data['uid_dueno'] = uidDueno;
    if ((uidSupervisor ?? '').isNotEmpty) {
      data['uid_supervisor'] = uidSupervisor; // nuevo
    }
    return data;
  }

  Proyecto copyWith({
    String? id,
    String? nombre,
    String? descripcion,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    int? idCategoria,
    String? categoriaNombre,
    bool? activo,
    String? uidDueno,
    String? uidSupervisor, // nuevo
  }) {
    return Proyecto(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      fechaInicio: fechaInicio ?? this.fechaInicio,
      fechaFin: fechaFin ?? this.fechaFin,
      idCategoria: idCategoria ?? this.idCategoria,
      categoriaNombre: categoriaNombre ?? this.categoriaNombre,
      activo: activo ?? this.activo,
      uidDueno: uidDueno ?? this.uidDueno,
      uidSupervisor: uidSupervisor ?? this.uidSupervisor,
    );
  }
}
