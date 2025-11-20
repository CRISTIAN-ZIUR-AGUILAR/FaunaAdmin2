import 'dart:io' as io;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:faunadmin2/models/observacion.dart';

class DetalleObservacionLocalScreen extends StatelessWidget {
  final Observacion observacion;
  final String? baseDir;

  const DetalleObservacionLocalScreen({
    super.key,
    required this.observacion,
    this.baseDir,
  });

  // ========= Descubrir carpeta local si no llegó por args =========
  Future<String?> _computeBaseDirFallback() async {
    if (kIsWeb) return null;
    if (baseDir != null && baseDir!.isNotEmpty) return baseDir;

    // 1) Mejor pista disponible
    String? hint = observacion.capturaKey ?? observacion.id;
    if (hint == null || hint.trim().isEmpty) return null;
    hint = hint.trim();

    // 2) Remueve prefijo local:
    if (hint.startsWith('local:')) {
      hint = hint.substring('local:'.length);
    }

    // 3) Si luce como ruta absoluta -> úsala
    if (hint.startsWith('/') || hint.contains('/FaunaLocal/observaciones/')) {
      final dirPath = io.Directory(hint).existsSync()
          ? hint
          : io.Directory(p.dirname(hint)).existsSync()
          ? p.dirname(hint)
          : null;
      if (dirPath != null) {
        debugPrint('[DetalleLocal] fallback(baseDir from absolute)=$dirPath');
        return dirPath;
      }
    }

    // 4) Si no es ruta, asumimos nombre de carpeta dentro de Documents/...
    try {
      final docs = await getApplicationDocumentsDirectory();
      final candidate = io.Directory(
        p.join(docs.path, 'FaunaLocal', 'observaciones', hint),
      );
      if (await candidate.exists()) {
        debugPrint('[DetalleLocal] fallback(baseDir from docs)=${candidate.path}');
        return candidate.path;
      }

      // 5) Alternativa: External/Temp
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        final candidate2 = io.Directory(
          p.join(ext.path, 'FaunaLocal', 'observaciones', hint),
        );
        if (await candidate2.exists()) {
          debugPrint('[DetalleLocal] fallback(baseDir from external)=${candidate2.path}');
          return candidate2.path;
        }
      }
    } catch (e) {
      debugPrint('[DetalleLocal] fallback error: $e');
    }

