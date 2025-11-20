// lib/services/local_file_storage.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class LocalFileStorage {
  LocalFileStorage._();
  static final LocalFileStorage instance = LocalFileStorage._();

  final _uuid = const Uuid();

  // =========================
  // Paths base
  // =========================
  Future<Directory> _getRoot() async {
    if (kIsWeb) {
      throw UnsupportedError('Almacenamiento local no disponible en Web.');
    }
    // Preferimos Documents; si algo falla, caemos a External o, en última instancia, a Temp.
    Directory base;
    try {
      base = await getApplicationDocumentsDirectory(); // no-null
    } catch (_) {
      base = (await getExternalStorageDirectory()) ?? await getTemporaryDirectory();
    }
    final root = Directory('${base.path}/FaunaLocal');
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }
  Future<Directory> _getObsDir() async {
    final root = await _getRoot();
    final dir = Directory('${root.path}/observaciones');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
  String _stamp() {
    final d = DateTime.now();
    String t(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${t(d.month)}${t(d.day)}_${t(d.hour)}${t(d.minute)}${t(d.second)}';
  }

  String _safeExt(String path) {
    final ext = path.split('.').last.toLowerCase();
    if (ext == 'jpg' || ext == 'jpeg' || ext == 'png') return ext;
    return 'jpg';
  }
  // =========================
  // Guardar observación completa (meta + 1..4 fotos)
  // =========================
  /// Guarda OBSERVACIÓN con múltiples fotos (1..4) y meta completo.
  /// - Crea: FaunaLocal/observaciones/<stamp_uuid8>/
  /// - Copia fotos: foto_1.<ext> .. foto_4.<ext>
  /// - Escribe meta.json y mete control local.
  /// [idProyecto] y [uidUsuario] son opcionales; si se pasan, sobrescriben
  /// valores presentes en [meta] bajo las claves "id_proyecto" y "uid_usuario".
  Future<Directory> guardarObservacionFull({
    required Map<String, dynamic> meta,
    required List<File> fotos, // 1..4
    String? idProyecto,
    String? uidUsuario,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Guardar observación local no disponible en Web.');
    }
    if (fotos.isEmpty) {
      throw ArgumentError('Al menos 1 foto es requerida.');
    }

    final fotosUsar = fotos.take(4).toList();
    final obsDir = await _getObsDir();
    final idLocal = '${_stamp()}_${_uuid.v4().substring(0, 8)}';
    final folder = Directory('${obsDir.path}/$idLocal');
    await folder.create(recursive: true);

    // Copiar fotos preservando extensión válida
    final nombres = <String>[];
    for (int i = 0; i < fotosUsar.length; i++) {
      final src = fotosUsar[i];
      final ext = _safeExt(src.path);
      final dest = File('${folder.path}/foto_${i + 1}.$ext');
      await src.copy(dest.path);
      nombres.add('foto_${i + 1}.$ext');
    }

    // Meta de salida (no mutamos el mapa original)
    final out = Map<String, dynamic>.from(meta);

    // Campos locales fijos
    out['id_local'] = idLocal;
    out['fotos'] = nombres; // nombres locales en carpeta
    out['created_local_at'] = DateTime.now().toUtc().toIso8601String();
    out['updated_local_at'] = out['updated_local_at'] ?? out['created_local_at'];
    // Cola de sincronización local
    // READY => pendiente de subir; SYNCED => subido; otros estados compatibles.
    out['status'] = (out['status'] ?? 'READY').toString().toUpperCase();
    // El sync escribirá remote_id cuando suba; lo dejamos explícitamente null si no existe
    out['remote_id'] = out.containsKey('remote_id') ? out['remote_id'] : null;

    // Normaliza proyecto/autor (parámetros tienen prioridad)
    final idProyectoFinal = (idProyecto ?? out['id_proyecto'] ?? '').toString();
    final uidUsuarioFinal = (uidUsuario ?? out['uid_usuario'])?.toString();

    out['id_proyecto'] = idProyectoFinal; // "" o id real
    if (uidUsuarioFinal != null && uidUsuarioFinal.isNotEmpty) {
      out['uid_usuario'] = uidUsuarioFinal;
    }

    final metaFile = File('${folder.path}/meta.json');
    await metaFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(out),
      flush: true,
    );

    return folder;
  }

  // =========================
  // Lectura / listado / edición
  // =========================

  /// Lista directorios de observaciones locales, **más recientes primero**.
  Future<List<Directory>> listarObservaciones() async {
    if (kIsWeb) return <Directory>[];
    final obsDir = await _getObsDir();
    if (!await obsDir.exists()) return <Directory>[];
    final list = obsDir
        .listSync(followLinks: false)
        .whereType<Directory>()
        .toList();

    // Orden por fecha de cambio (recientes primero). Si falla, por nombre desc.
    list.sort((a, b) {
      try {
        final ta = a.statSync().changed;
        final tb = b.statSync().changed;
        return tb.compareTo(ta);
      } catch (_) {
        return b.path.compareTo(a.path);
      }
    });
    return list;
  }

  Future<Map<String, dynamic>?> leerMeta(Directory carpeta) async {
    final file = File('${carpeta.path}/meta.json');
    if (!await file.exists()) return null;
    final txt = await file.readAsString();
    return json.decode(txt) as Map<String, dynamic>;
  }

  Future<void> actualizarStatus(
      Directory carpeta,
      String status, {
        String? remoteId,
      }) async {
    final file = File('${carpeta.path}/meta.json');
    if (!await file.exists()) return;
    final data = json.decode(await file.readAsString()) as Map<String, dynamic>;
    data['status'] = status.toUpperCase();
    if (remoteId != null) data['remote_id'] = remoteId;
    data['updated_local_at'] = DateTime.now().toUtc().toIso8601String();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
  }

  /// Lista archivos de foto dentro de la carpeta (jpg/jpeg/png), ordenados por nombre.
  Future<List<File>> listarFotos(Directory carpeta) async {
    final files = <File>[];
    await for (final e in carpeta.list(recursive: false, followLinks: false)) {
      if (e is File) {
        final n = e.path.toLowerCase();
        if (n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png')) {
          files.add(e);
        }
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  /// Elimina la carpeta completa de la observación
  Future<void> eliminarObservacionDir(Directory carpeta) async {
    if (await carpeta.exists()) {
      await carpeta.delete(recursive: true);
    }
  }

  /// Parcha meta.json (null => elimina la clave). Mantiene en cola de sync.
  Future<void> patchMeta(Directory carpeta, Map<String, dynamic> patch) async {
    final file = File('${carpeta.path}/meta.json');
    if (!await file.exists()) return;
    final data = json.decode(await file.readAsString()) as Map<String, dynamic>;

    patch.forEach((k, v) {
      if (v == null) {
        data.remove(k);
      } else {
        data[k] = v;
      }
    });

    data['status'] = (data['status'] ?? 'READY').toString().toUpperCase();
    data['updated_local_at'] = DateTime.now().toUtc().toIso8601String();

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
  }

  // =========================
  // Utilidades
  // =========================

  /// Busca una carpeta por su id_local (útil para abrir/editar offline).
  Future<Directory?> findByLocalId(String idLocal) async {
    final dirs = await listarObservaciones();
    for (final d in dirs) {
      final meta = await leerMeta(d);
      if (meta != null && meta['id_local'] == idLocal) return d;
    }
    return null;
  }

  /// Añade una foto a la carpeta y actualiza meta.json (mantiene extensión).
  Future<void> addLocalPhoto(Directory carpeta, File nuevaFoto) async {
    final existentes = await listarFotos(carpeta);
    final n = existentes.length + 1;
    final ext = _safeExt(nuevaFoto.path);
    final dest = File('${carpeta.path}/foto_$n.$ext');
    await nuevaFoto.copy(dest.path);

    final meta = await leerMeta(carpeta) ?? <String, dynamic>{};
    final list = (meta['fotos'] is List)
        ? List<String>.from(meta['fotos'])
        : <String>[];
    list.add('foto_$n.$ext');

    await patchMeta(carpeta, {'fotos': list});
  }

  /// Quita una foto por nombre y actualiza meta.json.
  Future<void> removeLocalPhoto(Directory carpeta, String fileName) async {
    final f = File('${carpeta.path}/$fileName');
    if (await f.exists()) {
      await f.delete();
    }
    final meta = await leerMeta(carpeta) ?? <String, dynamic>{};
    final list = (meta['fotos'] is List)
        ? List<String>.from(meta['fotos'])
        : <String>[];

    list.remove(fileName);
    await patchMeta(carpeta, {'fotos': list});
  }
}
