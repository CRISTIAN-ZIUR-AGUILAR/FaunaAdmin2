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
import 'package:faunadmin2/services/local_file_storage.dart';
import 'package:faunadmin2/services/firestore_service.dart';

import '../../../services/foto_service.dart';
import 'detalle_observacion_local_screen.dart';

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

  late ObservacionProvider _obsProv;

  // locales
  final _local = LocalFileStorage.instance;
  List<_LocalObsItem> _localItems = [];
  bool _cargandoLocales = false;

  // caché de nombres de proyecto
  final Map<String, String> _projNameCache = {};

  // búsqueda / scroll
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    _obsProv = context.read<ObservacionProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (!mounted || _bootstrapped) return;
    _bootstrapped = true;

    _obsProv = context.read<ObservacionProvider>();
    final auth = context.read<AuthProvider>();
    final permisos = PermisosService(auth);

    // 1) proyectoId desde argumentos
    String? proyectoIdArg;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['proyectoId'] is String) {
      final v = (args['proyectoId'] as String).trim();
      if (v.isNotEmpty) proyectoIdArg = v;
    }

    // 2) o el contexto seleccionado
    _ctxProyectoId = proyectoIdArg ?? auth.selectedRolProyecto?.idProyecto;

    // 3) Recolector sin proyecto => forzar "solo mías"
    final isSinProyecto = _ctxProyectoId == null || _ctxProyectoId!.isEmpty;
    setState(() => _soloMias = (isSinProyecto && permisos.isRecolector));

    // 4) vincular streams y cargar locales
    await _rebindProvider();
    await _cargarLocales();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _obsProv.stop();
    super.dispose();
  }

  /// Re-bindea el provider según proyecto/estado actuales
  Future<void> _rebindProvider() async {
    final isSinProyecto = _ctxProyectoId == null || _ctxProyectoId!.isEmpty;

    // ⚠️ si el filtro es "Revisión" (pendiente), no pasamos estado
    // para que el provider traiga ambos: pendiente + revisar_nuevo.
    final estadoParam =
    (_filtroEstado == EstadosObs.pendiente) ? null : _filtroEstado;

    if (!isSinProyecto) {
      await _obsProv.watchProyecto(
        proyectoId: _ctxProyectoId,
        estado: estadoParam,
      );
    } else {
      // Sin proyecto: sólo el Admin debe ver TODAS las sin proyecto.
      // Supervisores no deben ver observaciones sin proyecto de otros usuarios.
      final auth = context.read<AuthProvider>();
      final permisos = PermisosService(auth);
      final incluirSinProyectoSoloAdmin = permisos.isAdminUnico;

      await _obsProv.watchAuto(
        estado: estadoParam,
        incluirSinProyectoParaModeradores: incluirSinProyectoSoloAdmin,
      );
    }
  }

  Future<void> _cargarLocales() async {
    if (kIsWeb) return;
    setState(() => _cargandoLocales = true);
    try {
      final dirs = await _local.listarObservaciones();
      final list = <_LocalObsItem>[];
      final uidActual = context.read<AuthProvider>().uid;

      final bool isSinProyecto =
          _ctxProyectoId == null || _ctxProyectoId!.isEmpty;

      for (final dir in dirs) {
        final meta = await _local.leerMeta(dir);
        if (meta == null) continue;

        final estado = (meta['estado'] ?? '').toString().toLowerCase();

        // Si filtras Revisión (pendiente), incluye revisar_nuevo
        if (_filtroEstado != null) {
          final f = _filtroEstado!;
          final matchRevision = (f == EstadosObs.pendiente) &&
              (estado == EstadosObs.pendiente ||
                  estado == EstadosObs.revisarNuevo);
          final matchExacto = (estado == f);
          if (!(matchRevision || matchExacto)) continue;
        }

        final uidLocal = (meta['uid_usuario'] ?? '').toString();
        if (_soloMias &&
            uidActual != null &&
            uidLocal.isNotEmpty &&
            uidLocal != uidActual) continue;

        final idProyecto = (meta['id_proyecto'] ?? '').toString();

        // Filtro local por contexto:
        // - Con proyecto en contexto => solo locales de ese proyecto
        // - Sin proyecto => solo locales SIN proyecto
        if (!isSinProyecto) {
          if (idProyecto != _ctxProyectoId) continue;
        } else {
          if (idProyecto.isNotEmpty) continue; // solo sin proyecto
        }

        File? thumb;
        try {
          final fotos = await _local.listarFotos(dir);
          if (fotos.isNotEmpty) thumb = fotos.first;
        } catch (_) {}

        list.add(
          _LocalObsItem(
            dir: dir,
            meta: meta,
            estado: estado.isEmpty ? EstadosObs.borrador : estado,
            idProyecto: idProyecto.isEmpty ? null : idProyecto,
            uidUsuario: uidLocal,
            thumb: thumb,
          ),
        );
      }

      list.sort((a, b) {
        final da = DateTime.tryParse(
          (a.meta['created_local_at'] ?? '') as String? ?? '',
        ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final db = DateTime.tryParse(
          (b.meta['created_local_at'] ?? '') as String? ?? '',
        ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
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
      final snap =
      await FirebaseFirestore.instance.collection('proyectos').doc(id).get();
      final nombre = (snap.data()?['nombre'] as String?)?.trim();
      if (nombre != null && nombre.isNotEmpty) {
        _projNameCache[id] = nombre;
        if (mounted) setState(() {});
        return nombre;
      }
    } catch (_) {}
    return null;
  }

  void _onCambiarFiltro(String? nuevo) async {
    setState(() => _filtroEstado = nuevo);
    await _rebindProvider();
    await _cargarLocales();
  }

  Future<void> _onToggleSoloMias(bool v) async {
    setState(() => _soloMias = v);
    await _rebindProvider();
    await _cargarLocales();
  }

  void _onBuscarChanged(String s) =>
      setState(() => _q = s.trim().toLowerCase());

  void _clearSearch() {
    _searchCtrl.clear();
    _onBuscarChanged('');
  }

  // helpers especie (cloud/local) con compat
  String _localEspecie(Map<String, dynamic> meta) {
    final cient =
    (meta['especie_nombre_cientifico'] ?? meta['especie_nombre'])
        ?.toString()
        .trim();
    if (cient != null && cient.isNotEmpty) return cient;
    return (meta['especie_nombre_comun'] ?? '').toString().trim();
  }

  String _cloudEspecie(Observacion o) {
    final cient = (o.especieNombreCientifico ?? '').toString().trim();
    if (cient.isNotEmpty) return cient;
    return (o.especieNombreComun ?? '').toString().trim();
  }

  bool _matchesQuery(_UiItem it) {
    if (_q.isEmpty) return true;

    String especie = '', lugar = '', municipio = '', estadoPais = '';

    if (it.isLocal) {
      final m = it.local!.meta;
      especie = _localEspecie(m).toLowerCase();
      lugar = ((m['lugar_nombre'] ?? '') as String? ?? '').toLowerCase();
      municipio = ((m['municipio'] ?? '') as String? ?? '').toLowerCase();
      estadoPais = ((m['estado_pais'] ?? '') as String? ?? '').toLowerCase();
    } else {
      final o = it.cloud!;
      especie = _cloudEspecie(o).toLowerCase();
      lugar = (o.lugarNombre ?? '').toLowerCase();
      municipio = (o.municipio ?? '').toLowerCase();
      estadoPais = (o.estadoPais ?? '').toLowerCase();
    }

    return especie.contains(_q) ||
        lugar.contains(_q) ||
        municipio.contains(_q) ||
        estadoPais.contains(_q);
  }

  // ⬇️ filtro de estado que trata "Revisión" como pendiente || revisar_nuevo
  bool _matchesEstado(_UiItem it) {
    if (_filtroEstado == null) return true;

    final e = it.isLocal
        ? it.local!.estado
        : (it.cloud!.estado).toLowerCase();

    if (_filtroEstado == EstadosObs.pendiente) {
      return e == EstadosObs.pendiente || e == EstadosObs.revisarNuevo;
    }
    return e == _filtroEstado;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final obsProv = context.watch<ObservacionProvider>();
    final permisos = PermisosService(auth);

    final bool isSinProyecto =
        _ctxProyectoId == null || _ctxProyectoId!.isEmpty;
    final bool isRecolectorSinProyectoUI = permisos.isRecolectorSinProyecto;

    final puedeCrearEnProyecto =
    (_ctxProyectoId != null && _ctxProyectoId!.isNotEmpty)
        ? permisos.canCreateObservationInProject(_ctxProyectoId!)
        : false;
    final puedeCrearSinProyecto = permisos.canCreateObservationSinProyecto;

    // construir lista combinada (cloud + local)
    final items = <_UiItem>[];

    for (final o in obsProv.observaciones) {
      // Filtro por proyecto / sin proyecto en nube
      if (!isSinProyecto) {
        // vista desde un proyecto: solo obs de ese proyecto
        if (o.idProyecto != _ctxProyectoId) continue;
      } else {
        // vista general "Observaciones" sin proyecto:
        // solo obs SIN proyecto (admin verá las de todos los usuarios)
        if (o.idProyecto != null && o.idProyecto!.isNotEmpty) continue;
      }

      if (_soloMias && (auth.uid != null) && o.uidUsuario != auth.uid) {
        continue;
      }
      items.add(_UiItem.cloud(o));
    }

    for (final lo in _localItems) {
      // ya vienen filtradas en _cargarLocales() según _ctxProyectoId,
      // aquí solo las agregamos
      items.add(_UiItem.local(lo));
    }

    // primero por estado, luego por búsqueda
    final byEstado = items.where(_matchesEstado).toList();
    final filtered = byEstado.where(_matchesQuery).toList();

    String? ctxNombreProyecto;
    if (_ctxProyectoId != null && _ctxProyectoId!.isNotEmpty) {
      ctxNombreProyecto = _projNameCache[_ctxProyectoId!];
      if (ctxNombreProyecto == null) _fetchProyectoNombre(_ctxProyectoId!);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Observaciones'),
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: () async {
              await _rebindProvider();
              await _cargarLocales();
              if (_scrollCtrl.hasClients) {
                _scrollCtrl.animateTo(
                  0,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOut,
                );
              }
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _CtxBanner(
            proyectoId: _ctxProyectoId,
            proyectoNombre: ctxNombreProyecto,
          ),
          _FiltrosEstado(
            seleccionado: _filtroEstado,
            onChanged: _onCambiarFiltro,
          ),
          _BuscarBox(
            controller: _searchCtrl,
            onChanged: _onBuscarChanged,
            onClear: _clearSearch,
          ),
          if (!isRecolectorSinProyectoUI)
            _RowSoloMias(
              value: _soloMias,
              onChanged: _onToggleSoloMias,
            ),
          const Divider(height: 1),
          Expanded(
            child: (obsProv.isLoading &&
                obsProv.observaciones.isEmpty &&
                _cargandoLocales)
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
              onRefresh: () async {
                await _rebindProvider();
                await _cargarLocales();
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final int columns =
                  (width >= 1100) ? 3 : (width >= 700) ? 2 : 1;

                  if (filtered.isEmpty) {
                    return ListView(
                      controller: _scrollCtrl,
                      children: [
                        const SizedBox(height: 140),
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 56,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withOpacity(.55),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Sin observaciones',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24),
                          child: Text(
                            'Crea una nueva observación con el botón “Agregar”.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  if (columns == 1) {
                    return ListView.separated(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.all(12),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                      const SizedBox(height: 10),
                      itemBuilder: (_, i) => _buildItemCard(
                        context,
                        filtered[i],
                        _obsProv,
                      ),
                    );
                  }

                  const double kCardExtent = 200;
                  return GridView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                    SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: kCardExtent,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _buildItemCard(
                      context,
                      filtered[i],
                      _obsProv,
                    ),
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
        afterAdded: () async {
          await _rebindProvider();
          await _cargarLocales();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Observación agregada')),
            );
          }
        },
      ),
    );
  }

  Widget _buildItemCard(
      BuildContext context,
      _UiItem it,
      ObservacionProvider obsProv,
      ) {
    // Resuelve nombre del proyecto si aplica
    String? proyectoNombre;
    final String? pid =
    it.isLocal ? it.local!.idProyecto : it.cloud?.idProyecto;
    if (pid != null && pid.isNotEmpty) {
      proyectoNombre = _projNameCache[pid];
      if (proyectoNombre == null) _fetchProyectoNombre(pid);
    }

    VoidCallback? onTap;
    if (it.isLocal) {
      onTap = () {
        final oLocal = _toObservacionLocal(it.local!);
        Navigator.of(context)
            .push(
          MaterialPageRoute(
            builder: (_) => DetalleObservacionLocalScreen(
              observacion: oLocal,
              baseDir: it.local!.dir.path,
            ),
          ),
        )
            .then((_) async => await _cargarLocales());
      };
    } else {
      final o = it.cloud!;
      if (o.id == null || o.id!.isEmpty) return const SizedBox.shrink();
      onTap = () {
        Navigator.pushNamed(
          context,
          '/observaciones/detalle',
          arguments: o.id!,
        ).then((_) async {
          await _rebindProvider();
          await _cargarLocales();
        });
      };
    }

    return _ObsCardFancy(
      item: it,
      proyectoNombre: proyectoNombre,
      trailing: _ActionButtons(
        item: it,
        refreshAfterNav: () async {
          await _rebindProvider();
          await _cargarLocales();
        },
      ),
      onTap: onTap,
    );
  }
}

// ======== UI bits ========

class _CtxBanner extends StatelessWidget {
  final String? proyectoId;
  final String? proyectoNombre;

  const _CtxBanner({
    required this.proyectoId,
    required this.proyectoNombre,
  });

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
        color: Theme.of(context)
            .colorScheme
            .surfaceVariant
            .withOpacity(0.55),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(isSinProyecto ? Icons.public : Icons.work_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _BuscarBox extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _BuscarBox({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    controller
      ..removeListener(_noop)
      ..addListener(_noop);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: SizedBox(
        height: 44,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            suffixIcon: (controller.text.isNotEmpty)
                ? IconButton(
              tooltip: 'Limpiar',
              onPressed: onClear,
              icon: const Icon(Icons.clear),
            )
                : null,
            hintText:
            'Buscar por especie (científico/común), lugar, municipio o estado…',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            isDense: true,
          ),
        ),
      ),
    );
  }

  void _noop() {}
}

class _RowSoloMias extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _RowSoloMias({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
      const EdgeInsets.only(left: 8, right: 8, bottom: 6, top: 6),
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

  const _FiltrosEstado({
    required this.seleccionado,
    required this.onChanged,
  });

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
          chip('Revisión', EstadosObs.pendiente),
          chip('Aprobado', EstadosObs.aprobado),
          chip('Rechazado', EstadosObs.rechazado),
          chip('Archivado', EstadosObs.archivado),
        ],
      ),
    );
  }
}

// ======== Card fancy ========

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

    final rawEstado = item.isLocal ? (lo!.estado) : (o!.estado);
    final estado = (rawEstado.isEmpty) ? EstadosObs.borrador : rawEstado;

    String _cap(String s) =>
        (s.isEmpty) ? '—' : (s[0].toUpperCase() + s.substring(1));

    String _estadoLabel(String e) {
      switch (e) {
        case EstadosObs.pendiente:
          return 'Revisión';
        case EstadosObs.revisarNuevo:
          return 'Revisión (reenvío)';
        case EstadosObs.borrador:
          return 'Borrador';
        case EstadosObs.aprobado:
          return 'Aprobado';
        case EstadosObs.rechazado:
          return 'Rechazado';
        case EstadosObs.archivado:
          return 'Archivado';
        default:
          return _cap(e);
      }
    }

    final lugar = item.isLocal
        ? ((lo!.meta['lugar_nombre'] ?? '') as String? ?? '')
        : (o!.lugarNombre ?? '');
    final especie =
    item.isLocal ? _localEspecie(lo!.meta) : _cloudEspecie(o!);
    final fecha = item.isLocal
        ? _fmtDate(_parseDate(lo!.meta['fecha_captura']))
        : _fmtDate(o!.fechaCaptura);

    final File? thumbLocal = item.isLocal ? lo!.thumb : null;

    final String? thumbUrl = item.isLocal
        ? null
        : (() {
      try {
        final c = (o?.coverUrl ?? '').toString().trim();
        if (c.isNotEmpty && c.startsWith('http')) return c;
        final media = o?.mediaUrls ?? const [];
        if (media.isNotEmpty && media.first.startsWith('http')) {
          return media.first;
        }
      } catch (_) {}
      return null;
    })();

    final badgeLocal = item.isLocal
        ? Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        'LOCAL',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context)
              .colorScheme
              .onTertiaryContainer,
        ),
      ),
    )
        : const SizedBox.shrink();

    final estadoChip = Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _estadoColor(context, estado).withOpacity(.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _estadoColor(context, estado).withOpacity(.35),
        ),
      ),
      child: Text(
        _estadoLabel(estado),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _estadoColor(context, estado),
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 0.5,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        mouseCursor: onTap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
              Theme.of(context).dividerColor.withOpacity(.45),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumb (84x84)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: item.isLocal
                      ? (thumbLocal != null
                      ? Image.file(
                    thumbLocal,
                    fit: BoxFit.cover,
                  )
                      : _thumbPlaceholder(context))
                      : (thumbUrl != null &&
                      thumbUrl.startsWith('http'))
                      ? Image.network(
                    thumbUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _brokenThumbPlaceholder(
                            context),
                  )
                      : _thumbPlaceholder(context),
                ),
              ),
              const SizedBox(width: 12),

              // Texto
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    // primera línea: especie + estado + LOCAL
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (especie.isEmpty)
                                ? 'Sin especie'
                                : especie,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontStyle:
                              FontStyle.italic,
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
                        padding:
                        const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.work_outline,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                proyectoNombre!,
                                maxLines: 1,
                                overflow:
                                TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                  color: Theme.of(
                                      context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // tercera: fecha y lugar
                    Padding(
                      padding:
                      const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.event_outlined,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            fecha ?? '—',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall,
                          ),
                          if (lugar.trim().isNotEmpty) ...[
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.place_outlined,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                lugar,
                                maxLines: 1,
                                overflow:
                                TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    if (trailing != null) ...[
                      const SizedBox(height: 10),
                      trailing!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbPlaceholder(BuildContext context) => Container(
    color: Theme.of(context)
        .colorScheme
        .surfaceVariant
        .withOpacity(.45),
    child: const Icon(Icons.photo_outlined),
  );

  Widget _brokenThumbPlaceholder(BuildContext context) =>
      Container(
        color: Theme.of(context)
            .colorScheme
            .surfaceVariant
            .withOpacity(.45),
        child: const Icon(Icons.broken_image_outlined),
      );

  Color _estadoColor(BuildContext context, String estado) {
    final cs = Theme.of(context).colorScheme;
    switch (estado) {
      case EstadosObs.borrador:
        return cs.secondary;
      case EstadosObs.pendiente:
      case EstadosObs.revisarNuevo:
        return cs.primary;
      case EstadosObs.aprobado:
        return Colors.green;
      case EstadosObs.rechazado:
        return Colors.red;
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

  // helpers especie dentro de la card (shadow de los globales)
  String _localEspecie(Map<String, dynamic> meta) {
    final cient =
    (meta['especie_nombre_cientifico'] ?? meta['especie_nombre'])
        ?.toString()
        .trim();
    if (cient != null && cient.isNotEmpty) return cient;
    return (meta['especie_nombre_comun'] ?? '').toString().trim();
  }

  String _cloudEspecie(Observacion o) {
    final cient =
    (o.especieNombreCientifico ?? '').toString().trim();
    if (cient.isNotEmpty) return cient;
    return (o.especieNombreComun ?? '').toString().trim();
  }
}

// ======== FAB ========

class _FabObservaciones extends StatelessWidget {
  final String? proyectoId;
  final bool puedeCrearEnProyecto;
  final bool puedeCrearSinProyecto;
  final String? uidActual;
  final Future<void> Function()? afterAdded;

  const _FabObservaciones({
    required this.proyectoId,
    required this.puedeCrearEnProyecto,
    required this.puedeCrearSinProyecto,
    required this.uidActual,
    this.afterAdded,
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
        ).then((res) async {
          if (res is Map && res['success'] == true) {
            await afterAdded?.call();
          }
        });
      },
      icon: const Icon(Icons.add),
      label: const Text('Agregar'),
    );
  }
}

// ======== Acciones (Ver / Editar / Aprobar / Eliminar) ========

class _ActionButtons extends StatelessWidget {
  final _UiItem item;
  final Future<void> Function()? refreshAfterNav;

  const _ActionButtons({
    required this.item,
    this.refreshAfterNav,
  });

  @override
  Widget build(BuildContext context) {
    if (item.isLocal) {
      return Wrap(
        spacing: 10,
        runSpacing: 6,
        children: [
          // Ver (igual que antes)
          TextButton.icon(
            onPressed: () {
              final oLocal = _toObservacionLocal(item.local!);
              Navigator.pushNamed(
                context,
                '/observaciones/detalle_local',
                arguments: {
                  'obs': oLocal,
                  'dirPath': item.local!.dir.path,
                },
              ).then((_) async => await refreshAfterNav?.call());
            },
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Ver'),
          ),

          // Subir a nube (conserva estado y datos del meta.json)
          TextButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  icon: const Icon(Icons.cloud_upload_outlined, size: 48),
                  title: const Text('Subir a la nube'),
                  content: const Text(
                    'Se subirá esta observación local a la nube con los datos actuales '
                        '(estado, especie, fecha, etc.). '
                        'No se modificará el contenido local.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          Navigator.of(ctx).pop(false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.cloud_upload),
                      onPressed: () =>
                          Navigator.of(ctx).pop(true),
                      label: const Text('Subir'),
                    ),
                  ],
                ),
              );

              if (ok == true) {
                // Loader
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) =>
                  const Center(child: CircularProgressIndicator()),
                );

                try {
                  final auth = context.read<AuthProvider>();

                  FirestoreService fs;
                  try {
                    fs = context.read<FirestoreService>();
                  } catch (_) {
                    fs = FirestoreService();
                  }

                  await _publicarLocal(
                    context: context,
                    auth: auth,
                    fs: fs,
                    item: item.local!,
                    ctxProyectoId: context
                        .findAncestorStateOfType<
                        _ListaObservacionesScreenState>()
                        ?._ctxProyectoId,
                    mantenerEstado: true,
                  );

                  if (context.mounted) {
                    Navigator.of(context).pop(); // cierra loader
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                        Text('Observación subida a la nube'),
                      ),
                    );
                  }
                  await refreshAfterNav?.call();
                } catch (e) {
                  if (context.mounted) {
                    Navigator.of(context).pop(); // cierra loader
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error al subir: $e'),
                      ),
                    );
                  }
                }
              }
            },
            icon: const Icon(Icons.cloud_upload_outlined, size: 18),
            label: const Text('Subir a nube'),
          ),

          // Eliminar local
          TextButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  icon: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                    size: 48,
                  ),
                  title: const Text('Eliminar borrador local'),
                  content: const Text(
                    'Esto eliminará definitivamente la carpeta local y sus fotos.\n'
                        'Esta acción no se puede deshacer.\n\n'
                        '¿Deseas continuar?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          Navigator.of(ctx).pop(false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.delete_forever),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () =>
                          Navigator.of(ctx).pop(true),
                      label: const Text('Eliminar'),
                    ),
                  ],
                ),
              );

              if (ok == true) {
                try {
                  await LocalFileStorage.instance
                      .eliminarObservacionDir(item.local!.dir);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                        Text('Borrador local eliminado'),
                      ),
                    );
                  }
                  await refreshAfterNav?.call();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                        Text('Error al eliminar: $e'),
                      ),
                    );
                  }
                }
              }
            },
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Eliminar'),
          ),
        ],
      );
    } else {
      // Cloud: Ver/Editar/Aprobar/Eliminar según permisos
      final o = item.cloud!;
      final id = o.id!;
      final auth = context.read<AuthProvider>();
      final permisos = PermisosService(auth);

      final estado = (o.estado).toLowerCase();
      final bool soyAutor = (o.uidUsuario == auth.uid);

      const _editables = {EstadosObs.borrador, EstadosObs.rechazado};
      final bool canEdit =
          soyAutor && _editables.contains(estado);

      final bool canApprove = !soyAutor &&
          (estado == EstadosObs.pendiente ||
              estado == EstadosObs.revisarNuevo) &&
          permisos.canModeratePending(
            idProyecto: o.idProyecto,
            uidAutor: o.uidUsuario,
          );

      final bool canDelete = permisos.canDeleteObsV2(
        idProyecto: o.idProyecto,
        uidAutor: o.uidUsuario,
        estado: estado,
      );

      return Wrap(
        spacing: 10,
        runSpacing: 6,
        children: [
          TextButton.icon(
            onPressed: () {
              Navigator.pushNamed(
                context,
                '/observaciones/detalle',
                arguments: id,
              ).then((_) async => await refreshAfterNav?.call());
            },
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Ver'),
          ),
          if (canEdit)
            TextButton.icon(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  '/observaciones/edit',
                  arguments: id,
                ).then((_) async => await refreshAfterNav?.call());
              },
              icon:
              const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Editar'),
            ),
          if (canApprove)
            TextButton.icon(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  '/observaciones/aprobar',
                  arguments: id,
                ).then((_) async => await refreshAfterNav?.call());
              },
              icon: const Icon(Icons.verified_outlined, size: 18),
              label: const Text('Aprobar'),
            ),
          if (canDelete)
            TextButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    icon: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red,
                      size: 48,
                    ),
                    title:
                    const Text('Confirmar eliminación'),
                    content: const Text(
                      'Esta acción no se puede deshacer y eliminará '
                          'también la media y los logs asociados.\n\n'
                          '¿Deseas continuar?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            Navigator.of(ctx).pop(false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.delete_forever),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        onPressed: () =>
                            Navigator.of(ctx).pop(true),
                        label: const Text('Eliminar'),
                      ),
                    ],
                  ),
                );

                if (ok == true) {
                  try {
                    final auth = context.read<AuthProvider>();

                    FirestoreService fs;
                    try {
                      fs = context.read<FirestoreService>();
                    } catch (_) {
                      fs = FirestoreService();
                    }

                    await fs.deleteObservacion(
                      auth: auth,
                      id: id,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(
                        const SnackBar(
                          content: Text('Observación eliminada'),
                        ),
                      );
                    }
                    await refreshAfterNav?.call();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(
                        SnackBar(
                          content: Text(
                            'Error al eliminar: ${e.toString()}',
                          ),
                        ),
                      );
                    }
                  }
                }
              },
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Eliminar'),
            ),
        ],
      );
    }
  }
}

