// lib/ui/screens/observaciones/lista_observaciones_screen.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:faunadmin2/models/observacion.dart';
import 'package:faunadmin2/providers/auth_provider.dart';
import 'package:faunadmin2/providers/observacion_provider.dart';
import 'package:faunadmin2/services/permisos_service.dart';

// Local storage (ya lo tienes)
import 'package:faunadmin2/services/local_file_storage.dart';

class ListaObservacionesScreen extends StatefulWidget {
  const ListaObservacionesScreen({super.key});

  @override
  State<ListaObservacionesScreen> createState() =>
      _ListaObservacionesScreenState();
}

class _ListaObservacionesScreenState extends State<ListaObservacionesScreen> {
  String? _filtroEstado; // null = todos
  String? _ctxProyectoId; // null => sin proyecto
  bool _soloMias = false;
  String _q = '';

  // Provider referenciado de forma segura para usar en dispose()
  late ObservacionProvider _obsProv;

  // locales
  final _local = LocalFileStorage.instance;
  List<_LocalObsItem> _localItems = [];
  bool _cargandoLocales = false;

  // caché de nombres de proyecto
  final Map<String, String> _projNameCache = {};

  // búsqueda
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Post frame: inicializamos contexto y streams
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // cacheamos provider para usarlo en dispose() sin hacer lookups
      _obsProv = context.read<ObservacionProvider>();

      final auth = context.read<AuthProvider>();
      final permisos = PermisosService(auth);

      _ctxProyectoId = auth.selectedRolProyecto?.idProyecto; // puede ser null
      final isSinProyecto = _ctxProyectoId == null || _ctxProyectoId!.isEmpty;
      final forzarSoloMias = (isSinProyecto && permisos.isRecolector);

      setState(() {
        _soloMias = forzarSoloMias; // recolector/sin-proyecto: forzado
      });

      // Stream en nube
      await _obsProv.watchProyecto(
        proyectoId: _ctxProyectoId,
        estado: _filtroEstado,
      );

