// lib/models/categoria.dart
class Categoria {
  final int id;
  final String nombre;
  final String clave;
  final bool isProtected; // ← NUEVO: indica si es inborrable

  Categoria({
    required this.id,
    required this.nombre,
    required this.clave,
    this.isProtected = false,
  });

  factory Categoria.fromMap(Map<String, dynamic> m) => Categoria(
    id: (m['id_categoria'] as num?)?.toInt() ?? 0,
    nombre: (m['nombre'] as String?)?.trim() ?? '',
    clave: ((m['clave'] as String?) ?? '').trim().toUpperCase(),
    isProtected: (m['is_protected'] as bool?) ?? false,
  );

  Map<String, dynamic> toMap() => {
    'id_categoria': id,
    'nombre': nombre,
    'clave': clave,
    'is_protected': isProtected,
  };

  Categoria copyWith({
    int? id,
    String? nombre,
    String? clave,
    bool? isProtected,
  }) =>
      Categoria(
        id: id ?? this.id,
        nombre: nombre ?? this.nombre,
        clave: clave ?? this.clave,
        isProtected: isProtected ?? this.isProtected,
      );
}

