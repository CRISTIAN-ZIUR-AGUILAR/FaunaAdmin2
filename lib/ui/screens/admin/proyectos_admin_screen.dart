// lib/ui/screens/admin/proyectos_admin_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:faunadmin2/models/proyecto.dart';
import 'package:faunadmin2/models/rol.dart';
import 'package:faunadmin2/services/firestore_service.dart';

class ProyectosAdminScreen extends StatefulWidget {
  const ProyectosAdminScreen({super.key});

  @override
  State<ProyectosAdminScreen> createState() => _ProyectosAdminScreenState();
}

class _ProyectosAdminScreenState extends State<ProyectosAdminScreen> {
  final _fs = FirestoreService();

  String _search = '';
  String _estado = 'todos'; // todos | activos | inactivos
  String _categoria = 'todas'; // 'todas' o nombre exacto
  String _orden = 'nombre_asc'; // nombre_asc | nombre_desc

  Stream<List<Proyecto>> _streamAll() => _fs.streamProyectos();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Proyectos (Admin)'),
        actions: [
          IconButton(
            tooltip: 'Crear proyecto',
            onPressed: () => Navigator.pushNamed(context, '/proyectos/crear'),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: StreamBuilder<List<Proyecto>>(
        stream: _streamAll(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // Proyectos crudos
          final all = snap.data!;

          // Catálogo de categorías dinámico usando el campo denormalizado
          final categorias = <String>{
            for (final p in all)
              if ((p.categoriaNombre ?? '').trim().isNotEmpty)
                (p.categoriaNombre!).trim(),
          }.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          // Si el seleccionado ya no existe, volvemos a "todas"
          if (_categoria != 'todas' && !categorias.contains(_categoria)) {
            _categoria = 'todas';
          }

          // ---- Filtros sobre copia ----
          var items = List<Proyecto>.from(all);

          // Búsqueda (nombre, categoría, descripción)
          if (_search.isNotEmpty) {
            items = items.where((p) {
              final n = p.nombre.toLowerCase();
              final c = (p.categoriaNombre ?? '').toLowerCase();
              final d = (p.descripcion).toLowerCase();
              return n.contains(_search) || c.contains(_search) || d.contains(_search);
            }).toList();
          }

          // Estado
          if (_estado != 'todos') {
            final wantActive = _estado == 'activos';
            items = items.where((p) => (p.activo != false) == wantActive).toList();
          }

          // Categoría exacta (por nombre denormalizado)
          if (_categoria != 'todas') {
            items = items
                .where((p) => (p.categoriaNombre ?? '').trim() == _categoria)
                .toList();
          }

          // Orden
          items.sort((a, b) {
            final an = a.nombre.toLowerCase();
            final bn = b.nombre.toLowerCase();
            final byName = an.compareTo(bn);
            if (_orden == 'nombre_asc') return byName;
            if (_orden == 'nombre_desc') return -byName;
            return byName;
          });

          return Column(
            children: [
              _Filters(
                categorias: categorias,
                selectedCategoria: _categoria,
                orden: _orden,
                onSearchChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                onEstadoChanged: (v) => setState(() => _estado = v),
                onCategoriaChanged: (v) => setState(() => _categoria = v),
                onOrdenChanged: (v) => setState(() => _orden = v),
              ),
              const Divider(height: 1),
              if (items.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text('No hay proyectos con los filtros actuales.'),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (_, i) => _ProyectoTile(
                      p: items[i],
                      onOpenDetalle: () => Navigator.pushNamed(
                        context,
                        '/proyectos/detalle',
                        arguments: items[i].id,
                      ),
                      onOpenEquipo: () => Navigator.pushNamed(
                        context,
                        '/proyectos/equipo',
                        arguments: items[i].id,
                      ),
                      onEditar: () => Navigator.pushNamed(
                        context,
                        '/proyectos/edit',
                        arguments: items[i].id,
                      ),
                      onEliminar: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Eliminar proyecto'),
                            content: const Text(
                              'Se eliminarán vínculos, categorías y observaciones asociadas.\n'
                                  'Esta acción no se puede deshacer. ¿Continuar?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Eliminar'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          try {
                            await FirestoreService().deleteProyectoCascade(items[i].id!);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Proyecto eliminado')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error al eliminar: $e')),
                              );
                            }
                          }
                        }
                      },
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

class _Filters extends StatefulWidget {
  final List<String> categorias;          // opciones dinámicas
  final String selectedCategoria;         // valor actual
  final String orden;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onEstadoChanged;
  final ValueChanged<String> onCategoriaChanged;
  final ValueChanged<String> onOrdenChanged;

  const _Filters({
    required this.categorias,
    required this.selectedCategoria,
    required this.orden,
    required this.onSearchChanged,
    required this.onEstadoChanged,
    required this.onCategoriaChanged,
    required this.onOrdenChanged,
  });

  @override
  State<_Filters> createState() => _FiltersState();
}

class _FiltersState extends State<_Filters> {
  String _estado = 'todos';
  late String _categoria; // se inicializa con el seleccionado externo
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _categoria = widget.selectedCategoria;
  }

  @override
  void didUpdateWidget(covariant _Filters oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si las opciones cambian y el seleccionado ya no existe, volvemos a 'todas'
    if (_categoria != 'todas' && !widget.categorias.contains(_categoria)) {
      setState(() => _categoria = 'todas');
      widget.onCategoriaChanged('todas');
    }
    // Si el padre cambió el seleccionado explícitamente, lo reflejamos
    if (widget.selectedCategoria != _categoria) {
      _categoria = widget.selectedCategoria;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Opciones: “todas” + categorías encontradas
    final cats = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'todas', child: Text('Todas las categorías')),
      ...widget.categorias.map((c) => DropdownMenuItem(value: c, child: Text(c))),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Wrap(
        spacing: 14,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Buscador más ancho para desktop/web
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 320, maxWidth: 520),
            child: TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre, categoría o descripción…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: widget.onSearchChanged,
            ),
          ),
          DropdownButton<String>(
            value: _estado,
            items: const [
              DropdownMenuItem(value: 'todos', child: Text('Todos')),
              DropdownMenuItem(value: 'activos', child: Text('Activos')),
              DropdownMenuItem(value: 'inactivos', child: Text('Inactivos')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _estado = v);
              widget.onEstadoChanged(v);
            },
          ),
          DropdownButton<String>(
            value: _categoria,
            items: cats,
            onChanged: (v) {
              if (v == null) return;
              setState(() => _categoria = v);
              widget.onCategoriaChanged(v);
            },
          ),
          // Ordenar
          DropdownButton<String>(
            value: widget.orden,
            items: const [
              DropdownMenuItem(value: 'nombre_asc', child: Text('Ordenar: Nombre')),
              DropdownMenuItem(value: 'nombre_desc', child: Text('Ordenar: Nombre (Z→A)')),
            ],
            onChanged: (v) {
              if (v != null) widget.onOrdenChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

/// Mini modelo para mostrar datos del usuario (nombre/correo)
class _UserMini {
  final String uid;
  final String nombre;
  final String correo;
  _UserMini({required this.uid, required this.nombre, required this.correo});
}

class _ProyectoTile extends StatefulWidget {
  final Proyecto p;
  final VoidCallback onOpenDetalle;
  final VoidCallback onOpenEquipo;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;

  const _ProyectoTile({
    required this.p,
    required this.onOpenDetalle,
    required this.onOpenEquipo,
    required this.onEditar,
    required this.onEliminar,
  });

  @override
  State<_ProyectoTile> createState() => _ProyectoTileState();
}

class _ProyectoTileState extends State<_ProyectoTile> {
  final _db = FirebaseFirestore.instance;
  static final Map<String, Future<_UserMini?>> _userCache = {};

  Future<_UserMini?> _fetchUserMini(String uid) {
    return _userCache.putIfAbsent(uid, () async {
      try {
        final doc = await _db.collection('usuarios').doc(uid).get();
        if (!doc.exists) {
          return _UserMini(uid: uid, nombre: uid, correo: '');
        }
        final m = doc.data()!;
        String pickNombre(Map<String, dynamic> m) {
          final raw = (m['nombre_completo'] ??
              m['nombreCompleto'] ??
              m['displayName'] ??
              m['nombre'] ??
              '') as String;
          final v = raw.trim();
          return v.isEmpty ? uid : v;
        }

        String pickCorreo(Map<String, dynamic> m) {
          final raw = (m['correo'] ?? m['email'] ?? m['correo_electronico'] ?? '') as String;
          return raw.trim();
        }

        return _UserMini(uid: uid, nombre: pickNombre(m), correo: pickCorreo(m));
      } catch (_) {
        return _UserMini(uid: uid, nombre: uid, correo: '');
      }
    });
  }

  // ===== Chips dinámicos =====

  // Chip con conteo de colaboradores activos en URP
  Widget _colabCountChip(String proyectoId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('usuario_rol_proyecto')
          .where('id_proyecto', isEqualTo: proyectoId)
          .where('id_rol', isEqualTo: Rol.colaborador)
          .where('activo', isEqualTo: true)
          .snapshots(),
      builder: (context, snap) {
        final n = (snap.data?.docs.length ?? 0);
        return Chip(
          label: Text('Colabs: $n'),
          visualDensity: VisualDensity.compact,
        );
      },
    );
  }

  // Chip con presencia y conteo de supervisores activos en URP
  Widget _supervisorChip(String proyectoId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('usuario_rol_proyecto')
          .where('id_proyecto', isEqualTo: proyectoId)
          .where('id_rol', isEqualTo: Rol.supervisor)
          .where('activo', isEqualTo: true)
          .snapshots(),
      builder: (context, snap) {
        final n = (snap.data?.docs.length ?? 0);
        if (n > 0) {
          return Chip(
            label: Text(n == 1 ? 'Supervisor: 1' : 'Supervisores: $n'),
            visualDensity: VisualDensity.compact,
            avatar: const Icon(Icons.verified_user, size: 18),
          );
        }
        return Chip(
          label: const Text('Sin supervisor'),
          visualDensity: VisualDensity.compact,
          avatar: const Icon(Icons.warning_amber_rounded, size: 18),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;

    final nombre = p.nombre.trim().isNotEmpty ? p.nombre.trim() : 'Proyecto';
    final categoria = (p.categoriaNombre ?? '').trim();
    final activo = p.activo != false;
    final uidDueno = (p.uidDueno ?? '').trim();

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: widget.onOpenDetalle,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              blurRadius: 12,
              spreadRadius: 0,
              offset: const Offset(0, 3),
              color: Colors.black.withOpacity(0.07),
            ),
          ],
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(.18),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ícono grande
            CircleAvatar(
              radius: 26,
              backgroundColor: Colors.orange.withOpacity(.12),
              child: const Icon(Icons.workspaces_rounded, color: Colors.orange, size: 26),
            ),
            const SizedBox(width: 14),
            // Texto + chips
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nombre
                  Text(
                    nombre,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  // Chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (categoria.isNotEmpty)
                        Chip(
                          label: Text(categoria),
                          visualDensity: VisualDensity.compact,
                        ),
                      Chip(
                        label: Text(activo ? 'Activo' : 'Inactivo'),
                        visualDensity: VisualDensity.compact,
                      ),
                      if (p.id != null) _colabCountChip(p.id!),
                      if (p.id != null) _supervisorChip(p.id!),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Dueño
                  if (uidDueno.isNotEmpty)
                    FutureBuilder<_UserMini?>(
                      future: _fetchUserMini(uidDueno),
                      builder: (context, sn) {
                        final u = sn.data;
                        final texto = u == null
                            ? 'Dueño: cargando…'
                            : (u.correo.isNotEmpty
                            ? 'Dueño: ${u.nombre} · ${u.correo}'
                            : 'Dueño: ${u.nombre}');
                        return Text(
                          texto,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(.82),
                            fontSize: 13.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Acciones
            PopupMenuButton<String>(
              tooltip: 'Acciones',
              onSelected: (value) {
                switch (value) {
                  case 'detalle':
                    widget.onOpenDetalle();
                    break;
                  case 'equipo':
                    widget.onOpenEquipo();
                    break;
                  case 'editar':
                    widget.onEditar();
                    break;
                  case 'eliminar':
                    widget.onEliminar();
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'detalle', child: Text('Abrir detalle')),
                PopupMenuItem(value: 'equipo', child: Text('Equipo')),
                PopupMenuItem(value: 'editar', child: Text('Editar')),
                PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
              ],
              icon: Icon(Icons.more_vert, color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
