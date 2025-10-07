// lib/models/rol.dart
class Rol {
  final int id;
  final String descripcion;

  // IDs de tu catálogo
  static const int admin         = 1;
  static const int supervisor    = 2;
  static const int recolector    = 3;
  static const int duenoProyecto = 4;
  static const int colaborador   = 5;

  // Aliases de compatibilidad (para evitar cambios en otras partes del código)
  static const int adminGlobal = admin;
  static const int dueno       = duenoProyecto;
  static const int collector   = recolector;

  const Rol({
    required this.id,
    required this.descripcion,
  });

  factory Rol.fromMap(Map<String, dynamic> m) {
    // Soporta 'id_rol' o 'id'
    final rawId = m['id_rol'] ?? m['id'];
    final id = rawId is int ? rawId : int.tryParse('$rawId') ?? 0;

    // Soporta 'descripcion', 'rol_nombre' o 'nombre'
    final desc = (m['descripcion'] ?? m['rol_nombre'] ?? m['nombre'])
        ?.toString()
        .trim() ??
        '';

    return Rol(id: id, descripcion: desc);
  }

  Map<String, dynamic> toMap() => {
    'id_rol': id,
    'descripcion': descripcion,
    // Incluimos también 'rol_nombre' para compatibilidad
    'rol_nombre': descripcion,
  };
}
