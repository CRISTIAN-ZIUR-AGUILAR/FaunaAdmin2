// lib/ui/screens/observaciones/aprobar_observacion_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:faunadmin2/models/observacion.dart';
import 'package:faunadmin2/models/photo_media.dart';
import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/providers/observacion_provider.dart';
import 'package:faunadmin2/services/permisos_service.dart';
import 'package:faunadmin2/services/firestore_service.dart';

// Notificaciones
import 'package:faunadmin2/models/notificacion.dart';
import 'package:faunadmin2/services/notificacion_service.dart';
import 'package:faunadmin2/utils/notificaciones_constants.dart';

class AprobarObservacionScreen extends StatefulWidget {
  final String observacionId;
  const AprobarObservacionScreen({super.key, required this.observacionId});

  @override
  State<AprobarObservacionScreen> createState() => _AprobarObservacionScreenState();
}

class _AprobarObservacionScreenState extends State<AprobarObservacionScreen> {
  final _db = FirebaseFirestore.instance;
  final _fs = FirestoreService();
  final _notif = NotificacionService();

  final _motivoCtrl = TextEditingController();
  bool _working = false;

  // ===== Utils =====
  DateTime? _ts(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  String _fmtDT(dynamic v) {
    final d = _ts(v);
    if (d == null) return '—';
    String t(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${t(d.month)}-${t(d.day)} ${t(d.hour)}:${t(d.minute)}';
  }

  String _humanBytes(dynamic v) {
    if (v == null) return '—';
    int n;
    if (v is int) n = v; else if (v is String) n = int.tryParse(v) ?? 0; else return v.toString();
    const k = 1024;
    if (n < k) return '$n B';
    final kb = n / k;
    if (kb < k) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / k;
    if (mb < k) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / k;
    return '${gb.toStringAsFixed(1)} GB';
  }

  bool _isChanged(Map<String, dynamic> raw, String key) {
    final arr = raw['changed_fields_since_reject'];
    if (arr is List) return arr.contains(key);
    return false;
  }

  // Calcula dif contra snapshot del rechazo y, si falta, la persiste
  Future<Set<String>> _ensureChangedFieldsSet(String obsId, Map<String, dynamic> raw) async {
    final changed = <String>{};
    final snap = (raw['rejected_snapshot'] is Map<String, dynamic>)
        ? raw['rejected_snapshot'] as Map<String, dynamic>
        : null;
    if (snap != null) {
      final keys = <String>[
        'especie_nombre_cientifico','especie_nombre_comun',
        'taxo_clase','taxo_orden','taxo_familia',
        'lugar_nombre','lugar_tipo','municipio','estado_pais','ubic_region','ubic_distrito',
        'lat','lng','altitud',
        'fecha_captura','edad_aproximada','condicion_animal','rastro_tipo','rastro_detalle','notas',
      ];
      for (final k in keys) {
        final a = raw[k];
        final b = snap[k];
        if ((a is num || b is num) ? (a?.toString() != b?.toString()) : (a != b)) {
          changed.add(k);
        }
      }
      // si el campo no existe en doc, lo guardamos para facilitar UI posteriores
      if (!(raw['changed_fields_since_reject'] is List)) {
        try {
          await context.read<ObservacionProvider>().patch(
            observacionId: obsId,
            patch: {'changed_fields_since_reject': changed.toList()},
            toast: false,
          );
        } catch (_) {}
      }
    }
    return changed;
  }

  Future<String> _ensureDownloadUrl(String raw) async {
    if (raw.isEmpty) return raw;
    if (raw.startsWith('gs://')) {
      final ref = FirebaseStorage.instance.refFromURL(raw);
      return await ref.getDownloadURL();
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      final url = Uri.tryParse(raw);
      final isGcs = raw.contains('firebasestorage.googleapis.com') || raw.contains('appspot.com');
      final hasToken = url?.queryParameters.containsKey('token') ?? false;
      final hasAlt = url?.queryParameters['alt'] == 'media';
      if (isGcs && !hasToken && !hasAlt) {
        try {
          if (url != null && url.pathSegments.contains('o')) {
            final oIdx = url.pathSegments.indexOf('o');
            if (oIdx >= 0 && oIdx + 1 < url.pathSegments.length) {
              final enc = url.pathSegments[oIdx + 1];
              final decodedPath = Uri.decodeFull(enc);
              final ref = FirebaseStorage.instance.ref(decodedPath);
              return await ref.getDownloadURL();
            }
          }
        } catch (_) {}
      }
      return raw;
    }
    try {
      final ref = FirebaseStorage.instance.ref(raw);
      return await ref.getDownloadURL();
    } catch (_) {
      return raw;
    }
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

  Future<void> _runAction({
    required Future<bool> Function() call,
    required String okMsg,
    Observacion? obsForNotif,
    Map<String, dynamic>? meta,
    bool popOnOk = true,
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

      if (ok && obsForNotif != null) {
        final uidAutor = obsForNotif.uidUsuario ?? '';
        if (uidAutor.isNotEmpty) {
          await _notif.push(
            uid: uidAutor,
            proyectoId: obsForNotif.idProyecto,
            obsId: obsForNotif.id,
            tipo: (okMsg.contains('aprobada'))
                ? NotiTipo.obsAprobada
                : (okMsg.contains('rechazada') ? NotiTipo.obsRechazada : NotiTipo.obsEditada),
            nivel: (okMsg.contains('rechazada'))
                ? NotiNivel.error
                : (okMsg.contains('aprobada') ? NotiNivel.success : NotiNivel.info),
            titulo: okMsg,
            mensaje: 'Tu ${_labelObs(obsForNotif)} ${okMsg.toLowerCase()}',
            meta: meta,
          );
        }
      }

      if (ok && popOnOk) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  String _fmtFecha(DateTime? dt) {
    if (dt == null) return '—';
    String t(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${t(dt.month)}-${t(dt.day)} ${t(dt.hour)}:${t(dt.minute)}';
  }

  String _labelObs(Observacion o) {
    final lugar = (o.lugarNombre?.trim().isNotEmpty ?? false)
        ? o.lugarNombre!.trim()
        : (o.municipio?.trim().isNotEmpty ?? false)
        ? o.municipio!.trim()
        : 'observación';
    final fecha = _fmtFecha(o.fechaCaptura);
    return '$lugar · $fecha';
  }

  @override
  void dispose() {
    _motivoCtrl.dispose();
    super.dispose();
  }

  // ===== Validación de aprobación (replica reglas de “agregar”) =====
  List<String> _issuesForApproval(Map<String, dynamic> raw, List<PhotoMedia> medias) {
    final issues = <String>[];
    final obs = Observacion.fromMap(raw, raw['id']!.toString());
    if (medias.isEmpty || medias.length > 4) {
      issues.add('Debes tener entre 1 y 4 fotos vinculadas.');
    }
    if (obs.fechaCaptura == null) {
      issues.add('Falta la fecha/hora de captura.');
    }
    if ((obs.lugarTipo ?? '').trim().isEmpty) {
      issues.add('Falta el tipo de lugar.');
    }
    final lugarOk = ((obs.lugarNombre ?? '').trim().isNotEmpty) || ((obs.municipio ?? '').trim().isNotEmpty);
    if (!lugarOk) {
      issues.add('Escribe el nombre del lugar o el municipio.');
    }
    if (obs.lat == null || obs.lng == null) {
      issues.add('Incluye coordenadas (latitud y longitud).');
    }
    const validas = {EstadosAnimal.vivo, EstadosAnimal.muerto, EstadosAnimal.rastro};
    if (!validas.contains(obs.condicionAnimal)) {
    issues.add('Condición del animal inválida.');
    }
    if (obs.condicionAnimal == EstadosAnimal.rastro) {
    final hasTipo = (obs.rastroTipo ?? '').trim().isNotEmpty;
    final hasDetalle = (obs.rastroDetalle ?? '').trim().isNotEmpty;
    if (!hasTipo && !hasDetalle) {
    issues.add('Para “Rastro”, indica tipo o detalle.');
    }
    }
    return issues;
  }

  Future<List<PhotoMedia>> _fetchMediaOnce() async {
    final qs = await _db
        .collection('observaciones')
        .doc(widget.observacionId)
        .collection('media')
        .get();
    return qs.docs.map((d) => PhotoMedia.fromMap(d.data(), d.id)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final permisos = PermisosService(auth);

    final obsRef = _db.collection('observaciones').doc(widget.observacionId);

    return Scaffold(
      appBar: AppBar(title: const Text('Revisión de observación')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: obsRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists || snap.data!.data() == null) {
            return const Center(child: Text('No se encontró la observación.'));
          }

          final raw = snap.data!.data()!..putIfAbsent('id', () => snap.data!.id);
          final obs = Observacion.fromMap(raw, snap.data!.id);

          // Permisos
          final proyectoId = obs.idProyecto;
          final soyAutor = (obs.uidUsuario == auth.uid);
          final reviewerEsAdmin = permisos.isAdminUnico;
          final esModeradorProyecto = (proyectoId != null && proyectoId.isNotEmpty)
              ? permisos.canModerateProject(proyectoId)
              : false;
          final puedeAprobar = reviewerEsAdmin || (esModeradorProyecto && !soyAutor);

          final mediaStream = _fs.streamPhotoMediaForObservacion(widget.observacionId);

          final dtRejected = _ts(raw['rejected_at']);
          final dtUpdated = _ts(raw['updated_at']);
          final updatedAfterReject =
          (dtRejected != null && dtUpdated != null && dtUpdated.isAfter(dtRejected));

          // calcula/actualiza "changed_fields_since_reject" si aplica
          if (obs.estado == EstadosObs.rechazado) {
            // fire and forget
            unawaited(_ensureChangedFieldsSet(obs.id!, raw));
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              // Header
              _Header(obs: obs),
              const SizedBox(height: 6),
              _EstadoPill(estado: obs.estado ?? EstadosObs.borrador),
              if (updatedAfterReject)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(.08),
                      border: Border.all(color: Colors.blue.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Actualizada después del rechazo (${_fmtDT(dtRejected)})'),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),
              // ===== Evidencias =====
              _CardSection(
                title: 'Evidencias',
                children: [
                  _SpanChild(
                    span: (_) => _.clamp(1, 3),
                    child: StreamBuilder<List<PhotoMedia>>(
                      stream: mediaStream,
                      builder: (ctx, msnap) {
                        if (msnap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }
                        final medias = (msnap.data ?? const <PhotoMedia>[]);
                        if (medias.isEmpty) {
                          return const Text('Sin fotos cargadas.');
                        }
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 4 / 5,
                          ),
                          itemCount: medias.length,
                          itemBuilder: (_, i) => _MediaCard(
                            media: medias[i],
                            ensureUrl: _ensureDownloadUrl,
                            rejectedAt: dtRejected,
                            fmtDT: _fmtDT,
                            humanBytes: _humanBytes,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),

              // ===== Checklist (se calcula con una lectura única cuando apruebas) =====
              _CardSection(
                title: 'Checklist de revisión',
                children: [
                  _SpanChild(
                    child: FutureBuilder<List<PhotoMedia>>(
                      future: _fetchMediaOnce(),
                      builder: (_, ms) {
                        final medias = ms.data ?? const <PhotoMedia>[];
                        final issues = _issuesForApproval(raw, medias);
                        final ok = issues.isEmpty;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Check(ok, 'Tiene entre 1 y 4 fotos (actual: ${medias.length})'),
                            _Check(obs.fechaCaptura != null, 'Fecha/hora de captura'),
                            _Check((obs.lugarTipo ?? '').trim().isNotEmpty, 'Tipo de lugar'),
                            _Check(((obs.lugarNombre ?? '').trim().isNotEmpty) || ((obs.municipio ?? '').trim().isNotEmpty),
                                'Nombre del lugar o municipio'),
                            _Check((obs.lat != null && obs.lng != null), 'Coordenadas (lat/lng)'),
                            _Check(
                              {EstadosAnimal.vivo, EstadosAnimal.muerto, EstadosAnimal.rastro}.contains(obs.condicionAnimal),
                              'Condición válida',
                            ),
                            if (obs.condicionAnimal == EstadosAnimal.rastro)
                              _Check(
                                ((obs.rastroTipo ?? '').trim().isNotEmpty) || ((obs.rastroDetalle ?? '').trim().isNotEmpty),
                                'Rastro: tipo o detalle indicado',
                              ),
                            if (!ok) ...[
                              const SizedBox(height: 8),
                              Text('Pendientes:', style: Theme.of(context).textTheme.bodySmall),
                              ...issues.map((e) => Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text('• $e', style: const TextStyle(color: Colors.red)),
                              )),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),

              // ===== Autor / Proyecto =====
              _CardSection(
                title: 'Autor / Proyecto',
                children: [
                  _SpanChild(child: _AutorRow(uid: obs.uidUsuario ?? '')),
                  _SpanChild(child: _ProyectoRow(proyectoId: obs.idProyecto)),
                ],
              ),

              // ===== Especie =====
              _CardSection(
                title: 'Especie',
                children: [
                  _SpanChild(child: _KVx('Nombre científico', obs.especieNombreCientifico ?? '—',
                      changed: _isChanged(raw, 'especie_nombre_cientifico'))),
                  _SpanChild(child: _KVx('Nombre común', obs.especieNombreComun ?? '—',
                      changed: _isChanged(raw, 'especie_nombre_comun'))),
                ],
              ),

              // ===== Taxonomía (auto) =====
              _CardSection(
                title: 'Taxonomía (auto)',
                children: [
                  _SpanChild(child: _KVx('Clase', (raw['taxo_clase'] ?? '—').toString(),
                      changed: _isChanged(raw, 'taxo_clase'))),
                  _SpanChild(child: _KVx('Orden', (raw['taxo_orden'] ?? '—').toString(),
                      changed: _isChanged(raw, 'taxo_orden'))),
                  _SpanChild(child: _KVx('Familia', (raw['taxo_familia'] ?? '—').toString(),
                      changed: _isChanged(raw, 'taxo_familia'))),
                ],
              ),

              // ===== Lugar =====
              _CardSection(
                title: 'Lugar',
                children: [
                  _SpanChild(child: _KVx('Nombre del lugar', obs.lugarNombre ?? '—',
                      changed: _isChanged(raw, 'lugar_nombre'))),
                  _SpanChild(child: _KVx('Tipo de lugar', obs.lugarTipo ?? '—',
                      changed: _isChanged(raw, 'lugar_tipo'))),
                  _SpanChild(child: _KVx('Municipio', obs.municipio ?? '—',
                      changed: _isChanged(raw, 'municipio'))),
                  _SpanChild(child: _KVx('Estado (auto)', obs.estadoPais ?? '—',
                      changed: _isChanged(raw, 'estado_pais'))),
                  _SpanChild(child: _KVx('Región (auto)', (raw['ubic_region'] ?? '—').toString(),
                      changed: _isChanged(raw, 'ubic_region'))),
                  _SpanChild(child: _KVx('Distrito (auto)', (raw['ubic_distrito'] ?? '—').toString(),
                      changed: _isChanged(raw, 'ubic_distrito'))),
                ],
              ),

              // ===== Coordenadas =====
              _CardSection(
                title: 'Coordenadas',
                children: [
                  _SpanChild(child: _KVx('Latitud', obs.lat?.toStringAsFixed(6) ?? '—',
                      changed: _isChanged(raw, 'lat'))),
                  _SpanChild(child: _KVx('Longitud', obs.lng?.toStringAsFixed(6) ?? '—',
                      changed: _isChanged(raw, 'lng'))),
                  _SpanChild(child: _KVx('Altitud',
                      obs.altitud != null ? '${obs.altitud!.toStringAsFixed(1)} m' : '—',
                      changed: _isChanged(raw, 'altitud'))),
                ],
              ),

              // ===== Captura =====
              _CardSection(
                title: 'Captura',
                children: [
                  _SpanChild(child: _KVx('Fecha/Hora de captura', _fmtFecha(obs.fechaCaptura),
                      changed: _isChanged(raw, 'fecha_captura'))),
                  _SpanChild(child: _KVx('Edad aproximada', obs.edadAproximada?.toString() ?? '—',
                      changed: _isChanged(raw, 'edad_aproximada'))),
                  _SpanChild(child: _KVx('Condición', obs.condicionAnimal ?? '—',
                      changed: _isChanged(raw, 'condicion_animal'))),
                  if ((obs.condicionAnimal ?? '') == EstadosAnimal.rastro)
                    _SpanChild(child: _KVx('Tipo de rastro', obs.rastroTipo ?? '—',
                        changed: _isChanged(raw, 'rastro_tipo'))),
                  if ((obs.condicionAnimal ?? '') == EstadosAnimal.rastro)
                    _SpanChild(child: _KVx('Detalle del rastro', obs.rastroDetalle ?? '—',
                        changed: _isChanged(raw, 'rastro_detalle'))),
                ],
              ),

              if ((obs.notas ?? '').trim().isNotEmpty)
                _CardSection(
                  title: 'Notas',
                  children: [ _SpanChild(child: _KVx('Notas', obs.notas!.trim(),
                      changed: _isChanged(raw, 'notas'))), ],
                ),

              const SizedBox(height: 12),
              _ActionsBar(
                estado: obs.estado ?? EstadosObs.borrador,
                puedeAprobar: puedeAprobar,
                soyAutor: soyAutor,
                working: _working,
                motivoCtrl: _motivoCtrl,
                onAprobar: () async {
                  // Validación dura previo a aprobar
                  final medias = await _fetchMediaOnce();
                  final issues = _issuesForApproval(raw, medias);
                  if (issues.isNotEmpty) {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Faltan requisitos'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: issues.map((e) => Text('• $e')).toList(),
                        ),
                        actions: [ TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ok')) ],
                      ),
                    );
                    return;
                  }
                  await _confirm(
                    title: 'Aprobar observación',
                    message: '¿Confirmas aprobar esta observación?',
                    run: () => _runAction(
                      call: () => context.read<ObservacionProvider>().aprobar(obs.id!),
                      okMsg: 'Observación aprobada',
                      obsForNotif: obs,
                      meta: {'estado': EstadosObs.aprobado},
                    ),
                  );
                },
                onRechazar: () async {
                  if (_motivoCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Escribe el motivo de rechazo')),
                    );
                    return;
                  }
                  await _confirm(
                    title: 'Rechazar observación',
                    message: '¿Seguro que deseas rechazarla? Se notificará al autor.',
                    run: () => _runAction(
                      call: () => context.read<ObservacionProvider>()
                          .rechazar(obs.id!, motivo: _motivoCtrl.text.trim()),
                      okMsg: 'Observación rechazada',
                      obsForNotif: obs,
                      meta: {
                        'estado': EstadosObs.rechazado,
                        'motivo': _motivoCtrl.text.trim(),
                      },
                    ),
                  );
                },
                onArchivar: () => _confirm(
                  title: 'Archivar observación',
                  message: 'Se moverá a “Archivado”. ¿Continuar?',
                  run: () => _runAction(
                    call: () => context.read<ObservacionProvider>().archivar(obs.id!),
                    okMsg: 'Observación archivada',
                    obsForNotif: obs,
                    meta: {'estado': EstadosObs.archivado},
                  ),
                ),
                onRevertir: () => _confirm(
                  title: 'Devolver a borrador',
                  message: 'La observación volverá a “borrador”. ¿Continuar?',
                  run: () => _runAction(
                    call: () => context.read<ObservacionProvider>().revertirABorrador(obs.id!),
                    okMsg: 'Devuelta a borrador',
                    obsForNotif: obs,
                    meta: {'estado': EstadosObs.borrador},
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ================== Helpers UI (igual estilo que “agregar”) ==================
class _CardSection extends StatelessWidget {
  final String title;
  final List<_SpanChild> children;
  final EdgeInsets margin;
  const _CardSection({
    required this.title,
    required this.children,
    this.margin = const EdgeInsets.only(bottom: 16),
  });

  int _colsForWidth(double w) {
    if (w >= 1200) return 3;
    if (w >= 801) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final cols = _colsForWidth(constraints.maxWidth);
      const gap = 12.0;
      final colW = (constraints.maxWidth - gap * (cols - 1)) / cols;
      final items = <Widget>[];
      for (final sc in children) {
        final span = sc.span?.call(cols) ?? 1;
        final width = (span.clamp(1, cols) * colW) + (gap * (span - 1));
        items.add(SizedBox(width: width, child: sc.child));
      }
      return Card(
        elevation: 1.5,
        margin: margin,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 6, height: 22,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 10),
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                )),
              ]),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Wrap(spacing: 12.0, runSpacing: 12.0, children: items),
            ],
          ),
        ),
      );
    });
  }
}

class _SpanChild {
  final Widget child;
  final int Function(int cols)? span;
  _SpanChild({required this.child, this.span});
}

class _KVx extends StatelessWidget {
  final String k;
  final String v;
  final bool changed;
  const _KVx(this.k, this.v, {this.changed = false});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Text(k, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          if (changed) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.shade300),
              ),
              child: const Text('Actualizado', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
      subtitle: Text(v),
    );
  }
}

class _Header extends StatelessWidget {
  final Observacion obs;
  const _Header({required this.obs});

  @override
  Widget build(BuildContext context) {
    final title = (obs.lugarNombre?.trim().isNotEmpty ?? false)
        ? obs.lugarNombre!.trim()
        : (obs.municipio?.trim().isNotEmpty ?? false)
        ? obs.municipio!.trim()
        : 'Observación';
    String t(int n) => n.toString().padLeft(2, '0');
    final dt = obs.fechaCaptura;
    final fecha = (dt == null)
        ? 'Sin fecha'
        : '${dt.year}-${t(dt.month)}-${t(dt.day)} ${t(dt.hour)}:${t(dt.minute)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(fecha, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _EstadoPill extends StatelessWidget {
  final String estado;
  const _EstadoPill({required this.estado});

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    switch (estado) {
      case EstadosObs.aprobado: bg = Colors.green.shade100; fg = Colors.green.shade800; break;
      case EstadosObs.rechazado: bg = Colors.red.shade100; fg = Colors.red.shade800; break;
      case EstadosObs.pendiente:
      case EstadosObs.revisarNuevo: bg = Colors.amber.shade100; fg = Colors.amber.shade900; break;
      case EstadosObs.archivado: bg = Colors.blueGrey.shade100; fg = Colors.blueGrey.shade800; break;
      default: bg = Colors.grey.shade200; fg = Colors.grey.shade800;
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(estado, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      ),
    );
  }
}

class _MediaCard extends StatefulWidget {
  final PhotoMedia media;
  final Future<String> Function(String) ensureUrl;
  final DateTime? rejectedAt;
  final String Function(dynamic) fmtDT;
  final String Function(dynamic) humanBytes;

  const _MediaCard({
    required this.media,
    required this.ensureUrl,
    required this.rejectedAt,
    required this.fmtDT,
    required this.humanBytes,
  });

  @override
  State<_MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<_MediaCard> {
  late Future<String> _fut;

  @override
  void initState() {
    super.initState();
    _fut = _resolve();
  }

  @override
  void didUpdateWidget(covariant _MediaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.id != widget.media.id ||
        oldWidget.media.thumbnailPath != widget.media.thumbnailPath ||
        oldWidget.media.storagePath != widget.media.storagePath) {
      _fut = _resolve();
    }
  }

  Future<String> _resolve() async {
    final thumb = widget.media.thumbnailPath ?? '';
    final src = thumb.isNotEmpty ? thumb : (widget.media.url ?? widget.media.storagePath);
    return await widget.ensureUrl(src ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[];
    if ((widget.media.authenticity ?? '').isNotEmpty) {
      badges.add(_smallBadge(widget.media.authenticity!));
    }
    if ((widget.media.quality ?? '').isNotEmpty) {
      badges.add(_smallBadge(widget.media.quality!));
    }
    if ((widget.media.flags ?? const <String>[]).isNotEmpty) {
      for (final f in widget.media.flags!) {
        badges.add(_smallBadge(f));
      }
    }

    final j = widget.media.toMap();
    final capturedAt = j['captured_at'];
    final createdAt  = j['createdAt'];
    final camera     = (j['camera_model'] ?? j['device_model'] ?? '').toString();
    final orig       = (j['original_file_name'] ?? '').toString();
    final size       = j['file_size'];
    final width      = j['width'] ?? j['image_width'];
    final height     = j['height'] ?? j['image_height'];
    final nuevo      = (widget.rejectedAt != null &&
        createdAt != null &&
        (createdAt is Timestamp ? createdAt.toDate() : DateTime.tryParse(createdAt.toString()) ?? DateTime(1900))
            .isAfter(widget.rejectedAt!));

    return FutureBuilder<String>(
      future: _fut,
      builder: (ctx, snap) {
        final url = snap.data ?? '';
        return Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: (url.isEmpty)
                          ? Container(color: Colors.black12, alignment: Alignment.center,
                          child: const Icon(Icons.image_not_supported_outlined))
                          : CachedNetworkImage(
                        imageUrl: url, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                    if (badges.isNotEmpty)
                      Positioned(
                        left: 6, top: 6, right: 6,
                        child: Wrap(spacing: 6, runSpacing: 6, children: badges.take(3).toList()),
                      ),
                    if (nuevo)
                      Positioned(
                        right: 6, top: 6,
                        child: _smallBadge('NUEVO', strong: true, color: Colors.orange.withOpacity(.85)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (capturedAt != null) Text('Tomada: ${widget.fmtDT(capturedAt)}', style: const TextStyle(fontSize: 12)),
                    if (camera.isNotEmpty)   Text('Cámara: $camera', style: const TextStyle(fontSize: 12)),
                    Row(
                      children: [
                        if (width != null && height != null)
                          Expanded(child: Text('Dimensiones: ${width}×$height', style: const TextStyle(fontSize: 12))),
                        if (size != null)
                          Expanded(child: Text('Tamaño: ${widget.humanBytes(size)}', style: const TextStyle(fontSize: 12))),
                      ],
                    ),
                    if (orig.isNotEmpty) Text('Archivo: $orig', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _smallBadge(String text, {bool strong = false, Color? color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: (color ?? Colors.black.withOpacity(.55)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(text,
        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: strong ? FontWeight.w800 : FontWeight.w600)),
  );
}

class _Check extends StatelessWidget {
  final bool ok;
  final String text;
  const _Check(this.ok, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(ok ? Icons.check_circle : Icons.error_outline,
            size: 16, color: ok ? Colors.green : Colors.red),
        const SizedBox(width: 6),
        Expanded(child: Text(text)),
      ],
    );
  }
}

// Autor y Proyecto (lookups compactos)
class _AutorRow extends StatelessWidget {
  final String uid;
  const _AutorRow({required this.uid});

  @override
  Widget build(BuildContext context) {
    if ((uid).trim().isEmpty) return const _KVx('Autor', '—');
    final fut = FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
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
          final n = (data['nombre_completo'] ?? data['displayName'] ?? data['nombre'] ?? '').toString().trim();
          final c = (data['correo'] ?? data['email'] ?? '').toString().trim();
          if (n.isNotEmpty) {
            valor = c.isNotEmpty ? '$n · $c' : n;
          } else if (c.isNotEmpty) {
            valor = c;
          }
        }
        return _KVx('Autor', valor);
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
      return const _KVx('Proyecto', '— (sin proyecto)');
    }
    final fut = FirebaseFirestore.instance.collection('proyectos').doc(proyectoId).get();
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
          final nombre = (data['nombre'] ?? data['titulo'] ?? '').toString().trim();
          if (nombre.isNotEmpty) valor = nombre;
        }
        return _KVx('Proyecto', valor);
      },
    );
  }
}

// Barra de acciones compacta
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
  });

  @override
  Widget build(BuildContext context) {
    final isPendiente = estado == EstadosObs.pendiente || estado == EstadosObs.revisarNuevo;
    final canModerate = puedeAprobar && isPendiente;
    final showArchivar = estado == EstadosObs.aprobado && puedeAprobar;
    final showRevertir =
        (estado == EstadosObs.rechazado && (puedeAprobar || soyAutor)) ||
            (estado == EstadosObs.archivado && puedeAprobar);

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
                  child: Text('Motivo de rechazo (si aplica)', style: Theme.of(context).textTheme.bodySmall),
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

