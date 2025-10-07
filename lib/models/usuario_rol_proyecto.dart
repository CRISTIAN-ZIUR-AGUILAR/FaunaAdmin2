import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:faunadmin2/utils/constants.dart';

class UsuarioRolProyecto {
  /// ID del documento (snap.id)
  final String id;

  /// null => rol global (legacy). En la lógica actual, casi todo es “por proyecto”.
  final String? idProyecto;

  /// UID del usuario al que pertenece el vínculo
  final String uidUsuario;

  /// ID canónico del rol (ver Rol.* / RoleIds.*). Puede venir como int o string en Firestore.
  final int? idRol;

  /// Flags de estado (opcionalmente presentes en Firestore)
  final bool activo;        // default true
  final String estatus;     // 'aprobado' | 'pendiente' | 'activo' | ... (default 'aprobado')

  /// Metadata opcional
  final DateTime? createdAt;

  const UsuarioRolProyecto({
    required this.id,
    required this.idProyecto,
    required this.uidUsuario,
    required this.idRol,
    this.activo = true,
    this.estatus = 'aprobado',
    this.createdAt,
  });

  // ----------------- Helpers de parseo -----------------
  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  static String _normLower(dynamic v, {String fallback = 'aprobado'}) {
    final s = (v ?? fallback).toString();
    return s.isEmpty ? fallback : s.toLowerCase();
  }

  // ----------------- Constructores desde Firestore -----------------
  factory UsuarioRolProyecto.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snap) {
    final m = snap.data() ?? <String, dynamic>{};

    final idProyecto = (m[URPFields.idProyecto] ?? m['proyecto_id']) as String?;
    final uidUsuario = (m[URPFields.uidUsuario] ?? m['uid']) as String? ?? '';
    final idRol      = _toInt(m[URPFields.idRol] ?? m['rol'] ?? m['idRol']);

    final activo  = (m['activo'] ?? true) == true;
    final estatus = _normLower(m['estatus'], fallback: 'aprobado');
    final created = _toDate(m[URPFields.createdAt] ?? m['createdAt']);

    return UsuarioRolProyecto(
      id: snap.id,
      idProyecto: idProyecto,
      uidUsuario: uidUsuario,
      idRol: idRol,
      activo: activo,
      estatus: estatus,
      createdAt: created,
    );
  }

  /// Útil cuando ya tienes un `Map` y el id del doc.
  factory UsuarioRolProyecto.fromMap(Map<String, dynamic> m, String docId) {
    final idProyecto = (m[URPFields.idProyecto] ?? m['proyecto_id']) as String?;
    final uidUsuario = (m[URPFields.uidUsuario] ?? m['uid']) as String? ?? '';
    final idRol      = _toInt(m[URPFields.idRol] ?? m['rol'] ?? m['idRol']);

    final activo  = (m['activo'] ?? true) == true;
    final estatus = _normLower(m['estatus'], fallback: 'aprobado');
    final created = _toDate(m[URPFields.createdAt] ?? m['createdAt']);

    return UsuarioRolProyecto(
      id: docId,
      idProyecto: idProyecto,
      uidUsuario: uidUsuario,
      idRol: idRol,
      activo: activo,
      estatus: estatus,
      createdAt: created,
    );
  }

  // ----------------- Serialización -----------------
  Map<String, dynamic> toMap() {
    return {
      URPFields.idProyecto: idProyecto,
      URPFields.uidUsuario: uidUsuario,
      URPFields.idRol: idRol,
      'activo': activo,
      'estatus': estatus,
      if (createdAt != null) URPFields.createdAt: Timestamp.fromDate(createdAt!),
    };
  }

  // ----------------- Copy -----------------
  UsuarioRolProyecto copyWith({
    String? id,
    String? idProyecto,
    String? uidUsuario,
    int? idRol,
    bool? activo,
    String? estatus,
    DateTime? createdAt,
  }) {
    return UsuarioRolProyecto(
      id: id ?? this.id,
      idProyecto: idProyecto ?? this.idProyecto,
      uidUsuario: uidUsuario ?? this.uidUsuario,
      idRol: idRol ?? this.idRol,
      activo: activo ?? this.activo,
      estatus: estatus ?? this.estatus,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // ----------------- Getters de conveniencia -----------------
  bool get isActive => activo;
  bool get isGlobal => idProyecto == null || idProyecto!.isEmpty;

  bool get isAdmin       => idRol == RoleIds.admin;
  bool get isSupervisor  => idRol == RoleIds.supervisor;
  bool get isDueno       => idRol == RoleIds.dueno;
  bool get isColaborador => idRol == RoleIds.colaborador;
  bool get isRecolector  => idRol == RoleIds.recolector;

  String get rolLabel => kRoleLabels[idRol ?? -1] ?? 'ROL ${idRol ?? "?"}';

  @override
  String toString() =>
      'URP{id=$id, uid=$uidUsuario, rol=$idRol, proy=$idProyecto, activo=$activo, estatus=$estatus}';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UsuarioRolProyecto &&
        other.id == id &&
        other.uidUsuario == uidUsuario &&
        other.idRol == idRol &&
        other.idProyecto == idProyecto &&
        other.activo == activo &&
        other.estatus == estatus;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      uidUsuario.hashCode ^
      (idRol ?? -1).hashCode ^
      (idProyecto?.hashCode ?? 0) ^
      activo.hashCode ^
      estatus.hashCode;
}
