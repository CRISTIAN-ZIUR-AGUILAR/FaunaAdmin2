// lib/models/especie.dart
class Especie {
  final String id;                     // docId en Firestore (sugerido: nombre_cientifico normalizado con guiones bajos)
  final String nombreCientifico;
  final List<String> nombresComunes;   // puede estar vacío
  final String? reino;
  final String? filo;
  final String? claseTax;              // 'clase' es palabra reservada en Dart, usamos claseTax
  final String? orden;
  final String? familia;
  final String? genero;
  final String? especie;
  final bool? endemicaMx;
  final String? estatusIucn;
  final List<String> sinonimos;
  final List<String> habitat;
  final String normName;               // sin acentos/minúsculas
  final List<String> normComunes;      // idem

  const Especie({
    required this.id,
    required this.nombreCientifico,
    required this.nombresComunes,
    this.reino,
    this.filo,
    this.claseTax,
    this.orden,
    this.familia,
    this.genero,
    this.especie,
    this.endemicaMx,
    this.estatusIucn,
    this.sinonimos = const [],
    this.habitat = const [],
    required this.normName,
    required this.normComunes,
  });

  factory Especie.fromMap(Map<String, dynamic> d, String id) {
    List<String> _list(dynamic v) =>
        (v is List ? v : []).map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList();

    return Especie(
      id: id,
      nombreCientifico: (d['nombre_cientifico'] ?? '').toString(),
      nombresComunes: _list(d['nombre_comun']),
      reino: d['reino'],
      filo: d['filo'],
      claseTax: d['clase'],
      orden: d['orden'],
      familia: d['familia'],
      genero: d['genero'],
      especie: d['especie'],
      endemicaMx: d['endemica_mx'],
      estatusIucn: d['estatus_iucn'],
      sinonimos: _list(d['sinonimos']),
      habitat: _list(d['habitat']),
      normName: (d['norm_name'] ?? '').toString(),
      normComunes: _list(d['norm_comunes']),
    );
  }

  Map<String, dynamic> toMap() => {
    'nombre_cientifico': nombreCientifico,
    'nombre_comun': nombresComunes,
    'reino': reino,
    'filo': filo,
    'clase': claseTax,
    'orden': orden,
    'familia': familia,
    'genero': genero,
    'especie': especie,
    'endemica_mx': endemicaMx,
    'estatus_iucn': estatusIucn,
    'sinonimos': sinonimos,
    'habitat': habitat,
    'norm_name': normName,
    'norm_comunes': normComunes,
  }..removeWhere((k, v) => v == null);
}
