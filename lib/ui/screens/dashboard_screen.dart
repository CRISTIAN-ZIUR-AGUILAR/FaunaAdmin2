// lib/ui/screens/dashboard_screen.dart (versión PRO auto-sync, sin botones manuales)
import 'dart:convert';
import 'dart:io' show File; // <-- para mostrar thumbs locales con Image.file
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/ui/widgets/app_drawer.dart';
import 'package:faunadmin2/services/local_file_storage.dart';
import 'package:faunadmin2/services/auto_sync_observaciones_service.dart';
import 'package:faunadmin2/models/observacion.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

// === Configuración ===
const Duration kVentanaBorradoresRecientes = Duration(days: 30);

class DashboardScreen extends StatefulWidget {
  final bool skipAutoNavFromRoute;
  const DashboardScreen({super.key, this.skipAutoNavFromRoute = false});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? _fullNameFromDb;
  int _pendientesLocal = 0;

  bool get _isMobile {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  // cache para nombres de proyecto
  final Map<String, String> _projNameCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Lanzamos las tareas asíncronas SIN await (para no mezclar await + context)
      _loadNombreCompleto();

      if (_isMobile) {
        // Arrancamos el autosync (escucha conectividad + sube en segundo plano)
        AutoSyncObservacionesService.instance.start(context);
        _refreshPendingLocal();
      }
    });
  }

  Future<void> _loadNombreCompleto() async {
    try {
      final uid = fb.FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();
      final data = doc.data();
      final nombre =
      (data != null ? (data['nombre_completo'] as String?) : null)?.trim();
      if (!mounted) return;
      if (nombre != null && nombre.isNotEmpty) {
        setState(() => _fullNameFromDb = nombre);
      }
    } catch (e) {
      debugPrint('[DASH] _loadNombreCompleto error: $e');
      // Silencioso
    }
  }

  Future<void> _refreshPendingLocal() async {
    if (!_isMobile) return;
    try {
      final dirList = await LocalFileStorage.instance.listarObservaciones();
      int count = 0;
      for (final d in dirList) {
        final meta = await LocalFileStorage.instance.leerMeta(d);
        if (meta == null) continue;
        final status = (meta['status'] ?? '').toString().toUpperCase();
        if (status != 'SYNCED') count++;
      }
      if (!mounted) return;
      setState(() => _pendientesLocal = count);
      debugPrint('[DASH] Pendientes locales detectados: $count');
    } catch (e) {
      debugPrint('[DASH] _refreshPendingLocal error: $e');
      if (!mounted) return;
      setState(() => _pendientesLocal = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    final firebaseDisplayName =
    (auth.user?.displayName?.trim().isNotEmpty ?? false)
        ? auth.user!.displayName!.trim()
        : null;
    final displayName = (_fullNameFromDb?.isNotEmpty ?? false)
        ? _fullNameFromDb!
        : (firebaseDisplayName ?? 'Usuario');

    final correo = auth.user?.email ?? '—';
    final cs = Theme.of(context).colorScheme;

    // TODO: cuando tengas el código del rol activo en el AuthProvider,
    // pásalo aquí para filtrar por rol en el dashboard.
    // Ejemplo (ajusta el nombre de la propiedad):
    // final rolCodigo = auth.rolActivoCodigo;
    const String? rolCodigo = null;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            tooltip: MaterialLocalizations.of(ctx).openAppDrawerTooltip,
          ),
        ),
        title: Text('Hola, ${displayName.split(' ').first}'),
        // 🔕 Sin acciones de sync manuales
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadNombreCompleto();
          if (_isMobile) await _refreshPendingLocal();
          if (mounted) setState(() {});
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _HeaderCardSimple(name: displayName, email: correo),
            const SizedBox(height: 14),

            // CTA principal
            _AddObservationCTA(
              onTap: () => Navigator.of(context).pushNamed('/seleccion'),
            ),
            const SizedBox(height: 14),

            // Info de sincronización automática + estado
            if (_isMobile)
              _SyncStrip(
                pendientes: _pendientesLocal,
              ),
            if (!_isMobile)
              const _InfoBox(
                  text:
                  'La sincronización local automática está disponible solo en Android/iOS.'),

            const SizedBox(height: 16),

            // Proyectos y Observaciones (borradores) => Local + Nube
            _ProyectosResumenCard(
              fetchProyectoNombre: _fetchProyectoNombre,
              ctxRolCodigo: rolCodigo,
            ),

            const SizedBox(height: 24),

            // Placeholder de sección de notificaciones (espacio reservado)
            const _InfoBox(
              text:
              '🔔 Notificaciones (aprobadas, rechazadas, cambios, eliminaciones) — próximamente.',
            ),
          ],
        ),
      ),
    );
  }

  // ===== helpers de proyecto =====

  Future<String?> _fetchProyectoNombre(String id) async {
    if (id.isEmpty) return null;
    if (_projNameCache.containsKey(id)) return _projNameCache[id];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('proyectos')
          .doc(id)
          .get();
      final nombre = (snap.data()?['nombre'] as String?)?.trim();
      if (nombre != null && nombre.isNotEmpty) {
        _projNameCache[id] = nombre;
        return nombre;
      }
    } catch (e) {
      debugPrint('[DASH] _fetchProyectoNombre($id) error: $e');
    }
    return null;
  }
}