      // Carga locales
      await _cargarLocales();
    });
  }

  @override
  void dispose() {
    // Usamos la referencia cacheada, NO el context
    _searchCtrl.dispose();
    _obsProv.stop();
    super.dispose();
  }

  Future<void> _cargarLocales() async {
    if (kIsWeb) return; // no hay FS en web
    setState(() => _cargandoLocales = true);
    try {
      final dirs = await _local.listarObservaciones();
      final list = <_LocalObsItem>[];

      final uidActual = context.read<AuthProvider>().uid;

      for (final dir in dirs) {
        final meta = await _local.leerMeta(dir);
        if (meta == null) continue;

        // Filtro rápido por estado seleccionado (si aplica)
        final estado = (meta['estado'] ?? '').toString().toLowerCase();
        if (_filtroEstado != null && estado != _filtroEstado) continue;

        // Si forzamos solo mías: comparamos uid
        final uidLocal = (meta['uid_usuario'] ?? '').toString();
        if (_soloMias && uidActual != null && uidLocal.isNotEmpty && uidLocal != uidActual) {
          continue;
        }

        // Proyecto en meta (puede ser null/empty)
        final idProyecto = (meta['id_proyecto'] ?? '').toString();

        // Primera foto para miniatura (si existe)
        File? thumb;
        try {
          final fotos = await _local.listarFotos(dir);
          if (fotos.isNotEmpty) thumb = fotos.first;
        } catch (_) {}

        list.add(_LocalObsItem(
          dir: dir,
          meta: meta,
          estado: estado.isEmpty ? EstadosObs.borrador : estado,
          idProyecto: idProyecto.isEmpty ? null : idProyecto,
          uidUsuario: uidLocal,
          thumb: thumb,
        ));
      }

      // ordenamos por created_local_at desc si existe
      list.sort((a, b) {
        final da = DateTime.tryParse((a.meta['created_local_at'] ?? '') as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db = DateTime.tryParse((b.meta['created_local_at'] ?? '') as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });

      setState(() => _localItems = list);
    } catch (_) {
      // swallow
    } finally {
      if (mounted) setState(() => _cargandoLocales = false);
    }
  }

  Future<String?> _fetchProyectoNombre(String id) async {
    if (_projNameCache.containsKey(id)) return _projNameCache[id];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('proyectos')
          .doc(id)
          .get();
      final nombre = (snap.data()?['nombre'] as String?)?.trim();
      if (nombre != null && nombre.isNotEmpty) {
        _projNameCache[id] = nombre;
        if (mounted) setState(() {}); // refresca las cards que dependan
        return nombre;
      }
    } catch (_) {}
    return null;
  }

  void _onCambiarFiltro(String? nuevo) async {
    setState(() => _filtroEstado = nuevo);
    await _obsProv.setEstadoFiltro(nuevo);
    await _cargarLocales();
  }

  Future<void> _onToggleSoloMias(bool v) async {
    setState(() => _soloMias = v);
    // En la nube: re-suscribir respetando _ctxProyectoId y _filtroEstado
    await _obsProv.refresh();
    await _cargarLocales();
  }

  void _onBuscarChanged(String s) {
    setState(() => _q = s.trim().toLowerCase());
  }

  bool _matchesQuery(_UiItem it) {
    if (_q.isEmpty) return true;

    String especie = '';
    String lugar = '';
    if (it.isLocal) {
      especie = ((it.local!.meta['especie_nombre'] ?? '') as String? ?? '').toLowerCase();
      lugar   = ((it.local!.meta['lugar_nombre']   ?? '') as String? ?? '').toLowerCase();
    } else {
      especie = (it.cloud!.especieNombre ?? '').toLowerCase();
      lugar   = (it.cloud!.lugarNombre   ?? '').toLowerCase();
    }
    return especie.contains(_q) || lugar.contains(_q);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final obsProv = context.watch<ObservacionProvider>();
    final permisos = PermisosService(auth);

    final puedeAprobar = permisos.canApproveObservation;
    final puedeCrearEnProyecto = (_ctxProyectoId != null && _ctxProyectoId!.isNotEmpty)
        ? permisos.canCreateObservationInProject(_ctxProyectoId!)
        : false;
    final puedeCrearSinProyecto = permisos.canCreateObservationSinProyecto;

    final isRecolectorSinProyecto =
    (permisos.isRecolector && (_ctxProyectoId == null || _ctxProyectoId!.isEmpty));

    // Construimos la lista combinada (cloud + local)
    final items = <_UiItem>[];
    // Cloud primero
    for (final o in obsProv.observaciones) {
      items.add(_UiItem.cloud(o));
    }
    // Luego locales (badge LOCAL)
    for (final lo in _localItems) {
      // si hay proyecto en pantalla y el local es de otro proyecto, no lo mostramos
      if ((_ctxProyectoId ?? '').isNotEmpty && lo.idProyecto != _ctxProyectoId) continue;
      items.add(_UiItem.local(lo));
    }

    // Filtro de búsqueda (client-side)
    final filtered = items.where(_matchesQuery).toList();

    String? ctxNombreProyecto;
    if (_ctxProyectoId != null && _ctxProyectoId!.isNotEmpty) {
      ctxNombreProyecto = _projNameCache[_ctxProyectoId!];
      if (ctxNombreProyecto == null) {
        // Carga perezosa del nombre y refresca cuando llegue
        _fetchProyectoNombre(_ctxProyectoId!);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Observaciones')),
      body: Column(
        children: [
          _CtxBanner(
            proyectoId: _ctxProyectoId,
            proyectoNombre: ctxNombreProyecto,
          ),

          // filtros estado
          _FiltrosEstado(seleccionado: _filtroEstado, onChanged: _onCambiarFiltro),

          // búsqueda
          _BuscarBox(controller: _searchCtrl, onChanged: _onBuscarChanged),

          // toggle "solo mías" (oculto si forzado para recolector/sin-proyecto)
          if (!isRecolectorSinProyecto)
            _RowSoloMias(
              value: _soloMias,
              onChanged: _onToggleSoloMias,
            ),

          const Divider(height: 1),

          Expanded(
            child: (obsProv.isLoading && obsProv.observaciones.isEmpty && _cargandoLocales)
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
              onRefresh: () async {
                await obsProv.refresh();
                await _cargarLocales();
              },
              child: filtered.isEmpty
                  ? ListView(
                children: [
                  const SizedBox(height: 140),
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 48,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withOpacity(.6),
                  ),
                  const SizedBox(height: 8),
                  Text('Sin observaciones',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Crea una nueva observación con el botón “Agregar”.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              )
                  : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final it = filtered[i];

                  // Resuelve nombre de proyecto si aplica (con caché)
                  String? proyectoNombre;
                  final String? pid =
                  it.isLocal ? it.local!.idProyecto : it.cloud?.idProyecto;
                  if (pid != null && pid.isNotEmpty) {
                    proyectoNombre = _projNameCache[pid];
                    if (proyectoNombre == null) {
                      _fetchProyectoNombre(pid); // dispara en background
                    }
                  }

                  // Acciones/ navegación según tipo + permisos
                  VoidCallback? onTap;

                  if (it.isLocal) {
                    // Editar local
                    onTap = () {
                      Navigator.pushNamed(
                        context,
                        '/observaciones/editLocal',
                        arguments: {
                          'dirPath': it.local!.dir.path,
                          'meta': it.local!.meta,
                        },
                      ).then((_) async {
                        await _cargarLocales();
                      });
                    };
                  } else {
                    final o = it.cloud!;
                    // Omitir si no hay ID (evita rutas inválidas)
                    if (o.id == null || o.id!.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    final soyAutor =
                        auth.uid != null && o.uidUsuario == auth.uid;

                    if (puedeAprobar) {
                      // Moderador: ir a aprobar/detalle
                      onTap = () {
                        Navigator.pushNamed(
                          context,
                          '/observaciones/approve',
                          arguments: o.id!,
                        );
                      };
                    } else if (soyAutor &&
                        (o.estado == EstadosObs.borrador ||
                            o.estado == EstadosObs.rechazado)) {
                      // Autor puede editar si está en borrador o rechazado
                      onTap = () {
                        Navigator.pushNamed(
                          context,
                          '/observaciones/edit',
                          arguments: {
                            'mode': 'cloud',
                            'obsId': o.id!,
                          },
                        ).then((_) async {
                          await _obsProv.refresh();
                          await _cargarLocales();
                        });
                      };
                    } else {
                      // Solo lectura (pantalla de edición en readonly)
                      onTap = () {
                        Navigator.pushNamed(
                          context,
                          '/observaciones/edit',
                          arguments: {
                            'mode': 'cloud',
                            'obsId': o.id!,
                            'readonly': true,
                          },
                        ).then((_) async {
                          await _obsProv.refresh();
                          await _cargarLocales();
                        });
                      };
                    }
                  }

                  return _ObsCardFancy(
                    item: it,
                    proyectoNombre: proyectoNombre,
                    // Botón "Revisar" solo si hay onTap válido
                    trailing: (onTap != null)
                        ? TextButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.rate_review_outlined, size: 18),
                      label: const Text('Revisar'),
                    )
                        : null,
                    onTap: onTap,
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _FabObservaciones(
        proyectoId: _ctxProyectoId,
        puedeCrearEnProyecto: puedeCrearEnProyecto,
        puedeCrearSinProyecto: puedeCrearSinProyecto,
        uidActual: auth.uid,
      ),
    );
  }
}

// ======== UI bits ========

class _CtxBanner extends StatelessWidget {
  final String? proyectoId;
  final String? proyectoNombre;
  const _CtxBanner({required this.proyectoId, required this.proyectoNombre});

  @override
  Widget build(BuildContext context) {
    final isSinProyecto = (proyectoId == null || proyectoId!.isEmpty);
    final label = isSinProyecto
        ? 'Sin proyecto'
        : 'Proyecto: ${proyectoNombre ?? proyectoId}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6),
      ),
      child: Row(
        children: [
          Icon(isSinProyecto ? Icons.public : Icons.work_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _BuscarBox extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _BuscarBox({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Buscar por especie o lugar…',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

class _RowSoloMias extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _RowSoloMias({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilterChip(
          label: const Text('Solo mis observaciones'),
          selected: value,
          onSelected: onChanged,
        ),
      ),
    );
  }
}

class _FiltrosEstado extends StatelessWidget {
  final String? seleccionado;
  final ValueChanged<String?> onChanged;
  const _FiltrosEstado({required this.seleccionado, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, String? value) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: seleccionado == value,
        onSelected: (_) => onChanged(value),
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          chip('Todos', null),
          chip('Borrador', EstadosObs.borrador),
          chip('Pendiente', EstadosObs.pendiente),
          chip('Aprobado', EstadosObs.aprobado),
          chip('Rechazado', EstadosObs.rechazado),
          chip('Archivado', EstadosObs.archivado),
        ],
      ),
    );
  }
}

// ======== Card fancy (presentación mejorada) ========

class _ObsCardFancy extends StatelessWidget {
  final _UiItem item;
  final String? proyectoNombre;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _ObsCardFancy({
    required this.item,
    required this.proyectoNombre,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final o = item.cloud;
    final lo = item.local;

    final estado = item.isLocal ? (lo!.estado) : (o!.estado);
    final lugar = item.isLocal
        ? ((lo!.meta['lugar_nombre'] ?? '') as String? ?? '')
        : (o!.lugarNombre ?? '');
    final especie = item.isLocal
        ? ((lo!.meta['especie_nombre'] ?? '') as String? ?? '')
        : (o!.especieNombre ?? '');

    final fecha = item.isLocal
        ? _fmtDate(_parseDate(lo!.meta['fecha_captura']))
        : _fmtDate(o!.fechaCaptura);

    final thumb = item.isLocal ? lo!.thumb : null; // nube: si tienes URLs, muéstralas

    final badgeLocal = item.isLocal
        ? Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        'LOCAL',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onTertiaryContainer,
        ),
      ),
    )
        : const SizedBox.shrink();

    final estadoChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _estadoColor(context, estado).withOpacity(.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _estadoColor(context, estado).withOpacity(.4)),
      ),
      child: Text(
        estado[0].toUpperCase() + estado.substring(1),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _estadoColor(context, estado),
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    // Material + InkWell para garantizar hit-test correcto en toda la card
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        mouseCursor: onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).dividerColor.withOpacity(.6),
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumb
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: thumb != null
                      ? Image.file(thumb, fit: BoxFit.cover)
                      : Container(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceVariant
                        .withOpacity(.5),
                    child: const Icon(Icons.photo_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Texto
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // primera línea: especie + estado + LOCAL
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (especie.isEmpty) ? 'Sin especie' : especie,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        estadoChip,
                        const SizedBox(width: 6),
                        badgeLocal,
                      ],
                    ),

                    // segunda: nombre de proyecto (si hay)
                    if ((proyectoNombre ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.work_outline, size: 14),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                proyectoNombre!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // tercera: fecha y lugar
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.event_outlined, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            fecha ?? '—',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if ((lugar).trim().isNotEmpty) ...[
                            const SizedBox(width: 10),
                            const Icon(Icons.place_outlined, size: 14),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                lugar,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _estadoColor(BuildContext context, String estado) {
    final cs = Theme.of(context).colorScheme;
    switch (estado) {
      case EstadosObs.borrador:
        return cs.secondary;
      case EstadosObs.pendiente:
        return cs.primary;
      case EstadosObs.aprobado:
        return Colors.green.shade700;
      case EstadosObs.rechazado:
        return Colors.red.shade700;
      case EstadosObs.archivado:
        return cs.outline;
      default:
        return cs.onSurfaceVariant;
    }
  }

  String? _fmtDate(DateTime? d) {
    if (d == null) return null;
    String t(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${t(d.month)}-${t(d.day)}';
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) {
      try {
        if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) {
          final p = v.split('-').map(int.parse).toList();
          return DateTime(p[0], p[1], p[2]);
        }
        return DateTime.tryParse(v);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

// ======== FAB (sin cambios funcionales) ========

class _FabObservaciones extends StatelessWidget {
  final String? proyectoId;
  final bool puedeCrearEnProyecto;
  final bool puedeCrearSinProyecto;
  final String? uidActual;

  const _FabObservaciones({
    required this.proyectoId,
    required this.puedeCrearEnProyecto,
    required this.puedeCrearSinProyecto,
    required this.uidActual,
  });

  @override
  Widget build(BuildContext context) {
    final can = (proyectoId != null && proyectoId!.isNotEmpty)
        ? puedeCrearEnProyecto
        : puedeCrearSinProyecto;
    if (!can || uidActual == null) return const SizedBox.shrink();

    return FloatingActionButton.extended(
      onPressed: () {
        Navigator.pushNamed(
          context,
          '/observaciones/add',
          arguments: {
            'proyectoId': proyectoId,
            'uidUsuario': uidActual,
          },
        );
      },
      icon: const Icon(Icons.add),
      label: const Text('Agregar'),
    );
  }
}

// ======== Modelos auxiliares de UI ========

class _UiItem {
  final Observacion? cloud;
  final _LocalObsItem? local;
  final bool isLocal;

  _UiItem.cloud(this.cloud)
      : local = null,
        isLocal = false;

  _UiItem.local(this.local)
      : cloud = null,
        isLocal = true;
}

class _LocalObsItem {
  final Directory dir;
  final Map<String, dynamic> meta;
  final String estado;
  final String? idProyecto;
  final String uidUsuario;
  final File? thumb;

  _LocalObsItem({
    required this.dir,
    required this.meta,
    required this.estado,
    required this.idProyecto,
    required this.uidUsuario,
    required this.thumb,
  });
}
