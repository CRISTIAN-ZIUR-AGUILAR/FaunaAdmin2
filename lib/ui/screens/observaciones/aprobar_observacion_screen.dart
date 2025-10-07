// lib/ui/screens/observaciones/aprobar_observacion_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:faunadmin2/models/observacion.dart';
import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/providers/observacion_provider.dart';
import 'package:faunadmin2/services/permisos_service.dart';

// ✅ Notificaciones (modelo/servicio/constantes)
import 'package:faunadmin2/models/notificacion.dart'; // (lo usas para tipos locales si hiciera falta)
import 'package:faunadmin2/services/notificacion_service.dart';
import 'package:faunadmin2/utils/notificaciones_constants.dart';

// ✅ NUEVO: para resolver URLs y cachear imágenes
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AprobarObservacionScreen extends StatefulWidget {
  final String observacionId;
  const AprobarObservacionScreen({super.key, required this.observacionId});

  @override
  State<AprobarObservacionScreen> createState() =>
      _AprobarObservacionScreenState();
}

class _AprobarObservacionScreenState extends State<AprobarObservacionScreen> {
  final _motivoCtrl = TextEditingController();
  bool _working = false;

  final _notifSvc = NotificacionService();

  @override
  void dispose() {
    _motivoCtrl.dispose();
    super.dispose();
  }

  /// Normaliza URLs v0 de Firebase Storage cuando el bucket quedó con ".firebasestorage.app"
  String _sanitizeFirebaseUrl(String url) {
    if (url.contains('.firebasestorage.app')) {
      return url.replaceFirst('.firebasestorage.app', '.appspot.com');
    }
    return url;
  }

  // ====== HELPERS PARA URLS DE IMAGEN ======

  /// Normaliza dominios *.firebasestorage.app → *.appspot.com
  String _sanitizeFirebaseHost(String url) {
    if (url.contains('.firebasestorage.app')) {
      return url.replaceFirst('.firebasestorage.app', '.appspot.com');
    }
    return url;
  }

  /// Devuelve una URL descargable (https) a partir de:
  /// - gs://bucket/path
  /// - https://... (corrige host y bucket en el path si traen .firebasestorage.app,
  ///   e intenta reconstruir por StorageRef si falta token/alt=media)
  /// - rutas simples tipo "fotos/2025/L/archivo.jpg"
  Future<String> _ensureDownloadUrl(String raw) async {
    if (raw.isEmpty) return raw;

    // A) gs://bucket/path → getDownloadURL()
    if (raw.startsWith('gs://')) {
      final ref = FirebaseStorage.instance.refFromURL(raw);
      return await ref.getDownloadURL();
    }

    // B) http(s)://
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      var url = raw;

      // 1) Normaliza host si trae ".firebasestorage.app"
      if (url.contains('.firebasestorage.app')) {
        url = url.replaceFirst('.firebasestorage.app', '.appspot.com');
      }

      // 2) Si el *bucket* dentro del path también trae ".firebasestorage.app", cámbialo
      //    Ej: .../v0/b/<bucket>.firebasestorage.app/o/... → .../v0/b/<bucket>.appspot.com/o/...
      final bucketInPath = RegExp(r'/v0/b/([^/]+)/o/');
      final m = bucketInPath.firstMatch(url);
      if (m != null) {
        final bucket = m.group(1)!;
        if (bucket.endsWith('.firebasestorage.app')) {
          final fixed = bucket.replaceFirst('.firebasestorage.app', '.appspot.com');
          url = url.replaceFirst('/v0/b/$bucket/o/', '/v0/b/$fixed/o/');
        }
      }

      // 3) Si es GCS y NO trae token ni alt=media, intenta reconstruir por Storage Ref
      final uri = Uri.tryParse(url);
      final isGcs = url.contains('firebasestorage.googleapis.com') || url.contains('appspot.com');
      final hasToken = uri?.queryParameters.containsKey('token') ?? false;
      final hasAltMedia = uri?.queryParameters['alt'] == 'media';

      if (isGcs && (!hasToken && !hasAltMedia)) {
        try {
          if (uri != null && uri.pathSegments.contains('o')) {
            final oIndex = uri.pathSegments.indexOf('o');
            if (oIndex >= 0 && oIndex + 1 < uri.pathSegments.length) {
              final encoded = uri.pathSegments[oIndex + 1];
              final decodedPath = Uri.decodeFull(encoded);
              final ref = FirebaseStorage.instance.ref(decodedPath);
              return await ref.getDownloadURL();
            }
          }
        } catch (_) {/* fallback */}
      }

      return url;
    }