// ===== Convierte un _LocalObsItem en un modelo Observacion (para detalle_local) =====

Observacion _toObservacionLocal(_LocalObsItem lo) {
  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) {
      try {
        return DateTime.tryParse(v);
      } catch (_) {}
    }
    return null;
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  final m = lo.meta;

  // Trata de usar nombre científico, con fallback al común
  final cient =
  (m['especie_nombre_cientifico'] ?? m['especie_nombre'])
      ?.toString()
      .trim();
  final comun =
  (m['especie_nombre_comun'] ?? '')?.toString().trim();

  return Observacion(
    id: 'local:${lo.dir.path}', // marca única local
    estado:
    (lo.estado.isEmpty) ? EstadosObs.borrador : lo.estado,
    idProyecto:
    (lo.idProyecto ?? '').isEmpty ? null : lo.idProyecto,
    uidUsuario:
    (lo.uidUsuario.isEmpty) ? '' : lo.uidUsuario,
    especieNombreCientifico:
    (cient != null && cient.isNotEmpty) ? cient : null,
    especieNombreComun:
    (comun != null && comun.isNotEmpty) ? comun : null,
    lugarNombre:
    (m['lugar_nombre'] ?? '')?.toString().trim(),
    municipio:
    (m['municipio'] ?? '')?.toString().trim(),
    estadoPais:
    (m['estado_pais'] ?? '')?.toString().trim(),
    lat: _toDouble(m['lat']),
    lng: _toDouble(m['lng']),
    altitud: _toDouble(m['altitud']),
    fechaCaptura: _parseDate(m['fecha_captura']),
    createdAt: _parseDate(m['created_local_at']),
    updatedAt: _parseDate(
      m['updated_local_at'] ?? m['ultima_modificacion'],
    ),
    mediaUrls: const [],
  );
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