// ================= UI =================

class _InfoBox extends StatelessWidget {
  final String text;
  const _InfoBox({required this.text});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: cs.surface,
        border: Border.all(color: cs.outline.withOpacity(.16)),
      ),
      child: Text(text, style: const TextStyle(color: Colors.black54)),
    );
  }
}

class _HeaderCardSimple extends StatelessWidget {
  final String name;
  final String email;
  const _HeaderCardSimple({required this.name, required this.email});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary.withOpacity(.12), cs.secondary.withOpacity(.08)],
        ),
        border: Border.all(color: cs.outline.withOpacity(.15)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: cs.primary.withOpacity(.15),
            child: Icon(Icons.person, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(email, style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===== CTA aparte: Agregar observación =====
class _AddObservationCTA extends StatelessWidget {
  final VoidCallback onTap;
  const _AddObservationCTA({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withOpacity(.16)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.add_circle_outline),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Agregar observaciones',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(
            height: 40,
            child: OutlinedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.add),
              label: const Text('Agregar observación'),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== Strip de sincronización (solo informativa, sin botón) =====
class _SyncStrip extends StatelessWidget {
  final int pendientes;

  const _SyncStrip({
    required this.pendientes,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasPending = pendientes > 0;

    final String line1 = hasPending
        ? '$pendientes observación(es) guardadas en el teléfono.'
        : 'No hay observaciones locales pendientes por subir.';
    const String line2 =
        'Cuando el dispositivo tenga conexión a internet, la app las subirá automáticamente a la nube.';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: cs.surface,
        border: Border.all(color: cs.outline.withOpacity(.16)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: cs.primary.withOpacity(.10),
            child: const Icon(Icons.cloud_sync_rounded, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sincronización automática',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  line1,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
                const SizedBox(height: 2),
                const Text(
                  line2,
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =========================
// PROYECTOS: modelo + carga + UI
// =========================

class ObsResumen {
  final String id;
  final String titulo;
  final String? nombreCientifico;
  final DateTime? fecha;
  final String? thumb; // base64 o 'URL::http...' o 'FILE::/ruta'
  final String origen; // 'local' | 'nube'
  ObsResumen({
    required this.id,
    required this.titulo,
    required this.nombreCientifico,
    required this.fecha,
    required this.thumb,
    required this.origen,
  });
}

class ProyectoResumen {
  final String id;
  final String nombre;
  final List<ObsResumen> local;
  final List<ObsResumen> nube;
  ProyectoResumen({
    required this.id,
    required this.nombre,
    required this.local,
    required this.nube,
  });

  int get totalBorradores => local.length + nube.length;
}

String _safeStr(dynamic v) => (v == null) ? '' : v.toString().trim();

/// ====== Helpers de título preferido (científico > común > título crudo)
String? _preferSciName(Map<String, dynamic> m) {
  final cand = [
    // claves típicas cloud
    m['especie_nombre_cientifico'],
    m['nombre_cientifico'],
    m['taxon_nombre_cientifico'],
    m['scientific_name'],
    (m['especie'] is Map ? (m['especie'] as Map)['nombre_cientifico'] : null),
    (m['taxon'] is Map ? (m['taxon'] as Map)['nombre_cientifico'] : null),

    // ⚠️ clave usada en locales
    m['especie_nombre'],
  ];
  for (final c in cand) {
    final s = _safeStr(c);
    if (s.isNotEmpty) return s;
  }
  return null;
}

String? _preferCommonName(Map<String, dynamic> m) {
  final cand = [
    m['especie_nombre_comun'],
    m['nombre_comun'],
    m['common_name'],
    (m['especie'] is Map ? (m['especie'] as Map)['nombre_comun'] : null),
  ];
  for (final c in cand) {
    final s = _safeStr(c);
    if (s.isNotEmpty) return s;
  }
  return null;
}

// Miniatura: primera URL http(s) de una lista dinámica (media_urls)
String? _firstHttpFromList(dynamic v) {
  if (v is List) {
    for (final e in v) {
      final s = _safeStr(e);
      if (s.startsWith('http://') || s.startsWith('https://')) return s;
    }
  }
  return null;
}

// Carga combinada de borradores por proyecto (Local + Nube)
Future<List<ProyectoResumen>> cargarProyectosConBorradores({
  int maxProjects = 4,
  int maxItemsPorOrigen = 6,
  Future<String?> Function(String id)? fetchProyectoNombre,
  String? ctxRolCodigo, // <- opcional: filtrar por rol
}) async {
  final Map<String, ProyectoResumen> mapa = {};
  final Map<String, String> nombreProyecto = {};

  // 1) Local (borradores)
  if (!kIsWeb) {
    try {
      final local = LocalFileStorage.instance;
      final dirs = await local.listarObservaciones();
      debugPrint('[DASH] Local: carpetas encontradas = ${dirs.length}');
      final metas = await Future.wait(
          dirs.map((d) async => (dir: d, meta: await local.leerMeta(d))));
      int contDescartadas = 0;
      int contOk = 0;

      for (final e in metas) {
        final m = e.meta;
        if (m == null) {
          contDescartadas++;
          continue;
        }

        // rol de contexto en draft local (si existe)
        final ctxRolMeta =
        _safeStr(m['ctx_rol'] ?? m['ctxRol'] ?? m['rol_codigo']);
        if (ctxRolCodigo != null &&
            ctxRolMeta.isNotEmpty &&
            ctxRolMeta != ctxRolCodigo) {
          // borrador de otro rol → no se muestra
          contDescartadas++;
          continue;
        }

        // status/estado tolerante
        final estado = _safeStr(m['estado']).toLowerCase();
        final status = _safeStr(m['status']).toUpperCase();
        final esBorrador = estado == 'borrador' || status != 'SYNCED';
        if (!esBorrador) {
          contDescartadas++;
          continue;
        }

        final pid = _safeStr(m['id_proyecto'] ??
            m['proyecto_id'] ??
            m['project_id'] ??
            m['proyectoId']);
        // Si no tiene proyecto, lo agrupamos como "Sin proyecto"
        final keyProyecto = pid.isEmpty ? '__SIN_PROYECTO__' : pid;

        final pname = _safeStr(m['proyecto_nombre'] ??
            m['proyecto'] ??
            m['project_name'] ??
            m['nombre_proyecto']);
        if (pname.isNotEmpty) {
          nombreProyecto[keyProyecto] = pname;
        } else if (pid.isEmpty) {
          nombreProyecto['__SIN_PROYECTO__'] = 'Sin proyecto';
        }

        // ===== título preferido (científico > común > fallback)
        final sci = _preferSciName(m);
        final common = _preferCommonName(m);
        final titulo = (sci != null && sci.isNotEmpty)
            ? sci
            : (common != null && common.isNotEmpty)
            ? common
            : 'Sin especie';

        final tsStr = _safeStr(m['updated_local_at'] ??
            m['created_local_at'] ??
            m['ultima_modificacion']);
        final ts = tsStr.isEmpty ? null : DateTime.tryParse(tsStr);

        // Thumb local: base64 -> si no hay, primera foto como FILE::<ruta>
        String thumb = _safeStr(
            m['thumbnail_base64'] ?? m['thumb_b64'] ?? m['preview_b64']);
        if (thumb.isEmpty) {
          try {
            final fotos = await local.listarFotos(e.dir);
            if (fotos.isNotEmpty) {
              final path = fotos.first.path;
              if (path.isNotEmpty) thumb = 'FILE::$path';
            }
          } catch (ee) {
            debugPrint('[DASH] No pude listar fotos en ${e.dir.path}: $ee');
          }
        }

        final id = _safeStr(m['id'] ?? m['uuid'] ?? e.dir.toString());

        mapa.putIfAbsent(
            keyProyecto,
                () => ProyectoResumen(
                id: keyProyecto,
                nombre: nombreProyecto[keyProyecto] ??
                    (pid.isEmpty ? 'Sin proyecto' : 'Proyecto sin nombre'),
                local: [],
                nube: []));
        final pr = mapa[keyProyecto]!;
        if (pr.local.length < maxItemsPorOrigen) {
          pr.local.add(ObsResumen(
              id: id,
              titulo: titulo,
              nombreCientifico: sci,
              fecha: ts,
              thumb: thumb.isEmpty ? null : thumb,
              origen: 'local'));
        }
        if (nombreProyecto[keyProyecto] != null) {
          mapa[keyProyecto] = ProyectoResumen(
              id: pr.id,
              nombre: nombreProyecto[keyProyecto]!,
              local: pr.local,
              nube: pr.nube);
        }
        contOk++;
      }
      debugPrint('[DASH] Local: OK=$contOk, descartadas=$contDescartadas');
    } catch (e) {
      debugPrint('[DASH] Error leyendo locales: $e');
    }
  } else {
    debugPrint('[DASH] Local: omitido en Web.');
  }

  // 2) Nube (borradores)
  try {
    final uid = fb.FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      debugPrint(
          '[DASH] Cloud: uid=$uid — consultando borradores por uid_usuario');

      final col = FirebaseFirestore.instance.collection('observaciones');

      // Consulta SIMPLE (sin orderBy, así no requiere índice extra):
      final snap = await col
          .where('uid_usuario', isEqualTo: uid)
          .where('estado', isEqualTo: 'borrador')
          .limit(200)
          .get();

      debugPrint('[DASH] Cloud: docs=${snap.docs.length}');

      int cloudOk = 0;
      int cloudDesc = 0;

      for (final d in snap.docs) {
        final data = d.data();

        // rol de contexto (si está guardado en la nube)
        final ctxRolDoc = _safeStr(data['ctx_rol'] ?? data['ctxRol']);
        if (ctxRolCodigo != null &&
            ctxRolDoc.isNotEmpty &&
            ctxRolDoc != ctxRolCodigo) {
          cloudDesc++;
          continue;
        }

        // Proyecto (puede venir vacío o no venir)
        final pid = _safeStr(
            data['id_proyecto'] ?? data['proyecto_id'] ?? data['project_id']);
        final keyProyecto = pid.isEmpty ? '__SIN_PROYECTO__' : pid;

        final pname = _safeStr(data['proyecto_nombre'] ??
            data['proyecto'] ??
            data['project_name'] ??
            data['nombre_proyecto']);
        if (pname.isNotEmpty) {
          nombreProyecto[keyProyecto] = pname;
        } else if (pid.isEmpty) {
          nombreProyecto['__SIN_PROYECTO__'] = 'Sin proyecto';
        }

        // ===== título preferido (científico > común > 'Sin título')
        String? sci;
        for (final k in const [
          'especie_nombre_cientifico',
          'nombre_cientifico',
          'taxon_nombre_cientifico',
          'scientific_name'
        ]) {
          final s = _safeStr(data[k]);
          if (s.isNotEmpty) {
            sci = s;
            break;
          }
        }
        String? common;
        for (final k in const [
          'especie_nombre_comun',
          'nombre_comun',
          'common_name'
        ]) {
          final s = _safeStr(data[k]);
          if (s.isNotEmpty) {
            common = s;
            break;
          }
        }
        final titulo = (sci ??
            common ??
            _safeStr(data['titulo'] ?? data['title'] ?? 'Sin título'));

        // ===== timestamp (updated/created)
        DateTime? ts;
        final rawTs = (data['updatedAt'] ??
            data['updated_at'] ??
            data['createdAt'] ??
            data['created_at']);
        if (rawTs is Timestamp) {
          ts = rawTs.toDate();
        } else {
          final s = _safeStr(rawTs);
          if (s.isNotEmpty) ts = DateTime.tryParse(s);
        }

        // ===== thumbnail: cover_url o primera de media_urls
        String thumb = '';
        String urlDirecta = _safeStr(
            data['cover_url'] ?? data['thumbnail_url'] ?? data['thumb_url']);
        if (urlDirecta.isEmpty) {
          final firstFromList = _firstHttpFromList(data['media_urls']);
          if (firstFromList != null) urlDirecta = firstFromList;
        }
        if (urlDirecta.isNotEmpty) thumb = 'URL::$urlDirecta';

        // ===== armar mapa por proyecto
        mapa.putIfAbsent(
          keyProyecto,
              () => ProyectoResumen(
            id: keyProyecto,
            nombre: nombreProyecto[keyProyecto] ??
                (pid.isEmpty ? 'Sin proyecto' : 'Proyecto sin nombre'),
            local: [],
            nube: [],
          ),
        );

        final pr = mapa[keyProyecto]!;
        if (pr.nube.length < maxItemsPorOrigen) {
          pr.nube.add(ObsResumen(
            id: d.id,
            titulo: titulo.isEmpty ? 'Sin título' : titulo,
            nombreCientifico: sci,
            fecha: ts,
            thumb: thumb.isEmpty ? null : thumb,
            origen: 'nube',
          ));
        }
        if (nombreProyecto[keyProyecto] != null) {
          mapa[keyProyecto] = ProyectoResumen(
            id: pr.id,
            nombre: nombreProyecto[keyProyecto]!,
            local: pr.local,
            nube: pr.nube,
          );
        }

        cloudOk++;
        debugPrint(
            '[DASH][CLOUD] ${d.id} -> pid="$keyProyecto" title="$titulo" thumb=${thumb.isEmpty ? "NONE" : "URL"}');
      }

      debugPrint('[DASH] Cloud: OK=$cloudOk, descartadas=$cloudDesc');
    } else {
      debugPrint('[DASH] Cloud: uid nulo, omitiendo consulta.');
    }
  } catch (e) {
    debugPrint('[DASH] Error leyendo nube (borradores): $e');
  }

  // 3) Resolver nombres faltantes desde /proyectos
  if (fetchProyectoNombre != null) {
    for (final id in mapa.keys) {
      // No intentes resolver "__SIN_PROYECTO__"
      if (id == '__SIN_PROYECTO__') continue;

      if ((nombreProyecto[id] ?? '').isEmpty) {
        final resolved = await fetchProyectoNombre(id);
        if (resolved != null && resolved.isNotEmpty) {
          nombreProyecto[id] = resolved;
          final pr = mapa[id]!;
          mapa[id] = ProyectoResumen(
              id: pr.id, nombre: resolved, local: pr.local, nube: pr.nube);
          debugPrint('[DASH] Resuelto nombre proyecto $id => $resolved');
        }
      }
    }
  }

  // Orden y límite
  final list = mapa.values.toList()
    ..sort((a, b) => b.totalBorradores.compareTo(a.totalBorradores));
  final limited = list.take(maxProjects).toList();

  // Asegurar nombre final
  for (int i = 0; i < limited.length; i++) {
    final pr = limited[i];
    final name = nombreProyecto[pr.id] ?? pr.nombre;
    limited[i] = ProyectoResumen(
      id: pr.id,
      nombre: name.isNotEmpty
          ? name
          : (pr.id == '__SIN_PROYECTO__'
          ? 'Sin proyecto'
          : 'Proyecto sin nombre'),
      local: pr.local,
      nube: pr.nube,
    );
  }

  debugPrint('[DASH] Proyectos armados: ${limited.length}');
  for (final p in limited) {
    debugPrint(
        '[DASH] Proyecto "${p.nombre}" (id=${p.id}) -> local=${p.local.length}, nube=${p.nube.length}');
  }

  return limited;
}

class _ProyectosResumenCard extends StatefulWidget {
  final Future<String?> Function(String id) fetchProyectoNombre;
  final String? ctxRolCodigo;
  const _ProyectosResumenCard({
    required this.fetchProyectoNombre,
    this.ctxRolCodigo,
  });
  @override
  State<_ProyectosResumenCard> createState() => _ProyectosResumenCardState();
}

class _ProyectosResumenCardState extends State<_ProyectosResumenCard> {
  late Future<List<ProyectoResumen>> _future;

  @override
  void initState() {
    super.initState();
    _future = cargarProyectosConBorradores(
      fetchProyectoNombre: widget.fetchProyectoNombre,
      ctxRolCodigo: widget.ctxRolCodigo,
    );
  }

  @override
  void didUpdateWidget(covariant _ProyectosResumenCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ctxRolCodigo != widget.ctxRolCodigo) {
      setState(() {
        _future = cargarProyectosConBorradores(
          fetchProyectoNombre: widget.fetchProyectoNombre,
          ctxRolCodigo: widget.ctxRolCodigo,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<ProyectoResumen>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outline.withOpacity(.16)),
            ),
            child: const _LoadingRow(text: 'Cargando proyectos…'),
          );
        }
        final proyectos = snap.data ?? const <ProyectoResumen>[];
        if (proyectos.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outline.withOpacity(.16)),
            ),
            child: const Text(
              'No hay borradores locales o en la nube por proyecto.',
              style: TextStyle(color: Colors.black54),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outline.withOpacity(.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado con botón de actualizar a la derecha
              Row(
                children: [
                  const Icon(Icons.folder_special_outlined),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Proyectos y observaciones (borradores)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _future = cargarProyectosConBorradores(
                        fetchProyectoNombre: widget.fetchProyectoNombre,
                        ctxRolCodigo: widget.ctxRolCodigo,
                      );
                    }),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...proyectos.map((p) => _ProyectoItem(proyecto: p)).toList(),
            ],
          ),
        );
      },
    );
  }
}

class _ProyectoItem extends StatelessWidget {
  final ProyectoResumen proyecto;
  const _ProyectoItem({required this.proyecto});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline.withOpacity(.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado del proyecto (solo nombre + ícono)
            Row(
              children: [
                const Icon(Icons.folder_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    proyecto.nombre,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _SubListadoObservaciones(titulo: 'Local', items: proyecto.local),
            const SizedBox(height: 6),
            _SubListadoObservaciones(titulo: 'Nube', items: proyecto.nube),
          ],
        ),
      ),
    );
  }
}

class _SubListadoObservaciones extends StatelessWidget {
  final String titulo;
  final List<ObsResumen> items;
  const _SubListadoObservaciones({required this.titulo, required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(titulo == 'Local' ? Icons.phone_android : Icons.cloud_outlined,
              size: 16),
          const SizedBox(width: 6),
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: cs.surfaceVariant.withOpacity(.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child:
            Text('${items.length}', style: const TextStyle(fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 6),
        if (items.isEmpty)
          const Text('Sin borradores', style: TextStyle(color: Colors.black54))
        else
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _ObsChipCard(item: items[i]),
            ),
          ),
      ],
    );
  }
}

class _ObsChipCard extends StatelessWidget {
  final ObsResumen item;
  const _ObsChipCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget thumb = _thumbPlaceholder(cs);

    if (item.thumb != null && item.thumb!.isNotEmpty) {
      final mark = item.thumb!;
      if (mark.startsWith('URL::')) {
        final url = mark.substring(5);
        thumb = Image.network(url, width: 56, height: 56, fit: BoxFit.cover);
      } else if (mark.startsWith('FILE::')) {
        final path = mark.substring(6);
        if (!kIsWeb) {
          thumb =
              Image.file(File(path), width: 56, height: 56, fit: BoxFit.cover);
        } else {
          thumb = _thumbPlaceholder(cs); // en Web no hay File
        }
      } else {
        try {
          final bytes = base64Decode(mark);
          thumb = Image.memory(bytes, width: 56, height: 56, fit: BoxFit.cover);
        } catch (e) {
          debugPrint('[DASH] thumb base64 inválido: $e');
        }
      }
    }

    final fechaTxt = item.fecha != null ? _fmtFull(item.fecha!) : '—';
    final etiqueta = item.origen == 'local' ? 'Local' : 'Nube';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300, minWidth: 220),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline.withOpacity(.14)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: 56, height: 56, child: thumb),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 👇 título ya viene con científico/común priorizado
                  Text(item.titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  if (item.nombreCientifico != null)
                    Text(item.nombreCientifico!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: Colors.black87)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: item.origen == 'local'
                            ? Colors.orange.withOpacity(.22)
                            : cs.primaryContainer.withOpacity(.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child:
                      Text(etiqueta, style: const TextStyle(fontSize: 11)),
                    ),
                    const SizedBox(width: 8),
                    Text(fechaTxt,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black54)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbPlaceholder(ColorScheme cs) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
          child: Icon(Icons.photo, size: 20, color: Colors.black54)),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  final String text;
  const _LoadingRow({required this.text});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2)),
      const SizedBox(width: 10),
      Text(text),
    ]);
  }
}

// ===== utils =====
bool _isRecent(DateTime? d, {Duration maxAge = kVentanaBorradoresRecientes}) {
  if (d == null) return false;
  final now = DateTime.now();
  return now.difference(d).abs() <= maxAge;
}

String _fmtFull(DateTime d) {
  String t(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${t(d.month)}-${t(d.day)} ${t(d.hour)}:${t(d.minute)}';
}