    // C) RUTA SIMPLE tipo "fotos/2025/L/archivo.jpg" → getDownloadURL()
    try {
      final ref = FirebaseStorage.instance.ref(raw);
      return await ref.getDownloadURL();
    } catch (_) {
      return raw;
    }
  }

  /// Etiqueta legible para notificaciones (sin IDs)
  String _labelObs(Observacion o) {
    final lugar = (o.lugarNombre?.trim().isNotEmpty ?? false)
        ? o.lugarNombre!.trim()
        : (o.municipio?.trim().isNotEmpty ?? false)
        ? o.municipio!.trim()
        : 'observación';
    final fecha = _fmtFecha(o.fechaCaptura);
    return '$lugar · $fecha';
  }

  /// Wrapper para ejecutar una acción de provider y (si aplica) emitir notificación
  Future<void> _runAction({
    required Future<bool> Function() call,
    required String okMsg,
    Future<void> Function()? onOk,
  }) async {
    if (_working) return;
    setState(() => _working = true);
    final prov = context.read<ObservacionProvider>();

    try {
      final ok = await call();
      if (!mounted) return;
      setState(() => _working = false);

      final msg = ok ? okMsg : (prov.lastError ?? 'No se pudo completar la acción');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

      if (ok && onOk != null) {
        await onOk();
      }

      if (ok) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final permisos = PermisosService(auth);

    // Stream del doc + data cruda (para media_urls)
    final stream = FirebaseFirestore.instance
        .collection('observaciones')
        .doc(widget.observacionId)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Revisión de observación')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists || snap.data!.data() == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No se encontró la observación.'),
              ),
            );
          }

          final raw = snap.data!.data()!;
          final obs = Observacion.fromMap(raw, snap.data!.id);

          // ---------- QUIÉN PUEDE APROBAR ----------
          final selected = auth.selectedRolProyecto;
          final sameProject = (obs.idProyecto != null &&
              obs.idProyecto!.isNotEmpty &&
              selected?.idProyecto == obs.idProyecto);

          // Regla final:
          // - Admin / Admin único => siempre
          // - Supervisor o Dueño del mismo proyecto => siempre y que no sea el autor
          // - Nunca el autor (salvo que sea admin)
          final esAdmin = auth.isAdmin || permisos.isAdminUnico;
          final supervisorODuenoMismoProyecto =
              sameProject && (permisos.isSupervisorEnContexto || permisos.isDuenoEnContexto);
          final soyAutor = obs.uidUsuario == auth.uid;

          final puedeAprobar = esAdmin || (supervisorODuenoMismoProyecto && !soyAutor);

          // ---------- CONTENIDO ----------
          final content = ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              _Header(obs: obs), // <- SIN IDs
              const SizedBox(height: 10),
              _EstadoPill(estado: obs.estado),
              const SizedBox(height: 12),
              _FotosSection( // <- RESUELVE gs://, host, bucket y cachea
                mediaUrls: _mediaUrlsFromRaw(raw),
                ensureUrl: _ensureDownloadUrl,
              ),
              const SizedBox(height: 16),
              _SectionTitle('Datos generales'),

              // 👉 NOMBRES REALES (no IDs)
              _AutorRow(uid: obs.uidUsuario),
              _ProyectoRow(proyectoId: obs.idProyecto),

              _KV('Fecha de captura', _fmtFecha(obs.fechaCaptura)),
              if ((obs.lugarTipo ?? '').trim().isNotEmpty)
                _KV('Tipo de lugar', obs.lugarTipo!),
              if ((obs.lugarNombre ?? '').trim().isNotEmpty)
                _KV('Nombre del lugar', obs.lugarNombre!.trim()),
              if ((obs.municipio ?? '').trim().isNotEmpty ||
                  (obs.estadoPais ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: -6,
                    children: [
                      if ((obs.municipio ?? '').trim().isNotEmpty)
                        _chip(Icons.location_city_outlined, obs.municipio!.trim()),
                      if ((obs.estadoPais ?? '').trim().isNotEmpty)
                        _chip(Icons.flag_outlined, obs.estadoPais!.trim()),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              _SectionTitle('Ubicación'),
              _CoordsCard(lat: obs.lat, lng: obs.lng, altitud: obs.altitud),
              const SizedBox(height: 16),
              _SectionTitle('Condición / Rastro'),
              _ConditionBlock(
                condicion: obs.condicionAnimal,
                rastroTipo: obs.rastroTipo,
                rastroDetalle: obs.rastroDetalle,
              ),
              if ((obs.especieNombre ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                _SectionTitle('Especie (texto libre)'),
                Text(obs.especieNombre!.trim()),
              ],
              if ((obs.notas ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                _SectionTitle('Notas'),
                Text(obs.notas!.trim()),
              ],
              const SizedBox(height: 16),
              _SectionTitle('Medios vinculados'),
              _KV('Cantidad', (raw['media_count'] ?? 0).toString()),
            ],
          );

          // ---------- BARRA DE ACCIONES ----------
          final actionsBar = _ActionsBar(
            estado: obs.estado,
            puedeAprobar: puedeAprobar,
            soyAutor: soyAutor,
            working: _working,
            motivoCtrl: _motivoCtrl,

            // APROBAR
            onAprobar: () => _confirm(
              title: 'Aprobar observación',
              message: '¿Confirmas aprobar esta observación?',
              run: () => _runAction(
                call: () => context.read<ObservacionProvider>().aprobar(obs.id!),
                okMsg: 'Observación aprobada',
                onOk: () async {
                  final uidAutor = obs.uidUsuario;
                  if (uidAutor.isNotEmpty) {
                    await _notifSvc.push(
                      uid: uidAutor,
                      proyectoId: obs.idProyecto,
                      obsId: obs.id,
                      tipo: NotiTipo.obsAprobada,
                      nivel: NotiNivel.success,
                      titulo: 'Observación aprobada',
                      // 🔄 Sin IDs: lugar + fecha
                      mensaje: 'Tu ${_labelObs(obs)} fue aprobada ✅',
                      meta: {'estado': EstadosObs.aprobado},
                    );
                  }
                },
              ),
            ),

            // RECHAZAR
            onRechazar: () async {
              if (_motivoCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Escribe el motivo de rechazo')),
                );
                return;
              }
              await _confirm(
                title: 'Rechazar observación',
                message: '¿Seguro que deseas rechazarla? Esta acción notifica al autor.',
                run: () => _runAction(
                  call: () => context
                      .read<ObservacionProvider>()
                      .rechazar(obs.id!, motivo: _motivoCtrl.text.trim()),
                  okMsg: 'Observación rechazada',
                  onOk: () async {
                    final uidAutor = obs.uidUsuario;
                    if (uidAutor.isNotEmpty) {
                      await _notifSvc.push(
                        uid: uidAutor,
                        proyectoId: obs.idProyecto,
                        obsId: obs.id,
                        tipo: NotiTipo.obsRechazada,
                        nivel: NotiNivel.error,
                        titulo: 'Observación rechazada',
                        // 🔄 Sin IDs
                        mensaje: 'Tu ${_labelObs(obs)} fue rechazada ❌',
                        meta: {
                          'estado': EstadosObs.rechazado,
                          'motivo': _motivoCtrl.text.trim(),
                        },
                      );
                    }
                  },
                ),
              );
            },

            // ARCHIVAR (solo aprobada)
            onArchivar: () => _confirm(
              title: 'Archivar observación',
              message: 'Se moverá a “Archivado”. ¿Continuar?',
              run: () => _runAction(
                call: () => context.read<ObservacionProvider>().archivar(obs.id!),
                okMsg: 'Observación archivada',
                onOk: () async {
                  final uidAutor = obs.uidUsuario;
                  if (uidAutor.isNotEmpty) {
                    await _notifSvc.push(
                      uid: uidAutor,
                      proyectoId: obs.idProyecto,
                      obsId: obs.id,
                      tipo: NotiTipo.obsEditada, // o crea NotiTipo.obsArchivada
                      nivel: NotiNivel.info,
                      titulo: 'Observación archivada',
                      // 🔄 Sin IDs
                      mensaje: 'Tu ${_labelObs(obs)} fue archivada',
                      meta: {'estado': EstadosObs.archivado},
                    );
                  }
                },
              ),
            ),

            // REVERTIR A BORRADOR (rechazada/archivada)
            onRevertir: () => _confirm(
              title: 'Devolver a borrador',
              message: 'La observación volverá a estado “borrador”. ¿Continuar?',
              run: () => _runAction(
                call: () => context.read<ObservacionProvider>().revertirABorrador(obs.id!),
                okMsg: 'Devuelta a borrador',
                onOk: () async {
                  final uidAutor = obs.uidUsuario;
                  if (uidAutor.isNotEmpty) {
                    await _notifSvc.push(
                      uid: uidAutor,
                      proyectoId: obs.idProyecto,
                      obsId: obs.id,
                      tipo: NotiTipo.obsEditada, // o crea NotiTipo.obsDevueltaBorrador
                      nivel: NotiNivel.info,
                      titulo: 'Devuelta a borrador',
                      // 🔄 Sin IDs
                      mensaje: 'Tu ${_labelObs(obs)} volvió a borrador',
                      meta: {'estado': EstadosObs.borrador},
                    );
                  }
                },
              ),
            ),

            // ENVIAR A REVISIÓN (autor)
            onEnviarRevision: () => _runAction(
              call: () => context.read<ObservacionProvider>().enviarAPendiente(obs.id!),
              okMsg: 'Enviada a revisión',
            ),
          );

          return Stack(
            children: [
              content,
              Positioned(left: 0, right: 0, bottom: 0, child: actionsBar),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirm({
    required String title,
    required String message,
    required Future<void> Function() run,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok == true) await run();
  }

  // Helpers
  List<String> _mediaUrlsFromRaw(Map<String, dynamic> data) {
    final v1 = data['media_urls'];
    if (v1 is List) return v1.whereType<String>().toList();
    final v2 = data['mediaUrls'];
    if (v2 is List) return v2.whereType<String>().toList();
    return const <String>[];
  }

  static String _fmtFecha(DateTime? dt) {
    if (dt == null) return '—';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }
}

// =======================
//      SECCIONES UI
// =======================

class _Header extends StatelessWidget {
  final Observacion obs;
  const _Header({required this.obs});

  @override
  Widget build(BuildContext context) {
    // ❌ Sin IDs en el título: usa lugar/municipio o "Observación"
    final title = (obs.lugarNombre?.trim().isNotEmpty ?? false)
        ? obs.lugarNombre!.trim()
        : (obs.municipio?.trim().isNotEmpty ?? false)
        ? obs.municipio!.trim()
        : 'Observación';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(_fmtDate(obs.fechaCaptura), style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  static String _fmtDate(DateTime? dt) {
    if (dt == null) return 'Sin fecha';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }
}

String _shortId(String id) => id.length <= 6 ? id : id.substring(0, 6);

class _FotosSection extends StatefulWidget {
  final List<String> mediaUrls;
  final Future<String> Function(String) ensureUrl; // <- inyección del resolver
  const _FotosSection({required this.mediaUrls, required this.ensureUrl});

  @override
  State<_FotosSection> createState() => _FotosSectionState();
}

class _FotosSectionState extends State<_FotosSection> {
  late Future<List<String>> _fut;

  @override
  void initState() {
    super.initState();
    _fut = _resolveAll(widget.mediaUrls);
  }

  @override
  void didUpdateWidget(covariant _FotosSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaUrls != widget.mediaUrls) {
      _fut = _resolveAll(widget.mediaUrls);
    }
  }

  Future<List<String>> _resolveAll(List<String> raws) async {
    final list = <String>[];
    for (final r in raws) {
      try {
        final url = await widget.ensureUrl(r);
        if (url.isNotEmpty) list.add(url);
      } catch (_) {
        // Ignora la que falle y continúa
      }
    }
    return list;
  }

  void _openViewer(List<String> urls, int index) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            PageView.builder(
              controller: PageController(initialPage: index),
              itemCount: urls.length,
              itemBuilder: (_, i) => InteractiveViewer(
                panEnabled: true,
                minScale: 0.8,
                maxScale: 4,
                child: CachedNetworkImage(
                  imageUrl: urls[i],
                  fit: BoxFit.contain,
                  progressIndicatorBuilder: (_, __, p) => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (_, src, ___) {
                    debugPrint('⚠️ Error cargando imagen: $src');
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Icon(Icons.broken_image_outlined, size: 48),
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 8, right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaUrls.isEmpty) {
      return const _Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.image_not_supported_outlined),
              SizedBox(width: 8),
              Expanded(child: Text('Sin fotos cargadas (o aún procesándose).')),
            ],
          ),
        ),
      );
    }

    return FutureBuilder<List<String>>(
      future: _fut,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, __) => const _Card(
                child: SizedBox(
                  width: 220,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              ),
            ),
          );
        }

        final urls = (snap.data ?? const <String>[]);
        if (urls.isEmpty) {
          return const _Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.image_not_supported_outlined),
                  SizedBox(width: 8),
                  Expanded(child: Text('Sin fotos cargadas (o aún procesándose).')),
                ],
              ),
            ),
          );
        }

        return SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (ctx, i) {
              final url = urls[i];
              return InkWell(
                onTap: () => _openViewer(urls, i),
                child: _Card(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        progressIndicatorBuilder: (_, __, p) =>
                        const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        errorWidget: (_, src, ___) {
                          debugPrint('⚠️ Error cargando imagen: $src');
                          return Container(
                            color: Colors.black12,
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image_outlined),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _CoordsCard extends StatelessWidget {
  final double? lat, lng, altitud;
  const _CoordsCard({this.lat, this.lng, this.altitud});

  @override
  Widget build(BuildContext context) {
    final hasLat = lat != null && lat!.isFinite;
    final hasLng = lng != null && lng!.isFinite;
    final hasAlt = altitud != null && altitud!.isFinite;

    final coords = [
      if (hasLat && hasLng) '${lat!.toStringAsFixed(6)}, ${lng!.toStringAsFixed(6)}',
      if (hasAlt) '${altitud!.toStringAsFixed(1)} m',
    ].join(' · ');

    return _Card(
      child: ListTile(
        leading: const Icon(Icons.place_outlined),
        title: const Text('Coordenadas'),
        subtitle: Text(coords.isEmpty ? '—' : coords),
      ),
    );
  }
}

class _ConditionBlock extends StatelessWidget {
  final String? condicion;
  final String? rastroTipo;
  final String? rastroDetalle;
  const _ConditionBlock({
    required this.condicion,
    required this.rastroTipo,
    required this.rastroDetalle,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    rows.add(_KV('Condición', condicion ?? '—'));
    if ((rastroTipo ?? '').trim().isNotEmpty) {
      rows.add(_KV('Tipo de rastro', rastroTipo!.trim()));
    }
    if ((rastroDetalle ?? '').trim().isNotEmpty) {
      rows.add(_KV('Detalle del rastro', rastroDetalle!.trim()));
    }
    return Column(children: rows);
  }
}

class _ActionsBar extends StatelessWidget {
  final String estado;
  final bool puedeAprobar;
  final bool soyAutor;
  final bool working;
  final TextEditingController motivoCtrl;

  final VoidCallback onAprobar;
  final VoidCallback onRechazar;
  final VoidCallback onArchivar;
  final VoidCallback onRevertir;
  final VoidCallback onEnviarRevision;

  const _ActionsBar({
    required this.estado,
    required this.puedeAprobar,
    required this.soyAutor,
    required this.working,
    required this.motivoCtrl,
    required this.onAprobar,
    required this.onRechazar,
    required this.onArchivar,
    required this.onRevertir,
    required this.onEnviarRevision,
  });

  @override
  Widget build(BuildContext context) {
    final canModerate = puedeAprobar && estado == EstadosObs.pendiente;
    final showArchivar = estado == EstadosObs.aprobado && puedeAprobar;
    final showRevertir =
        (estado == EstadosObs.rechazado || estado == EstadosObs.archivado) &&
            (puedeAprobar || soyAutor);
    final showEnviarAutor = estado == EstadosObs.borrador && soyAutor;

    return Material(
      elevation: 12,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canModerate) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Motivo de rechazo (si aplica)',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: motivoCtrl,
                  enabled: !working,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Escribe el motivo si vas a rechazar…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canModerate)
                    FilledButton.icon(
                      onPressed: working ? null : onAprobar,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Aprobar'),
                    ),
                  if (canModerate)
                    OutlinedButton.icon(
                      onPressed: working ? null : onRechazar,
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Rechazar'),
                    ),
                  if (showArchivar)
                    OutlinedButton.icon(
                      onPressed: working ? null : onArchivar,
                      icon: const Icon(Icons.archive_outlined),
                      label: const Text('Archivar'),
                    ),
                  if (showRevertir)
                    OutlinedButton.icon(
                      onPressed: working ? null : onRevertir,
                      icon: const Icon(Icons.undo),
                      label: const Text('Revertir a borrador'),
                    ),
                  if (showEnviarAutor)
                    FilledButton.icon(
                      onPressed: working ? null : onEnviarRevision,
                      icon: const Icon(Icons.outgoing_mail),
                      label: const Text('Enviar a revisión'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =======================
//   WIDGETS/UTILIDADES
// =======================

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _KV extends StatelessWidget {
  final String k;
  final String v;
  const _KV(this.k, this.v);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(k, style: Theme.of(context).textTheme.bodySmall),
      subtitle: Text(v),
    );
  }
}

class _EstadoPill extends StatelessWidget {
  final String estado;
  const _EstadoPill({required this.estado});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (estado) {
      case EstadosObs.aprobado:
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        break;
      case EstadosObs.rechazado:
        bg = Colors.red.shade100;
        fg = Colors.red.shade800;
        break;
      case EstadosObs.pendiente:
        bg = Colors.amber.shade100;
        fg = Colors.amber.shade900;
        break;
      case EstadosObs.archivado:
        bg = Colors.blueGrey.shade100;
        fg = Colors.blueGrey.shade800;
        break;
      default:
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration:
        BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(
          estado,
          style:
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

Widget _chip(IconData icon, String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(.05),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: Colors.black54),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontSize: 11, color: Colors.black87)),
    ]),
  );
}

/// ---------- Filas con nombres reales ----------

class _AutorRow extends StatelessWidget {
  final String uid;
  const _AutorRow({required this.uid});

  @override
  Widget build(BuildContext context) {
    final fut =
    FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: fut,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('Autor', style: TextStyle(fontSize: 12)),
            subtitle: SizedBox(height: 14, child: LinearProgressIndicator()),
          );
        }
        String valor = '—';
        if (snap.hasData && snap.data!.data() != null) {
          final data = snap.data!.data()!;
          final nombre =
          (data['displayName'] ?? data['nombre'] ?? '').toString().trim();
          final correo = (data['email'] ?? '').toString().trim();
          if (nombre.isNotEmpty) {
            valor = correo.isNotEmpty ? '$nombre · $correo' : nombre;
          } else if (correo.isNotEmpty) {
            valor = correo;
          }
        }
        return _KV('Autor', valor);
      },
    );
  }
}

class _ProyectoRow extends StatelessWidget {
  final String? proyectoId;
  const _ProyectoRow({required this.proyectoId});

  @override
  Widget build(BuildContext context) {
    if (proyectoId == null || proyectoId!.trim().isEmpty) {
      return const _KV('Proyecto', '— (sin proyecto)');
    }
    final fut = FirebaseFirestore.instance
        .collection('proyectos')
        .doc(proyectoId)
        .get();
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: fut,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('Proyecto', style: TextStyle(fontSize: 12)),
            subtitle: SizedBox(height: 14, child: LinearProgressIndicator()),
          );
        }
        String valor = '—';
        if (snap.hasData && snap.data!.data() != null) {
          final data = snap.data!.data()!;
          final nombre =
          (data['nombre'] ?? data['titulo'] ?? '').toString().trim();
          if (nombre.isNotEmpty) valor = nombre;
        }
        return _KV('Proyecto', valor);
      },
    );
  }
}