    debugPrint('[DetalleLocal] fallback baseDir NOT FOUND for $hint');
    return null;
  }

  // ====== Soporte de imágenes ======
  static const _allowedExt = {
    '.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif', '.avif', '.bmp', '.gif',
  };

  bool _isAllowedFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return _allowedExt.contains(ext);
  }

  List<String> _resolverFotosAbs(Observacion obs, String? baseDir) {
    final base = (baseDir != null && baseDir.isNotEmpty) ? baseDir : null;
    final raw = List<String>.from(obs.mediaUrls);
    debugPrint('[DetalleLocal] baseDir=$base');
    debugPrint('[DetalleLocal] fotosRaw=$raw');

    bool isRemote(String pth) => pth.startsWith('http');

    String _fixOne(String pth) {
      var s = pth.trim();
      if (s.isEmpty) return s;

      // Quita prefijo file:// si viene así
      if (s.startsWith('file://')) {
        s = s.substring('file://'.length);
      }

      // Si ya es absoluta o remota, úsala tal cual
      if (isRemote(s) || s.startsWith('/')) return s;

      // Si es relativa y tenemos baseDir -> vuelve absoluta
      if (base != null) return p.join(base, s);

      // Relativa sin baseDir: se validará y filtrará después
      return s;
    }

    // 1) Normaliza y arma candidatos
    List<String> abs = [];
    for (final f in raw) {
      if (f.trim().isEmpty) continue;

      var candidate = _fixOne(f);

      // Si es local y no existe, intenta fallback con basename
      if (!isRemote(candidate) && !kIsWeb) {
        final file = io.File(candidate);
        if (!file.existsSync() && base != null) {
          final byBaseName = p.join(base, p.basename(candidate));
          if (io.File(byBaseName).existsSync()) {
            candidate = byBaseName;
          }
        }
      }

      abs.add(candidate);
    }

    // 2) Si venía vacío pero hay storage paths, intenta con sus basenames
    if (abs.isEmpty && base != null && obs.mediaStoragePaths.isNotEmpty) {
      final guessed = obs.mediaStoragePaths
          .map((sp) => p.basename(sp))
          .where((name) => name.trim().isNotEmpty)
          .map((name) => p.join(base, name))
          .toList();
      if (guessed.isNotEmpty) {
        abs = guessed;
        debugPrint('[DetalleLocal] usando mediaStoragePaths -> ${abs.length} fotos');
      }
    }

    // 3) Filtra locales inexistentes (no aplica a remotas ni Web)
    if (!kIsWeb) {
      abs = abs.where((path) {
        if (isRemote(path)) return true;
        return io.File(path).existsSync();
      }).toList();
    }

    // 4) Fallback final: escanear la carpeta si seguimos sin nada
    if (abs.isEmpty && base != null && !kIsWeb) {
      try {
        final dir = io.Directory(base);
        if (dir.existsSync()) {
          final files = dir
              .listSync()
              .whereType<io.File>()
              .where((f) => _isAllowedFile(f.path))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
          abs = files.map((f) => f.path).toList();
          debugPrint('[DetalleLocal] fallback scan -> ${abs.length} fotos');
        }
      } catch (e) {
        debugPrint('[DetalleLocal] scan error: $e');
      }
    }

    debugPrint('[DetalleLocal] fotosAbs=$abs');
    return abs;
  }

  // ====== Normalización de meta.json -> claves esperadas por Observacion.fromMap ======
  Map<String, dynamic> _normalizeLocalMeta(Map rawAny) {
    final raw = rawAny.map((k, v) => MapEntry(k.toString(), v));
    final m = <String, dynamic>{};

    dynamic _first(List<String> keys) {
      for (final k in keys) {
        final v = raw[k];
        if (v == null) continue;
        if (v is String && v.trim().isEmpty) continue;
        return v;
      }
      return null;
    }

    // Identidad / estado / proyecto / usuario
    m['id']            = _first(['id','obsId','observacionId']);
    final estado       = _first(['estado','status','state']);
    if (estado is String) m['estado'] = EstadosObs.normalize(estado);
    m['id_proyecto']   = _first(['id_proyecto','proyectoId','projectId']);
    m['uid_usuario']   = _first(['uid_usuario','uid','userId','autorUid']);
    m['id_categoria']  = _first(['id_categoria','categoriaId','categoryId']);

    // Captura
    m['fecha_captura']     = _first(['fecha_captura','fechaHora','fecha','capturedAt','captureDate']);
    m['edad_aproximada']   = _first(['edad_aproximada','edad','age']);

    // Especie (incluye respaldo y taxonomía)
    m['especie_nombre_cientifico'] = _first(['especie_nombre_cientifico','nombreEspecie','scientificName']);
    m['especie_nombre_comun']      = _first(['especie_nombre_comun','nombreComun','commonName']);
    m['especie_id']                = _first(['especie_id','taxonId','idTaxon']);
    m['especie_nombre_cientifico'] ??= _first(['especie_nombre']); // respaldo

    m['taxo_clase']   = _first(['taxo_clase','clase']);
    m['taxo_orden']   = _first(['taxo_orden','orden']);
    m['taxo_familia'] = _first(['taxo_familia','familia']);

    // Ubicación
    m['lugar_nombre'] = _first(['lugar_nombre','lugar','sitio','placeName']);
    m['lugar_tipo']   = _first(['lugar_tipo','tipoLugar','placeType']);
    m['municipio']    = _first(['municipio','municipality','county']);
    m['estado_pais']  = _first(['estado_pais','estado','state','region']);
    m['lat']          = _first(['lat','latitud','latitude']);
    m['lng']          = _first(['lng','longitud','lon','longitude']);
    m['altitud']      = _first(['altitud','altitude','elev','elevacion']);

    // Metadatos canónicos del municipio
    m['ubic_estado']   = _first(['ubic_estado','estado_canonico','estado_can','estadoCanonico']);
    m['ubic_region']   = _first(['ubic_region','region_canonica','regionCanonica']);
    m['ubic_distrito'] = _first(['ubic_distrito','distrito_canonico','distritoCanonico']);

    // Notas
    m['notas'] = _first(['notas','notes','observaciones','descripcion','description']);

    // Condición / rastro
    m['condicion_animal'] = _first(['condicion_animal','condicion','estadoAnimal','condition']);
    m['rastro_tipo']      = _first(['rastro_tipo','tipoRastro','trackType']);
    m['rastro_detalle']   = _first(['rastro_detalle','detalleRastro','trackDetail']);

    // Media
    final media = _first(['media_urls','fotos','media','imagenes','images']);
    if (media is List) {
      m['media_urls'] = media.map((e) => e?.toString() ?? '').toList();
    } else if (media is String && media.trim().isNotEmpty) {
      m['media_urls'] = media.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    // Nombres locales → media_urls (para que el resolutor las encuentre en baseDir)
    final mediaLocal = _first(['media_local_names','media_local','fotos_locales']);
    if (mediaLocal is List) {
      final list = mediaLocal.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
      if (list.isNotEmpty) {
        m['media_urls'] = list;
      }
    }

    m['cover_url']        = _first(['cover_url','cover','imagenPortada','imageCover','imageUrl','imagenUrl']);
    m['primary_media_id'] = _first(['primary_media_id','primary','firstMediaId']);

    // Auditoría / UI
    m['createdAt']        = _first(['createdAt','creado','fechaCreacion']);
    m['updatedAt']        = _first(['updatedAt','actualizado','fechaActualizacion']);
    m['autor_nombre']     = _first(['autor_nombre','autor','authorName']);
    m['proyecto_nombre']  = _first(['proyecto_nombre','proyecto','projectName']);
    m['categoria_nombre'] = _first(['categoria_nombre','categoria','categoryName']);

    // Clave de captura
    m['captura_key']      = _first(['captura_key','capturaKey','captureKey']);

    // Flujo opcional
    m['media_count']      = _first(['media_count','num_fotos','fotos_count']);
    m['ai_status']        = _first(['ai_status']);
    m['enviar_revision']  = _first(['enviar_revision']);
    // Limpieza
    m.removeWhere((k, v) {
      if (v == null) return true;
      if (v is String && v.trim().isEmpty) return true;
      if (v is List && v.isEmpty) return true;
      return false;
    });
    return m;
  }
  // Lee meta.json, normaliza y enriquece la Observacion (lo LOCAL tiene prioridad)
  Future<Observacion> _loadMetaAndEnrich(String? dir, Observacion original) async {
    if (kIsWeb || dir == null || dir.isEmpty) return original;
    try {
      final f = io.File(p.join(dir, 'meta.json'));
      if (await f.exists()) {
        final raw = jsonDecode(await f.readAsString());
        if (raw is Map) {
          final meta = _normalizeLocalMeta(raw);
          // 👇 PRIORIDAD A LO LOCAL:
          // Primero original, luego meta → si hay conflicto, gana el meta.json
          final merged = <String, dynamic>{...original.toMap(), ...meta};

          final id = original.id ?? meta['id']?.toString() ?? 'local';
          final enriched = Observacion.fromMap(merged, id);
          debugPrint('[DetalleLocal] meta.json leído + normalizado + fusionado');
          return enriched;
        }
      } else {
        debugPrint('[DetalleLocal] meta.json no existe en $dir');
      }
    } catch (e) {
      debugPrint('[DetalleLocal] meta.json error: $e');
    }
    return original;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _computeBaseDirFallback(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final dir = snap.data ?? baseDir;

        // Enriquecer con meta.json antes de renderizar UI
        return FutureBuilder<Observacion>(
          future: _loadMetaAndEnrich(dir, observacion),
          builder: (context, s2) {
            final obs = s2.data ?? observacion;

            final fotosAbs = _resolverFotosAbs(obs, dir);

            final titulo = obs.especieNombreCientifico
                ?? obs.especieNombreComun
                ?? obs.id
                ?? 'Observación local';

            final fechaTxt = (obs.fechaCaptura)?.toString() ?? '—';
            final lat = obs.lat?.toStringAsFixed(6) ?? '—';
            final lon = obs.lng?.toStringAsFixed(6) ?? '—';

            return Scaffold(
              appBar: AppBar(
                title: const Text('Observación (local)'),
                actions: const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Chip(label: Text('LOCAL'), visualDensity: VisualDensity.compact),
                  ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: DefaultTextStyle.merge(
                        style: Theme.of(context).textTheme.bodyMedium!,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(titulo, style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.schedule, size: 18),
                                const SizedBox(width: 8),
                                Text(fechaTxt),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.place, size: 18),
                                const SizedBox(width: 8),
                                Text('Lat: $lat  •  Lon: $lon'),
                              ],
                            ),
                            if (dir != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.folder, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      dir,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _FotosSection(fotosAbs: fotosAbs),
                  const SizedBox(height: 24),
                  _MetaSection(observacion: obs),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _FotosSection extends StatelessWidget {
  final List<String> fotosAbs;

  const _FotosSection({required this.fotosAbs});

  bool _isRemote(String p) => p.startsWith('http');

  @override
  Widget build(BuildContext context) {
    if (fotosAbs.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: const [
              Icon(Icons.photo_outlined),
              SizedBox(width: 12),
              Expanded(child: Text('Sin fotos en este borrador local.')),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fotos (${fotosAbs.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                final cross = c.maxWidth > 900 ? 4 : c.maxWidth > 600 ? 3 : 2;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: fotosAbs.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cross,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (_, i) {
                    final path = fotosAbs[i];
                    final isRemote = _isRemote(path);
                    return InkWell(
                      onTap: () {
                        showDialog(
                          context: context,
                          barrierColor: Colors.black.withOpacity(0.85),
                          builder: (_) => _PhotoViewer(path: path, isRemote: isRemote),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                          ),
                          child: isRemote
                              ? Image.network(
                            path,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                            const Center(child: Icon(Icons.broken_image_outlined)),
                          )
                              : kIsWeb
                              ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text(
                                'Archivo local (no visible en Web)',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                              : Image(
                            image: FileImage(io.File(path)),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoViewer extends StatelessWidget {
  final String path;
  final bool isRemote;

  const _PhotoViewer({required this.path, required this.isRemote});

  @override
  Widget build(BuildContext context) {
    Widget img;
    if (isRemote) {
      img = Image.network(path, fit: BoxFit.contain);
    } else {
      if (kIsWeb) {
        img = const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('No se puede mostrar un archivo local en Web.',
                textAlign: TextAlign.center),
          ),
        );
      } else {
        img = Image(image: FileImage(io.File(path)), fit: BoxFit.contain);
      }
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: Colors.transparent,
      child: Stack(
        alignment: Alignment.topRight,
        children: [
          InteractiveViewer(
            maxScale: 5,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 800),
              color: Colors.black,
              child: Center(child: img),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _MetaSection extends StatelessWidget {
  final Observacion observacion;

  const _MetaSection({required this.observacion});

  @override
  Widget build(BuildContext context) {
    final rows = <_KV>[];

    void add(String k, String? v) {
      if (v != null && v.trim().isNotEmpty) rows.add(_KV(k, v));
    }

    void addNum(String k, num? v) {
      if (v != null) rows.add(_KV(k, '$v'));
    }

    add('ID', observacion.id);
    add('Nombre científico', observacion.especieNombreCientifico);
    add('Nombre común', observacion.especieNombreComun);
    add('Municipio', observacion.municipio);
    add('Estado (país)', observacion.estadoPais);
    addNum('Altitud', observacion.altitud);
    add('Notas', observacion.notas);

    // ——— Extras útiles si tu modelo los expone ———
    add('Clase', observacion.taxoClase);
    add('Orden', observacion.taxoOrden);
    add('Familia', observacion.taxoFamilia);

    // Metadatos canónicos del municipio (si existen en el modelo)
    add('Estado (canónico)', observacion.ubicEstado);
    add('Región', observacion.ubicRegion);
    add('Distrito', observacion.ubicDistrito);

    add('Condición', observacion.condicionAnimal);
    add('Tipo de rastro', observacion.rastroTipo);
    add('Detalle de rastro', observacion.rastroDetalle);

    if (rows.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Metadatos', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...rows.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 160,
                    child: Text(
                      e.k,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e.v)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class _KV {
  final String k;
  final String v;
  _KV(this.k, this.v);
}

