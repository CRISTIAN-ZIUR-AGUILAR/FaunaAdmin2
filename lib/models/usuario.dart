import 'package:cloud_firestore/cloud_firestore.dart';

class Usuario {
  final String uid;
  final String nombreCompleto;
  final String correo;

  // Nombre simple (antes "formacion")
  final String ocupacion;
  final String nivelAcademico;
  final String area;

  final String estatus;
  final DateTime? fechaRegistro;

  /// Admin único del sistema (campo `is_admin` en Firestore)
  final bool isAdmin;

  const Usuario({
    required this.uid,
    required this.nombreCompleto,
    required this.correo,
    required this.ocupacion,
    required this.nivelAcademico,
    required this.area,
    required this.estatus,
    required this.fechaRegistro,
    required this.isAdmin,
  });

  factory Usuario.fromMap(Map<String, dynamic> m, String docId) {
    DateTime? _toDate(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString());
    }

    return Usuario(
      uid: docId,
      nombreCompleto: (m['nombre_completo'] as String?) ?? '',
      correo:        (m['correo']          as String?) ?? '',

      // Retrocompat
      ocupacion:     (m['ocupacion']       as String?) ?? (m['formacion'] as String?) ?? '',
      nivelAcademico:(m['nivel_academico'] as String?) ?? (m['nivel'] as String?) ?? '',
      area:          (m['area']            as String?) ?? (m['especialidad'] as String?) ?? '',

      estatus:       (m['estatus']         as String?) ?? '',
      fechaRegistro: _toDate(m['fecha_registro']),

      // Lee `is_admin` (y acepta 'isAdmin' por si acaso)
      isAdmin: (m['is_admin'] == true) || (m['isAdmin'] == true),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre_completo': nombreCompleto,
      'correo':          correo,
      'ocupacion':       ocupacion,
      'nivel_academico': nivelAcademico,
      'area':            area,
      'estatus':         estatus,
      if (fechaRegistro != null) 'fecha_registro': fechaRegistro,
      'is_admin':        isAdmin,
    };
  }

  Usuario copyWith({
    String? nombreCompleto,
    String? correo,
    String? ocupacion,
    String? nivelAcademico,
    String? area,
    String? estatus,
    DateTime? fechaRegistro,
    bool? isAdmin,
  }) {
    return Usuario(
      uid: uid,
      nombreCompleto: nombreCompleto ?? this.nombreCompleto,
      correo: correo ?? this.correo,
      ocupacion: ocupacion ?? this.ocupacion,
      nivelAcademico: nivelAcademico ?? this.nivelAcademico,
      area: area ?? this.area,
      estatus: estatus ?? this.estatus,
      fechaRegistro: fechaRegistro ?? this.fechaRegistro,
      isAdmin: isAdmin ?? this.isAdmin,
    );
  }
}