/// Publica una observación LOCAL a la nube usando el mismo flujo que "agregar".
Future<void> _publicarLocal({
  required BuildContext context,
  required AuthProvider auth,
  required FirestoreService fs, // por compat
  required _LocalObsItem item,
  required String? ctxProyectoId,
  bool mantenerEstado = true,
  bool borrarLocalDespues = false,
}) async {
  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  String? _nz(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  final prov = context.read<ObservacionProvider>();
  final fotoSvc = FotoService();
  final m = item.meta;

  // 0) Autenticación
  final uidActual = auth.uid ?? item.uidUsuario;
  if (uidActual.isEmpty) {
    throw 'No hay sesión activa para subir a la nube.';
  }

  // 1) Resolver proyecto
  final String? idProyecto =
  (ctxProyectoId != null && ctxProyectoId.isNotEmpty)
      ? ctxProyectoId
      : (item.idProyecto?.isNotEmpty == true
      ? item.idProyecto
      : null);

  // 2) Preparar Observacion para crear en cloud
  final cient =
  _nz(m['especie_nombre_cientifico'] ?? m['especie_nombre']);
  final comun = _nz(m['especie_nombre_comun']);

  final String estado = (mantenerEstado
      ? (m['estado'] ?? EstadosObs.borrador)
      : EstadosObs.borrador)
      .toString()
      .toLowerCase();

  final obs = Observacion(
    id: null,
    idProyecto: idProyecto,
    uidUsuario: uidActual,
    estado: estado,
    fechaCaptura: _parseDate(m['fecha_captura']),
    createdAt: _parseDate(m['created_local_at']),
    updatedAt:
    _parseDate(m['updated_local_at'] ?? m['ultima_modificacion']),
    especieId: _nz(m['especie_id']),
    especieNombreCientifico: cient,
    especieNombreComun: comun,
    lugarNombre: _nz(m['lugar_nombre']),
    lugarTipo: _nz(m['lugar_tipo']),
    municipio: _nz(m['municipio']),
    estadoPais: _nz(m['estado_pais'] ?? m['ubic_estado']),
    lat: _toDouble(m['lat']),
    lng: _toDouble(m['lng']),
    altitud: _toDouble(m['altitud']),
    notas: _nz(m['notas']),
    aiStatus: _nz(m['ai_status']) ?? 'idle',
    condicionAnimal:
    _nz(m['condicion_animal']) ?? EstadosAnimal.vivo,
    rastroTipo: _nz(m['rastro_tipo']),
    rastroDetalle: _nz(m['rastro_detalle']),
    mediaCount: null,
  );

  // 3) Crear documento con ObservacionProvider
  String? newId;
  if (obs.idProyecto == null) {
    newId = await prov.crearSinProyecto(data: obs);
  } else {
    newId = await prov.crearEnProyecto(
      proyectoId: obs.idProyecto!,
      data: obs,
    );
  }
  if (newId == null || newId.isEmpty) {
    throw 'No se pudo crear la observación en la nube.';
  }

  // 4) Patch de taxonomía si viene en meta
  try {
    await prov.patch(
      observacionId: newId,
      patch: {
        if (_nz(m['taxo_clase']) != null)
          'taxo_clase': _nz(m['taxo_clase']),
        if (_nz(m['taxo_orden']) != null)
          'taxo_orden': _nz(m['taxo_orden']),
        if (_nz(m['taxo_familia']) != null)
          'taxo_familia': _nz(m['taxo_familia']),
      },
      toast: false,
    );
  } catch (_) {}

  // 5) Subir fotos con FotoService
  final fotos = await LocalFileStorage.instance
      .listarFotos(item.dir);
  if (fotos.isNotEmpty) {
    try {
      final contextoTipo =
      (idProyecto == null || idProyecto.isEmpty)
          ? 'RESIDENCIA'
          : 'PROYECTO_INVESTIGACION';
      final contextoNombre =
      (idProyecto == null || idProyecto.isEmpty)
          ? (_nz(m['lugar_nombre']) ?? 'Sin nombre')
          : 'Proyecto $idProyecto';

      final subidas = await fotoSvc.subirVarias(
        fotografoUid: uidActual,
        fotografoNombre: uidActual,
        contextoTipo: contextoTipo,
        contextoNombre: contextoNombre,
        observacionId: newId,
        archivos: fotos,
      );

      final coverUrl =
      subidas.isNotEmpty ? subidas.first.url : null;
      await prov.patch(
        observacionId: newId,
        patch: {
          'media_count': subidas.length,
          'media_urls':
          subidas.map((m) => m.url).whereType<String>().toList(),
          if (coverUrl != null) 'cover_url': coverUrl,
          if (subidas.isNotEmpty)
            'primary_media_id': subidas.first.id,
          'updatedAt': DateTime.now(),
        },
        toast: false,
      );
    } catch (e) {
      rethrow;
    }
  }

  // 6) (Opcional) borrar carpeta local
  if (borrarLocalDespues) {
    try {
      await LocalFileStorage.instance
          .eliminarObservacionDir(item.dir);
    } catch (_) {/* ya publicada */}
  }
}

// ======== helpers externos ========

FirestoreService _resolveFS(BuildContext context) {
  try {
    return context.read<FirestoreService>();
  } catch (_) {
    return FirestoreService();
  }
}
