// lib/utils/categorias_utils.dart
//
// Utilidades para generar y asegurar claves cortas (siglas) de categorías.
// - `claveBaseDesdeNombre(nombre)` genera una clave base a partir del nombre.
// - `claveUnica(base, existentes)` garantiza que la clave resultante no colisione
//    con otras ya existentes (añadiendo sufijos alfabéticos o numéricos).

import 'package:flutter/cupertino.dart';

/// Normaliza texto para comparaciones: quita acentos/diacríticos, recorta y pasa a MAYÚSCULAS.
String _normKey(String s) {
  const map = {
    'Á': 'A', 'À': 'A', 'Â': 'A', 'Ä': 'A', 'Ã': 'A', 'Å': 'A',
    'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
    'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I',
    'Ó': 'O', 'Ò': 'O', 'Ô': 'O', 'Ö': 'O', 'Õ': 'O',
    'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U',
    'Ñ': 'N',
  };
  final up = s.trim().toUpperCase();
  final sb = StringBuffer();
  for (final ch in up.characters) {
    sb.write(map[ch] ?? ch);
  }
  return sb.toString().replaceAll(RegExp(r'\s+'), ' ');
}

/// Palabras a ignorar al crear siglas (artículos, preposiciones, etc.)
const Set<String> _stop = {
  'DE', 'DEL', 'LA', 'EL', 'LOS', 'LAS', 'Y', 'EN', 'PARA', 'POR', 'A',
  // números romanos comunes que no aportan a la sigla
  'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X',
};

/// Mapeo de nombres base -> clave fija (inborrables).
/// Se comparan usando `_normKey`, por lo que soporta acentos o sin acentos.
const Map<String, String> _baseNombreAClave = {
  'ACTIVIDADES COMPLEMENTARIAS': 'AC',
  'ECOLOGIA II': 'EC',                // soporta "Ecología II" o "Ecologia II"
  'TALLER DE FAUNA': 'TF',
  'RESIDENCIA': 'RS',
  'PROYECTO DE INVESTIGACION': 'PI',  // soporta "Investigación" o "Investigacion"
  'OTRO': 'OT',
};

/// Genera una sigla a partir del nombre (2 a 4 caracteres preferentemente).
String _siglaDeNombre(String nombre) {
  final norm = _normKey(nombre);
  final partes = norm.split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty && !_stop.contains(p))
      .toList();

  // 1) Acrónimo por primeras letras
  if (partes.isNotEmpty) {
    final acr = partes.map((p) => p[0]).join();
    if (acr.length >= 2 && acr.length <= 4) return acr;
    if (acr.length > 4) return acr.substring(0, 4);
  }

  // 2) Fallback: primeras letras del string normalizado sin espacios
  final compact = norm.replaceAll(' ', '');
  final take = compact.length >= 2 ? (compact.length >= 4 ? 4 : compact.length) : compact.length;
  return compact.substring(0, take);
}

/// Devuelve la clave **base** para un nombre.
/// - Si el nombre está en el catálogo de fijas, regresa la fija (AC, EC, TF, RS, PI, OT).
/// - En caso contrario, genera una sigla por heurística.
String claveBaseDesdeNombre(String nombre) {
  final k = _normKey(nombre);
  // normalizar llaves del mapa para comparar sin acentos
  for (final entry in _baseNombreAClave.entries) {
    if (_normKey(entry.key) == k) return entry.value;
  }
  return _siglaDeNombre(nombre);
}

/// Iterador de sufijos alfabéticos: A..Z, AA..ZZ, AAA..ZZZ
Iterable<String> _alphaSuffixes() sync* {
  const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  // 1 letra
  for (int i = 0; i < letters.length; i++) {
    yield letters[i];
  }
  // 2 letras
  for (int i = 0; i < letters.length; i++) {
    for (int j = 0; j < letters.length; j++) {
      yield '${letters[i]}${letters[j]}';
    }
  }
  // 3 letras
  for (int i = 0; i < letters.length; i++) {
    for (int j = 0; j < letters.length; j++) {
      for (int k = 0; k < letters.length; k++) {
        yield '${letters[i]}${letters[j]}${letters[k]}';
      }
    }
  }
}

/// Asegura que la clave no colisione con `existentes`.
/// - Si `base` NO está en `existentes`, se devuelve tal cual.
/// - Si SÍ está, se prueban sufijos A, B, ..., Z, AA, AB, ..., y al final 1, 2, 3...
String claveUnica(String base, Set<String> existentes) {
  String normBase = _normKey(base).replaceAll(' ', '');
  final upperSet = existentes.map((e) => _normKey(e).replaceAll(' ', '')).toSet();

  if (!upperSet.contains(normBase)) return normBase;

  for (final s in _alphaSuffixes()) {
    final cand = '$normBase$s';
    if (!upperSet.contains(cand)) return cand;
  }

  // Fallback numérico si se agotaran los sufijos alfabéticos (muy improbable)
  int i = 1;
  while (upperSet.contains('$normBase$i')) {
    i++;
  }
  return '$normBase$i';
}
